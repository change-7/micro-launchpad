import Foundation
import Observation

@MainActor
@Observable
final class CodexAppServerClient {
    static let usageRefreshInterval: TimeInterval = 30

    private(set) var activity: CodexActivity = .idle {
        didSet { publishRemoteState() }
    }
    private(set) var isConnected = false {
        didSet { publishRemoteState() }
    }
    private(set) var message = "Codex App Server에 연결하지 않았습니다." {
        didSet { publishRemoteState() }
    }
    private(set) var weeklyUsage: CodexWeeklyUsage? {
        didSet { publishRemoteState() }
    }
    private(set) var fiveHourUsage: CodexFiveHourUsage? {
        didSet { publishRemoteState() }
    }

    private let remoteBridge = CodexRemoteBridge()
    private var process: Process?
    private var input: FileHandle?
    private var output: Pipe?
    private var errorOutput: Pipe?
    private var nextRequestID = 1
    private var pendingOutput = Data()
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var activeThreadID: String?
    private var isUsingShellFallback = false
    private var desktopActivity: CodexActivity?
    private var pendingRemoteApproval: PendingRemoteApproval?
    private var remoteCompletionEventID = 0
    private var remoteActiveSessionCount = 0
    private var usageRefreshTask: Task<Void, Never>?
    private var remoteStateRefreshTask: Task<Void, Never>?
    private var lastUsageRefreshAt: Date?
    private var remoteSmartphonePagesProvider: () -> [SmartphonePage] = SmartphoneDefaults.persistedPages

    private struct PendingRemoteApproval {
        let requestID: Int
        let title: String
        let detail: String
        let responseKind: ResponseKind
        let requestedPermissions: [String: Any]?

        enum ResponseKind {
            case decision
            case permissions
        }
    }

    func startRemoteBridge() {
        remoteBridge.start()
        publishRemoteState()
        startRemoteStateRefreshLoop()
    }

    func setRemoteCommandHandler(_ handler: @escaping (CodexRemoteCommand) -> CodexRemoteCommandResult) {
        remoteBridge.onCommand = handler
    }

    func setRemoteSmartphonePagesProvider(_ provider: @escaping () -> [SmartphonePage]) {
        remoteSmartphonePagesProvider = provider
        publishRemoteState()
    }

    func stopRemoteBridge() {
        remoteStateRefreshTask?.cancel()
        remoteStateRefreshTask = nil
        remoteBridge.stop()
    }

    private func startRemoteStateRefreshLoop() {
        guard remoteStateRefreshTask == nil else { return }
        remoteStateRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.publishRemoteState()
            }
        }
    }

    func publishRemoteActivity(_ activity: CodexActivity) {
        desktopActivity = activity == .idle ? nil : activity
        publishRemoteState()
    }

    func publishRemoteCompletion(taskID: DesktopCodexTaskID) {
        remoteCompletionEventID += 1
        publishRemoteState()
    }

    func publishRemoteSessionCount(_ count: Int) {
        remoteActiveSessionCount = max(0, count)
        publishRemoteState()
    }

    func connect() {
        guard process == nil else { return }

        activity = .connecting
        message = "Codex App Server를 시작하는 중…"

        let launchedProcess = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        let command = Self.launchCommand { FileManager.default.isExecutableFile(atPath: $0) }
        isUsingShellFallback = command.executableURL.path == "/bin/zsh"
        launchedProcess.executableURL = command.executableURL
        launchedProcess.arguments = command.arguments
        launchedProcess.standardInput = inputPipe
        launchedProcess.standardOutput = outputPipe
        launchedProcess.standardError = errorPipe
        launchedProcess.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.handleTermination(status: process.terminationStatus)
            }
        }

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.consumeProtocolData(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            Task { @MainActor in
                self?.consumeDiagnostic(text)
            }
        }

        do {
            try launchedProcess.run()
            process = launchedProcess
            input = inputPipe.fileHandleForWriting
            output = outputPipe
            errorOutput = errorPipe
            sendRequest(
                method: "initialize",
                params: [
                    "clientInfo": ["name": "Micro Launchpad", "version": "1.0"],
                    "capabilities": [:]
                ],
                kind: .initialize
            )
        } catch {
            activity = .failed
            message = "Codex를 시작하지 못했습니다: \(error.localizedDescription)"
            cleanUpProcess()
        }
    }

    func disconnect() {
        guard process != nil else { return }
        message = "Codex 연결을 종료했습니다."
        cleanUpProcess()
        isConnected = false
        activity = .idle
        weeklyUsage = nil
        fiveHourUsage = nil
    }

    func startTask(prompt: String, workingDirectory: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDirectory = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConnected else {
            message = "먼저 Codex App Server에 연결하세요."
            return
        }
        guard !trimmedPrompt.isEmpty else {
            message = "Codex에 보낼 작업 내용을 입력하세요."
            return
        }
        guard trimmedDirectory.hasPrefix("/"), FileManager.default.fileExists(atPath: trimmedDirectory) else {
            message = "작업 폴더의 절대 경로를 확인하세요."
            return
        }

        desktopActivity = nil
        activity = .running
        message = "Codex 작업을 시작하는 중…"
        if let activeThreadID {
            startTurn(threadID: activeThreadID, prompt: trimmedPrompt, workingDirectory: trimmedDirectory)
        } else {
            sendRequest(
                method: "thread/start",
                params: [
                    "cwd": trimmedDirectory,
                    "approvalPolicy": "on-request"
                ],
                kind: .threadStart(prompt: trimmedPrompt, workingDirectory: trimmedDirectory)
            )
        }
    }

    func refreshWeeklyUsage() {
        guard isConnected,
              !pendingRequests.values.contains(where: { request in
                  if case .weeklyUsage = request { return true }
                  return false
              }) else { return }
        lastUsageRefreshAt = Date()
        sendRequest(method: "account/rateLimits/read", params: [:], kind: .weeklyUsage)
    }

    private func startUsageRefreshLoop() {
        guard usageRefreshTask == nil else { return }
        usageRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.usageRefreshInterval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                guard self.isConnected,
                      Self.shouldRefreshUsage(lastRefreshAt: self.lastUsageRefreshAt, now: Date()) else { continue }
                self.refreshWeeklyUsage()
            }
        }
    }

    private func startTurn(threadID: String, prompt: String, workingDirectory: String) {
        sendRequest(
            method: "turn/start",
            params: [
                "threadId": threadID,
                "cwd": workingDirectory,
                "approvalPolicy": "on-request",
                "input": [["type": "text", "text": prompt]]
            ],
            kind: .turnStart
        )
    }

    private func sendRequest(method: String, params: [String: Any], kind: PendingRequest) {
        let requestID = nextRequestID
        nextRequestID += 1
        pendingRequests[requestID] = kind
        write(["id": requestID, "method": method, "params": params])
    }

    private func sendNotification(method: String, params: [String: Any]) {
        write(["method": method, "params": params])
    }

    private func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object), var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        input?.write(line.data(using: .utf8) ?? Data())
    }

    private func consumeProtocolData(_ data: Data) {
        pendingOutput.append(data)
        while let newlineIndex = pendingOutput.firstIndex(of: 10) {
            let line = pendingOutput.prefix(upTo: newlineIndex)
            pendingOutput.removeSubrange(...newlineIndex)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handleProtocolObject(object)
        }
    }

    private func handleProtocolObject(_ object: [String: Any]) {
        if let method = object["method"] as? String {
            if method == "initialize" {
                sendNotification(method: "initialized", params: [:])
                isConnected = true
                activity = .idle
                message = "Codex App Server 연결됨"
                refreshWeeklyUsage()
                startUsageRefreshLoop()
                return
            }
            if let requestID = object["id"] as? Int,
               Self.isRemoteApprovalRequest(method) {
                let params = object["params"] as? [String: Any] ?? [:]
                pendingRemoteApproval = PendingRemoteApproval(
                    requestID: requestID,
                    title: Self.remoteApprovalTitle(for: method),
                    detail: Self.remoteApprovalDetail(from: params),
                    responseKind: method.lowercased().contains("permissions") ? .permissions : .decision,
                    requestedPermissions: params["permissions"] as? [String: Any]
                )
                if Self.shouldResetDesktopActivity(
                    for: .waitingForApproval,
                    desktopActivity: desktopActivity,
                    previousAppServerActivity: activity
                ) {
                    desktopActivity = nil
                }
                activity = .waitingForApproval
                message = "Codex 승인을 기다리는 중"
                return
            }
            if method == "serverRequest/resolved" {
                if let params = object["params"] as? [String: Any],
                   let requestID = params["requestId"] as? Int,
                   pendingRemoteApproval?.requestID == requestID {
                    pendingRemoteApproval = nil
                }
                return
            }
            if let eventActivity = CodexEventReducer.activity(for: method) {
                let previousAppServerActivity = activity
                if eventActivity != .waitingForApproval {
                    pendingRemoteApproval = nil
                }
                if Self.shouldResetDesktopActivity(
                    for: eventActivity,
                    desktopActivity: desktopActivity,
                    previousAppServerActivity: previousAppServerActivity
                ) {
                    // A new App Server turn supersedes the previous desktop completion.
                    // Without clearing this terminal value, the remote bridge can keep
                    // reporting COMPLETED until the transcript monitor catches up.
                    desktopActivity = nil
                }
                activity = eventActivity
                message = "Codex: \(eventActivity.title)"
            }
            return
        }

        guard let requestID = object["id"] as? Int,
              let request = pendingRequests.removeValue(forKey: requestID) else { return }
        if let error = object["error"] as? [String: Any] {
            if case .weeklyUsage = request {
                // Rate-limit reads can fail transiently while a turn is
                // starting. Keep the last successful values for the remote UI.
                return
            }
            activity = .failed
            message = "Codex 오류: \((error["message"] as? String) ?? "알 수 없는 오류")"
            return
        }

        switch request {
        case .initialize:
            sendNotification(method: "initialized", params: [:])
            isConnected = true
            activity = .idle
            message = "Codex App Server 연결됨"
            refreshWeeklyUsage()
            startUsageRefreshLoop()
        case let .threadStart(prompt, workingDirectory):
            guard let result = object["result"] as? [String: Any],
                  let thread = result["thread"] as? [String: Any],
                  let threadID = thread["id"] as? String else {
                activity = .failed
                message = "Codex 스레드를 만들지 못했습니다."
                return
            }
            activeThreadID = threadID
            startTurn(threadID: threadID, prompt: prompt, workingDirectory: workingDirectory)
        case .turnStart:
            desktopActivity = nil
            activity = .running
            message = "Codex 작업 중"
        case .weeklyUsage:
            let usage = Self.usage(from: object["result"] as? [String: Any])
            fiveHourUsage = Self.retainedUsage(existing: fiveHourUsage, refreshed: usage.fiveHour)
            weeklyUsage = Self.retainedUsage(existing: weeklyUsage, refreshed: usage.weekly)
        }
    }

    func respondToRemoteApproval(decision: String) -> (success: Bool, message: String) {
        let normalizedDecision = decision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["accept", "acceptForSession", "decline", "cancel"].contains(normalizedDecision) else {
            return (false, "지원하지 않는 승인 응답입니다.")
        }
        guard isConnected, let pendingApproval = pendingRemoteApproval else {
            return (false, "현재 대기 중인 Codex 승인 요청이 없습니다.")
        }

        pendingRemoteApproval = nil
        let result: [String: Any]
        switch pendingApproval.responseKind {
        case .decision:
            result = ["decision": normalizedDecision]
        case .permissions:
            let approved = normalizedDecision == "accept" || normalizedDecision == "acceptForSession"
            result = [
                "scope": normalizedDecision == "acceptForSession" ? "session" : "turn",
                "permissions": approved ? (pendingApproval.requestedPermissions ?? [:]) : [:]
            ]
        }
        write(["id": pendingApproval.requestID, "result": result])
        activity = .running
        message = normalizedDecision == "accept" || normalizedDecision == "acceptForSession"
            ? "Codex 승인을 전송했습니다."
            : "Codex 거부를 전송했습니다."
        return (true, message)
    }

    private func consumeDiagnostic(_ text: String) {
        guard !isConnected,
              Self.isMissingCLIDiagnostic(text, isUsingShellFallback: isUsingShellFallback) else { return }
        activity = .failed
        message = "Codex CLI가 설치되어 있지 않습니다. 터미널에서 npm install -g @openai/codex 를 실행하세요."
    }

    static func isMissingCLIDiagnostic(_ diagnostic: String, isUsingShellFallback: Bool) -> Bool {
        guard isUsingShellFallback else { return false }
        let normalizedDiagnostic = diagnostic.lowercased()
        return normalizedDiagnostic.contains("command not found: codex")
            || normalizedDiagnostic.contains("exec: codex: not found")
    }

    private func handleTermination(status: Int32) {
        guard process != nil else { return }
        isConnected = false
        if activity != .failed {
            activity = .failed
            message = "Codex App Server가 종료되었습니다. (종료 코드 \(status))"
        }
        cleanUpProcess()
    }

    private func cleanUpProcess() {
        usageRefreshTask?.cancel()
        usageRefreshTask = nil
        lastUsageRefreshAt = nil
        output?.fileHandleForReading.readabilityHandler = nil
        errorOutput?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        input = nil
        output = nil
        errorOutput = nil
        pendingOutput.removeAll(keepingCapacity: false)
        pendingRequests.removeAll(keepingCapacity: false)
        activeThreadID = nil
        pendingRemoteApproval = nil
        isUsingShellFallback = false
    }

    static func retainedUsage<T>(existing: T?, refreshed: T?) -> T? {
        refreshed ?? existing
    }

    private static func isRemoteApprovalRequest(_ method: String) -> Bool {
        let normalized = method.lowercased()
        return normalized.contains("requestapproval") || normalized.contains("confirmation")
    }

    private static func remoteApprovalTitle(for method: String) -> String {
        let normalized = method.lowercased()
        if normalized.contains("filechange") {
            return "파일 변경 승인 필요"
        }
        if normalized.contains("permission") {
            return "권한 승인 필요"
        }
        return "Codex 승인 필요"
    }

    private static func remoteApprovalDetail(from params: [String: Any]) -> String {
        var parts = [String]()
        if let reason = params["reason"] as? String, !reason.isEmpty {
            parts.append(reason)
        }
        if let command = params["command"] as? String, !command.isEmpty {
            parts.append(command)
        }
        if let cwd = params["cwd"] as? String, !cwd.isEmpty {
            parts.append("위치: \(cwd)")
        }
        return parts.isEmpty ? "Codex가 계속 진행하려면 확인이 필요합니다." : parts.joined(separator: "\n")
    }

    func publishRemoteState() {
        let smartphonePages = remoteSmartphonePagesProvider()
        let remoteActivity = Self.remoteActivity(
            desktopActivity: desktopActivity,
            appServerActivity: activity,
            hasPendingApproval: pendingRemoteApproval != nil
        )
        let remoteMessage = Self.remoteMessage(
            for: remoteActivity,
            activeSessionCount: remoteActiveSessionCount,
            fallbackMessage: message
        )
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: isConnected,
            activity: remoteActivity,
            message: remoteMessage,
            weeklyUsage: weeklyUsage,
            fiveHourUsage: fiveHourUsage,
            smartphonePages: smartphonePages,
            smartphoneIconAssets: SmartphoneIconAssetProvider.assets(for: smartphonePages),
            approval: pendingRemoteApproval.map {
                CodexRemoteApproval(requestID: $0.requestID, title: $0.title, detail: $0.detail)
            },
            completionEventID: remoteCompletionEventID,
            activeSessionCount: remoteActiveSessionCount
        )
        remoteBridge.publish(state)
    }

    static func remoteActivity(
        desktopActivity: CodexActivity?,
        appServerActivity: CodexActivity,
        hasPendingApproval: Bool
    ) -> CodexActivity {
        if hasPendingApproval { return .waitingForApproval }
        if let desktopActivity {
            switch desktopActivity {
            case .completed, .failed:
                // The app-server can remain on its last running notification
                // after the transcript monitor has observed the terminal event.
                return desktopActivity
            case .idle, .connecting, .running, .waitingForApproval:
                break
            }
        }
        switch appServerActivity {
        case .connecting, .running, .waitingForApproval:
            return appServerActivity
        case .idle, .completed, .failed:
            return desktopActivity ?? appServerActivity
        }
    }

    static func remoteMessage(
        for activity: CodexActivity,
        activeSessionCount: Int,
        fallbackMessage: String
    ) -> String {
        switch activity {
        case .connecting: "Codex App Server를 시작하는 중…"
        case .running:
            activeSessionCount > 1 ? "\(activeSessionCount)개 작업 중" : "Codex 작업 중"
        case .waitingForApproval:
            activeSessionCount > 1 ? "\(activeSessionCount)개 작업 중 · 승인 대기" : "Codex 승인을 기다리는 중"
        case .completed: "Codex 작업 완료"
        case .failed, .idle: fallbackMessage
        }
    }

    static func weeklyUsage(from result: [String: Any]?) -> CodexWeeklyUsage? {
        usage(from: result).weekly
    }

    static func shouldRefreshUsage(lastRefreshAt: Date?, now: Date, interval: TimeInterval = usageRefreshInterval) -> Bool {
        guard let lastRefreshAt else { return true }
        return now.timeIntervalSince(lastRefreshAt) >= interval
    }

    static func shouldResetDesktopActivity(
        for appServerActivity: CodexActivity,
        desktopActivity: CodexActivity?,
        previousAppServerActivity: CodexActivity? = nil
    ) -> Bool {
        guard desktopActivity == .completed else { return false }
        switch appServerActivity {
        case .connecting, .running, .waitingForApproval:
            switch previousAppServerActivity {
            case .connecting, .running, .waitingForApproval:
                return false
            case .idle, .completed, .failed, nil:
                return true
            }
        case .idle, .completed, .failed:
            return false
        }
    }

    static func usage(from result: [String: Any]?) -> (fiveHour: CodexFiveHourUsage?, weekly: CodexWeeklyUsage?) {
        guard let result else { return (fiveHour: nil, weekly: nil) }
        var candidates = [[String: Any]]()
        var preferredLimitID: String?
        if let rateLimits = result["rateLimits"] as? [String: Any] {
            preferredLimitID = rateLimits["limitId"] as? String ?? "codex"
            candidates.append(rateLimits)
        }
        if let rateLimitsByLimitID = result["rateLimitsByLimitId"] as? [String: [String: Any]] {
            let limitID = preferredLimitID ?? "codex"
            if let preferred = rateLimitsByLimitID[limitID] {
                candidates.append(preferred)
            }
        }
        var fiveHour: CodexFiveHourUsage?
        var weekly: CodexWeeklyUsage?
        for limit in candidates {
            for windowKey in ["primary", "secondary"] {
                guard let window = limit[windowKey] as? [String: Any],
                      let duration = number(window["windowDurationMins"]),
                      let usedPercent = number(window["usedPercent"]) else { continue }
                let resetsAt = number(window["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
                let roundedUsedPercent = Int(usedPercent.rounded())
                if duration == 300 {
                    fiveHour = CodexFiveHourUsage(usedPercent: roundedUsedPercent, resetsAt: resetsAt)
                } else if duration == 10_080 {
                    weekly = CodexWeeklyUsage(usedPercent: roundedUsedPercent, resetsAt: resetsAt)
                }
            }
        }
        return (fiveHour: fiveHour, weekly: weekly)
    }

    private static func number(_ value: Any?) -> TimeInterval? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    static func launchCommand(isExecutable: (String) -> Bool) -> (executableURL: URL, arguments: [String]) {
        let supportDirectory = NSHomeDirectory() + "/Library/Application Support/마이크로 런치패드/codex-runtime/node_modules"
        let executablePaths = [
            supportDirectory + "/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        ]
        if let executablePath = executablePaths.first(where: isExecutable) {
            return (URL(fileURLWithPath: executablePath), ["app-server"])
        }
        return (URL(fileURLWithPath: "/bin/zsh"), ["-lc", "exec codex app-server"])
    }

    private enum PendingRequest {
        case initialize
        case threadStart(prompt: String, workingDirectory: String)
        case turnStart
        case weeklyUsage
    }
}
