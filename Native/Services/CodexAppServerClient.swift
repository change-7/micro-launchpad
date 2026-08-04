import Foundation
import Observation

@MainActor
@Observable
final class CodexAppServerClient {
    private(set) var activity: CodexActivity = .idle
    private(set) var isConnected = false
    private(set) var message = "Codex App Server에 연결하지 않았습니다."
    private(set) var weeklyUsage: CodexWeeklyUsage?

    private var process: Process?
    private var input: FileHandle?
    private var output: Pipe?
    private var errorOutput: Pipe?
    private var nextRequestID = 1
    private var pendingOutput = Data()
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var activeThreadID: String?
    private var isUsingShellFallback = false

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
        sendRequest(method: "account/rateLimits/read", params: [:], kind: .weeklyUsage)
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
                return
            }
            if let eventActivity = CodexEventReducer.activity(for: method) {
                activity = eventActivity
                message = "Codex: \(eventActivity.title)"
            }
            return
        }

        guard let requestID = object["id"] as? Int,
              let request = pendingRequests.removeValue(forKey: requestID) else { return }
        if let error = object["error"] as? [String: Any] {
            if case .weeklyUsage = request {
                weeklyUsage = nil
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
            activity = .running
            message = "Codex 작업 중"
        case .weeklyUsage:
            weeklyUsage = Self.weeklyUsage(from: object["result"] as? [String: Any])
        }
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
        isUsingShellFallback = false
        weeklyUsage = nil
    }

    static func weeklyUsage(from result: [String: Any]?) -> CodexWeeklyUsage? {
        guard let result else { return nil }
        var candidates = [[String: Any]]()
        if let rateLimits = result["rateLimits"] as? [String: Any] {
            candidates.append(rateLimits)
        }
        if let rateLimitsByLimitID = result["rateLimitsByLimitId"] as? [String: [String: Any]] {
            candidates.append(contentsOf: rateLimitsByLimitID.values)
        }
        for limit in candidates {
            for windowKey in ["primary", "secondary"] {
                guard let window = limit[windowKey] as? [String: Any],
                      let duration = number(window["windowDurationMins"]), duration == 10_080,
                      let usedPercent = number(window["usedPercent"]) else { continue }
                let resetsAt = number(window["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
                return CodexWeeklyUsage(usedPercent: Int(usedPercent.rounded()), resetsAt: resetsAt)
            }
        }
        return nil
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
