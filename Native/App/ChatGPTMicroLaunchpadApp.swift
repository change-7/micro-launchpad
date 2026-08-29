import AppKit
import Observation
import SwiftUI

@main
struct ChatGPTMicroLaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = LaunchpadStore()
    @State private var midi = LaunchpadMIDIManager()
    private let runner = MacActionRunner()

    var body: some Scene {
        WindowGroup {
            ContentView(
                store: store,
                runner: runner,
                midi: midi,
                codex: appDelegate.codex,
                codexActivity: appDelegate.codexActivityController,
                launchpadLEDBubble: appDelegate.launchpadLEDBubble
            )
                .preferredColorScheme(.dark)
                .frame(width: 1120, height: 860)
        }
        .defaultSize(width: 1120, height: 860)
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("런치패드") {
                Button("설정 창 열기") { appDelegate.showMainWindow() }
                    .keyboardShortcut(",", modifiers: [.command])
                Button("단축키 권한 요청") { runner.requestAccessibilityPermission() }
            }

            CommandGroup(replacing: .appTermination) {
                Button("창 닫기") { appDelegate.hideMainWindow() }
                    .keyboardShortcut("q", modifiers: [.command])
            }
        }
    }
}

@MainActor
protocol CodexAppServerConnectionStarting: AnyObject {
    func connect()
    func startTask(prompt: String, workingDirectory: String)
}

extension CodexAppServerClient: CodexAppServerConnectionStarting {}

@MainActor
@Observable
final class CodexActivityController {
    typealias MakeMonitor = (@escaping ([DesktopCodexTaskLifecycleEvent]) -> Void) -> CodexDesktopTaskMonitor

    private(set) var activity: CodexActivity = .idle
    private(set) var activeSessionCount = 0
    @ObservationIgnored var onActivityChange: ((CodexActivity) -> Void)?
    @ObservationIgnored var onTaskCompletion: ((DesktopCodexTaskID) -> Void)?
    @ObservationIgnored var onActiveSessionCountChange: ((Int) -> Void)?
    @ObservationIgnored private let makeMonitor: MakeMonitor
    @ObservationIgnored private var coordinator = CodexActivityCoordinator()
    @ObservationIgnored private var appServerActivity: CodexActivity = .idle
    @ObservationIgnored private var desktopMonitor: CodexDesktopTaskMonitor?

    convenience init() {
        let sessionsRootURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        self.init(makeMonitor: { onEvents in
            CodexDesktopTaskMonitor(sessionsRootURL: sessionsRootURL, onEvents: onEvents)
        })
    }

    init(makeMonitor: @escaping MakeMonitor) {
        self.makeMonitor = makeMonitor
    }

    func startDesktopMonitoring() {
        guard desktopMonitor == nil else { return }
        let monitor = makeMonitor { [weak self] events in
            self?.consumeDesktopEvents(events)
        }
        desktopMonitor = monitor
        monitor.start()
    }

    func stopDesktopMonitoring() {
        desktopMonitor?.stop()
        desktopMonitor = nil
        activeDesktopSessionIDs.removeAll()
        coordinator = CodexActivityCoordinator()
        updateActiveSessionCount()
        publish(coordinator.updateAppServerActivity(appServerActivity))
    }

    func updateAppServerActivity(_ activity: CodexActivity) {
        appServerActivity = activity
        updateActiveSessionCount()
        publish(coordinator.updateAppServerActivity(activity))
    }

    private func consumeDesktopEvents(_ events: [DesktopCodexTaskLifecycleEvent]) {
        let nextActivity = coordinator.consume(events)
        updateDesktopSessionSet(with: events)
        publish(nextActivity)
        updateActiveSessionCount()
        for event in events {
            if case let .completed(taskID) = event {
                onTaskCompletion?(taskID)
            }
        }
    }

    @ObservationIgnored private var activeDesktopSessionIDs: Set<DesktopCodexTaskID> = []

    private func updateDesktopSessionSet(with events: [DesktopCodexTaskLifecycleEvent]) {
        for event in events {
            switch event {
            case let .started(taskID): activeDesktopSessionIDs.insert(taskID)
            case let .completed(taskID): activeDesktopSessionIDs.remove(taskID)
            }
        }
    }

    private func updateActiveSessionCount() {
        let nextCount: Int
        if !activeDesktopSessionIDs.isEmpty {
            nextCount = activeDesktopSessionIDs.count
        } else {
            nextCount = switch appServerActivity {
            case .connecting, .running, .waitingForApproval: 1
            case .idle, .completed, .failed: 0
            }
        }
        guard activeSessionCount != nextCount else { return }
        activeSessionCount = nextCount
        onActiveSessionCountChange?(nextCount)
    }

    private func publish(_ nextActivity: CodexActivity) {
        guard activity != nextActivity else { return }
        activity = nextActivity
        onActivityChange?(nextActivity)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var isBridgeOnly: Bool { CommandLine.arguments.contains("--bridge-only") }
    let codex: CodexAppServerClient
    let codexActivityController: CodexActivityController
    let launchpadLEDBubble = LaunchpadLEDStatusBubble()
    private let remoteActionRunner = MacActionRunner()
    private let connectionStarter: any CodexAppServerConnectionStarting
    private weak var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private weak var launchpadLEDBubbleMenuItem: NSMenuItem?
    private var allowsTermination = false
    private var hasStartedCodexConnection = false

    override init() {
        let codex = CodexAppServerClient()
        self.codex = codex
        connectionStarter = codex
        codexActivityController = CodexActivityController()
        super.init()
        configureLaunchpadLEDBubbleMenuUpdates()
        configureRemoteCommandHandling()
    }

    init(
        codexActivityController: CodexActivityController,
        connectionStarter: (any CodexAppServerConnectionStarting)? = nil
    ) {
        let codex = CodexAppServerClient()
        self.codex = codex
        self.codexActivityController = codexActivityController
        self.connectionStarter = connectionStarter ?? codex
        super.init()
        configureLaunchpadLEDBubbleMenuUpdates()
        configureRemoteCommandHandling()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        if isBridgeOnly {
            NSApp.setActivationPolicy(.prohibited)
        } else {
            installMenuBarItem()
        }
        codexActivityController.onActivityChange = { [weak codex] activity in
            codex?.publishRemoteActivity(activity)
        }
        codexActivityController.onTaskCompletion = { [weak codex] taskID in
            codex?.publishRemoteCompletion(taskID: taskID)
        }
        codexActivityController.onActiveSessionCountChange = { [weak codex] count in
            codex?.publishRemoteSessionCount(count)
        }
        codexActivityController.startDesktopMonitoring()
        codex.publishRemoteSessionCount(codexActivityController.activeSessionCount)
        codex.publishRemoteActivity(codexActivityController.activity)
        codex.startRemoteBridge()
        guard !hasStartedCodexConnection else { return }
        hasStartedCodexConnection = true
        connectionStarter.connect()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isBridgeOnly {
            DispatchQueue.main.async {
                NSApp.windows.forEach { $0.orderOut(nil) }
            }
            return
        }
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard let window = Self.mainApplicationWindow(in: NSApp.windows) else { return }

            self.mainWindow = window
            window.delegate = self

            guard let screen = NSScreen.main else { return }

            let visibleFrame = screen.visibleFrame.insetBy(dx: 18, dy: 18)
            let size = NSSize(
                width: min(window.frame.width, visibleFrame.width),
                height: min(window.frame.height, visibleFrame.height)
            )
            let origin = NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: size), display: true)
            window.makeKeyAndOrderFront(nil)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        launchpadLEDBubble.close()
        codexActivityController.stopDesktopMonitoring()
        codex.stopRemoteBridge()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard allowsTermination else {
            hideMainWindow()
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func showMainWindow() {
        let window = mainWindow ?? Self.mainApplicationWindow(in: NSApp.windows)
        guard let window else { return }
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    func hideMainWindow() {
        mainWindow?.orderOut(nil)
    }

    static func mainApplicationWindow(in windows: [NSWindow]) -> NSWindow? {
        windows.first { !($0 is NSPanel) && $0.styleMask.contains(.titled) }
    }

    func quitCompletely() {
        allowsTermination = true
        NSApp.terminate(nil)
    }

    private func configureRemoteCommandHandling() {
        codex.setRemoteCommandHandler { [weak self] command in
            guard let self else {
                return CodexRemoteCommandResult(id: command.id, success: false, message: "Mac 명령 처리기를 사용할 수 없습니다.")
            }
            return self.handleRemoteCommand(command)
        }
    }

    private func handleRemoteCommand(_ command: CodexRemoteCommand) -> CodexRemoteCommandResult {
        do {
            let message: String
            switch command.command {
            case "smartphoneButton":
                guard let action = command.action else {
                    return CodexRemoteCommandResult(id: command.id, success: false, message: "스마트폰 버튼 동작이 없습니다.")
                }
                message = try remoteActionRunner.execute(action)
            case "codexApproval":
                guard let decision = command.decision else {
                    return CodexRemoteCommandResult(id: command.id, success: false, message: "Codex 승인 응답이 없습니다.")
                }
                let response = codex.respondToRemoteApproval(decision: decision)
                guard response.success else {
                    return CodexRemoteCommandResult(id: command.id, success: false, message: response.message)
                }
                message = response.message
            case "run":
                message = try remoteActionRunner.execute(PadAction(kind: .shortcut, value: "cmd+r"))
            case "pause":
                message = try remoteActionRunner.execute(PadAction(kind: .shortcut, value: "space"))
            case "stop":
                message = try remoteActionRunner.execute(PadAction(kind: .shortcut, value: "escape"))
            case "terminal":
                message = try remoteActionRunner.execute(PadAction(kind: .app, value: "com.apple.Terminal"))
            case "browser":
                guard let url = URL(string: "https://www.apple.com") else { throw MacActionError.invalidAddress }
                NSWorkspace.shared.open(url)
                message = "기본 브라우저를 열었습니다."
            case "files":
                message = try remoteActionRunner.execute(PadAction(kind: .app, value: "com.apple.finder"))
            case "search":
                message = try remoteActionRunner.execute(PadAction(kind: .shortcut, value: "cmd+space"))
            case "capture":
                message = try remoteActionRunner.execute(PadAction(kind: .shortcut, value: "cmd+shift+4"))
            case "clipboard":
                message = try remoteActionRunner.execute(PadAction(kind: .shortcut, value: "cmd+v"))
            case "music":
                message = try remoteActionRunner.execute(PadAction(kind: .app, value: "com.apple.Music"))
            case "volume":
                message = try remoteActionRunner.execute(PadAction(kind: .shortcut, value: "volumeup"))
            case "focus":
                guard let url = URL(string: "x-apple.systempreferences:com.apple.Focus") else { throw MacActionError.invalidAddress }
                NSWorkspace.shared.open(url)
                message = "집중 모드 설정을 열었습니다."
            case "settings":
                message = try remoteActionRunner.execute(PadAction(kind: .app, value: "com.apple.systempreferences"))
            case "more":
                message = "추가 동작은 Mac 앱에서 매핑하세요."
            default:
                return CodexRemoteCommandResult(id: command.id, success: false, message: "지원하지 않는 버튼입니다.")
            }
            return CodexRemoteCommandResult(id: command.id, success: true, message: message)
        } catch {
            return CodexRemoteCommandResult(id: command.id, success: false, message: error.localizedDescription)
        }
    }

    private func installMenuBarItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "square.grid.3x3.fill",
            accessibilityDescription: "마이크로 런치패드"
        )
        let menu = NSMenu()
        menu.addItem(withTitle: "설정 창 열기", action: #selector(openMainWindowFromMenu), keyEquivalent: "")
        let bubbleItem = menu.addItem(
            withTitle: "LED 말풍선 표시",
            action: #selector(toggleLaunchpadLEDBubbleFromMenu),
            keyEquivalent: ""
        )
        bubbleItem.state = .off
        bubbleItem.isEnabled = false
        launchpadLEDBubbleMenuItem = bubbleItem
        menu.addItem(.separator())
        menu.addItem(withTitle: "완전히 종료", action: #selector(quitFromMenu), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
        launchpadLEDBubble.attach(to: item.button)
    }

    @objc private func openMainWindowFromMenu() {
        showMainWindow()
    }

    @objc private func quitFromMenu() {
        quitCompletely()
    }

    @objc private func toggleLaunchpadLEDBubbleFromMenu() {
        launchpadLEDBubble.toggleVisibilityPreference()
    }

    private func configureLaunchpadLEDBubbleMenuUpdates() {
        launchpadLEDBubble.onVisibilityPreferenceChanged = { [weak self] isVisible, isReady in
            self?.launchpadLEDBubbleMenuItem?.state = isVisible ? .on : .off
            self?.launchpadLEDBubbleMenuItem?.isEnabled = isReady
        }
    }
}
