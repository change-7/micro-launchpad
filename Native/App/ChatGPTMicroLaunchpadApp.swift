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
    @ObservationIgnored var onActivityChange: ((CodexActivity) -> Void)?
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
        coordinator = CodexActivityCoordinator()
        publish(coordinator.updateAppServerActivity(appServerActivity))
    }

    func updateAppServerActivity(_ activity: CodexActivity) {
        appServerActivity = activity
        publish(coordinator.updateAppServerActivity(activity))
    }

    private func consumeDesktopEvents(_ events: [DesktopCodexTaskLifecycleEvent]) {
        publish(coordinator.consume(events))
    }

    private func publish(_ nextActivity: CodexActivity) {
        guard activity != nextActivity else { return }
        activity = nextActivity
        onActivityChange?(nextActivity)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let codex: CodexAppServerClient
    let codexActivityController: CodexActivityController
    let launchpadLEDBubble = LaunchpadLEDStatusBubble()
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
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        installMenuBarItem()
        codexActivityController.startDesktopMonitoring()
        guard !hasStartedCodexConnection else { return }
        hasStartedCodexConnection = true
        connectionStarter.connect()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
