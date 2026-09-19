import AppKit

enum MacWindowAction: String, CaseIterable, Identifiable, Equatable {
    case leftHalf = "ctrl+fn+left"
    case rightHalf = "ctrl+fn+right"
    case topHalf = "ctrl+fn+up"
    case bottomHalf = "ctrl+fn+down"
    case nextDisplay = "ctrl+fn+shift+right"
    case fill = "ctrl+fn+f"
    case fullScreen = "window:full-screen"

    init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "ctrl+fn+left", "ctrl+globe+left", "window:left-half": self = .leftHalf
        case "ctrl+fn+right", "ctrl+globe+right", "window:right-half": self = .rightHalf
        case "ctrl+fn+up", "ctrl+globe+up", "window:top-half": self = .topHalf
        case "ctrl+fn+down", "ctrl+globe+down", "window:bottom-half": self = .bottomHalf
        case "ctrl+fn+shift+right", "ctrl+globe+shift+right", "window:next-display": self = .nextDisplay
        case "ctrl+fn+f", "ctrl+globe+f", "window:fill": self = .fill
        case "window:full-screen", "window:fullscreen": self = .fullScreen
        default: return nil
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftHalf: "창 왼쪽 50%"
        case .rightHalf: "창 오른쪽 50%"
        case .topHalf: "창 상단 50%"
        case .bottomHalf: "창 하단 50%"
        case .nextDisplay: "반대편 모니터로 이동"
        case .fill: "꽉 찬 화면"
        case .fullScreen: "전체 화면"
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.inset.filled"
        case .rightHalf: "rectangle.righthalf.inset.filled"
        case .topHalf: "rectangle.tophalf.inset.filled"
        case .bottomHalf: "rectangle.bottomhalf.inset.filled"
        case .nextDisplay: "rectangle.2.swap"
        case .fill: "macwindow.on.rectangle"
        case .fullScreen: "arrow.up.left.and.arrow.down.right"
        }
    }

    /// The key glyphs used by macOS for these built-in window shortcuts.
    /// Globe is the label shown on newer Mac keyboards; Fn is accepted by
    /// the shortcut parser as the same physical modifier.
    var shortcutDisplay: String {
        switch self {
        case .leftHalf: "⌃ Globe ←"
        case .rightHalf: "⌃ Globe →"
        case .topHalf: "⌃ Globe ↑"
        case .bottomHalf: "⌃ Globe ↓"
        case .nextDisplay: "⌃ Globe ⇧ →"
        case .fill: "⌃ Globe F"
        case .fullScreen: "전체 화면"
        }
    }

    var shortcutArrow: String {
        switch self {
        case .leftHalf: "←"
        case .rightHalf, .nextDisplay: "→"
        case .topHalf: "↑"
        case .bottomHalf: "↓"
        case .fill: "F"
        case .fullScreen: "⛶"
        }
    }

    var shortcutUsesShift: Bool {
        self == .nextDisplay
    }

    var placement: WindowPlacement {
        switch self {
        case .leftHalf: .leftHalf
        case .rightHalf: .rightHalf
        case .topHalf: .topHalf
        case .bottomHalf: .bottomHalf
        case .nextDisplay: .nextDisplay
        case .fill: .fill
        case .fullScreen: .fullScreen
        }
    }
}

enum WindowPlacement: Equatable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case nextDisplay
    case fill
    case fullScreen
}

enum MacActionError: LocalizedError {
    case appNotFound
    case invalidAddress
    case accessibilityRequired
    case shortcutNotConfigured
    case unsupportedShortcut
    case targetAppNotRunning
    case terminalCommandNotConfigured
    case terminalCommandFailed
    case clipboardTextNotConfigured
    case clipboardWriteFailed
    case windowActionFailed

    var errorDescription: String? {
        switch self {
        case .appNotFound: "설치된 앱을 찾지 못했습니다."
        case .invalidAddress: "웹페이지 주소가 올바르지 않습니다."
        case .accessibilityRequired: "단축키 실행에는 손쉬운 사용 권한이 필요합니다."
        case .shortcutNotConfigured: "등록된 단축키가 없습니다."
        case .unsupportedShortcut: "지원하지 않는 단축키 형식입니다."
        case .targetAppNotRunning: "대상 앱이 실행 중이 아닙니다. ‘앱이 꺼져 있으면 실행’ 옵션을 켜세요."
        case .terminalCommandNotConfigured: "등록된 터미널 명령어가 없습니다."
        case .terminalCommandFailed: "터미널 명령을 실행하지 못했습니다."
        case .clipboardTextNotConfigured: "등록된 클립보드 텍스트가 없습니다."
        case .clipboardWriteFailed: "클립보드 텍스트를 저장하지 못했습니다."
        case .windowActionFailed: "활성 창을 이동하지 못했습니다."
        }
    }
}

@MainActor
final class MacActionRunner {
    static let targetAppActivationOptions: NSApplication.ActivationOptions = [
        .activateAllWindows
    ]
    static let targetAppActivationRetryCount = 12
    static let targetAppActivationRetryInterval: TimeInterval = 0.15
    private static var fillRestoreFrames: [String: CGRect] = [:]

    func execute(_ action: PadAction, commandFileID: String? = nil) throws -> String {
        switch action.kind {
        case .app:
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: action.value) else { throw MacActionError.appNotFound }
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
            return "앱을 열었습니다."
        case .appFolder:
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: action.value) else { throw MacActionError.appNotFound }
            if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: action.value).first {
                Self.activateTargetApp(runningApp)
            } else {
                NSWorkspace.shared.openApplication(at: app, configuration: .init())
            }
            return "앱을 열고 단축키 폴더를 열었습니다."
        case .url:
            let address = action.value.hasPrefix("http") || action.value.hasPrefix("x-apple.")
                ? action.value
                : "https://\(action.value)"
            guard let url = URL(string: address) else { throw MacActionError.invalidAddress }
            NSWorkspace.shared.open(url)
            return "웹페이지를 열었습니다."
        case .shortcut:
            guard !action.value.isEmpty else { throw MacActionError.shortcutNotConfigured }

            if let windowAction = MacWindowAction(rawValue: action.value) {
                if action.targetAppBundleIdentifier.isEmpty {
                    try Self.moveActiveWindow(windowAction)
                    return "창 동작을 실행했습니다."
                }

                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: action.targetAppBundleIdentifier) else {
                    throw MacActionError.appNotFound
                }

                if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: action.targetAppBundleIdentifier).first {
                    Self.activateTargetApp(runningApp)
                    scheduleWindowAction(
                        windowAction,
                        after: 0.18,
                        targetAppBundleIdentifier: action.targetAppBundleIdentifier
                    )
                    return "대상 앱으로 전환한 뒤 창 동작을 실행합니다."
                }

                guard action.launchTargetAppIfNeeded else { throw MacActionError.targetAppNotRunning }
                NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
                scheduleWindowAction(
                    windowAction,
                    after: 0.65,
                    targetAppBundleIdentifier: action.targetAppBundleIdentifier,
                    activationRetriesRemaining: Self.targetAppActivationRetryCount
                )
                return "앱을 실행한 뒤 창 동작을 실행합니다."
            }

            let shortcut = Self.nativeShortcutValue(for: action.value)
            try Self.validateShortcut(shortcut)

            guard !action.targetAppBundleIdentifier.isEmpty else {
                try Self.sendShortcut(shortcut)
                return "단축키를 실행했습니다."
            }

            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: action.targetAppBundleIdentifier) else {
                throw MacActionError.appNotFound
            }

            if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: action.targetAppBundleIdentifier).first {
                Self.activateTargetApp(runningApp)
                scheduleShortcut(
                    shortcut,
                    after: 0.18,
                    targetAppBundleIdentifier: action.targetAppBundleIdentifier
                )
                return "대상 앱으로 전환한 뒤 단축키를 보냅니다."
            }

            guard action.launchTargetAppIfNeeded else { throw MacActionError.targetAppNotRunning }
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
            scheduleShortcut(
                shortcut,
                after: 0.65,
                targetAppBundleIdentifier: action.targetAppBundleIdentifier,
                activationRetriesRemaining: Self.targetAppActivationRetryCount
            )
            return "앱을 실행한 뒤 단축키를 보냅니다."
        case .terminalCommand:
            let command = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { throw MacActionError.terminalCommandNotConfigured }
            try Self.runTerminalCommand(TerminalCommandFileStore.shellCommand(for: commandFileID ?? "") ?? command)
            return "터미널 명령을 실행했습니다."
        case .clipboardText:
            guard !action.value.isEmpty else { throw MacActionError.clipboardTextNotConfigured }
            guard AXIsProcessTrusted() else { throw MacActionError.accessibilityRequired }
            _ = NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(action.value, forType: .string) else {
                throw MacActionError.clipboardWriteFailed
            }
            try Self.sendShortcut("cmd+v")
            return "클립보드 텍스트를 붙여넣었습니다."
        case .none:
            return "동작이 지정되지 않았습니다."
        }
    }

    func requestAccessibilityPermission() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private func scheduleShortcut(
        _ label: String,
        after delay: TimeInterval,
        targetAppBundleIdentifier: String? = nil,
        activationRetriesRemaining: Int = 0
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let targetAppBundleIdentifier,
               let targetApp = NSRunningApplication.runningApplications(
                   withBundleIdentifier: targetAppBundleIdentifier
               ).first {
                Self.activateTargetApp(targetApp)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    try? Self.sendShortcut(label)
                }
            } else if targetAppBundleIdentifier != nil, activationRetriesRemaining > 0 {
                self.scheduleShortcut(
                    label,
                    after: Self.targetAppActivationRetryInterval,
                    targetAppBundleIdentifier: targetAppBundleIdentifier,
                    activationRetriesRemaining: activationRetriesRemaining - 1
                )
            } else {
                try? Self.sendShortcut(label)
            }
        }
    }

    private func scheduleWindowAction(
        _ action: MacWindowAction,
        after delay: TimeInterval,
        targetAppBundleIdentifier: String,
        activationRetriesRemaining: Int = 0
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let targetApp = NSRunningApplication.runningApplications(
                withBundleIdentifier: targetAppBundleIdentifier
            ).first {
                Self.activateTargetApp(targetApp)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    try? Self.moveActiveWindow(action, targetApp: targetApp)
                }
            } else if activationRetriesRemaining > 0 {
                self.scheduleWindowAction(
                    action,
                    after: Self.targetAppActivationRetryInterval,
                    targetAppBundleIdentifier: targetAppBundleIdentifier,
                    activationRetriesRemaining: activationRetriesRemaining - 1
                )
            }
        }
    }

    private static func activateTargetApp(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            _ = app.activate(from: NSRunningApplication.current, options: targetAppActivationOptions)
        } else {
            _ = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }

    private static func runTerminalCommand(_ command: String) throws {
        let scriptSource = terminalAppleScript(for: command)
        guard let script = NSAppleScript(source: scriptSource) else {
            throw MacActionError.terminalCommandFailed
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if error != nil {
            throw MacActionError.terminalCommandFailed
        }
    }

    static func terminalAppleScript(for command: String) -> String {
        """
        tell application "Terminal"
            if (count of windows) = 0 then
                reopen
                repeat until (count of windows) > 0
                    delay 0.1
                end repeat
            end if
            do script "\(appleScriptEscaped(command))" in front window
            activate
        end tell
        """
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
    }

    private nonisolated static func validateShortcut(_ label: String) throws {
        guard AXIsProcessTrusted() else { throw MacActionError.accessibilityRequired }
        let tokens = label.lowercased().split(separator: "+").map(String.init)
        guard let key = tokens.last, let code = keyCode(for: key) else { throw MacActionError.unsupportedShortcut }
        _ = code
    }

    private nonisolated static func nativeShortcutValue(for value: String) -> String {
        MacWindowAction(rawValue: value)?.rawValue ?? value
    }

    nonisolated static func windowFrame(
        for action: MacWindowAction,
        currentFrame: CGRect,
        visibleDisplays: [CGRect]
    ) -> CGRect? {
        guard !visibleDisplays.isEmpty else { return nil }
        let currentCenter = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
        let currentDisplayIndex = visibleDisplays.firstIndex(where: { $0.contains(currentCenter) }) ?? 0
        let display = visibleDisplays[currentDisplayIndex]

        switch action.placement {
        case .leftHalf:
            return CGRect(x: display.minX, y: display.minY, width: floor(display.width / 2), height: display.height)
        case .rightHalf:
            let halfWidth = floor(display.width / 2)
            return CGRect(x: display.maxX - halfWidth, y: display.minY, width: halfWidth, height: display.height)
        case .topHalf:
            let halfHeight = floor(display.height / 2)
            return CGRect(x: display.minX, y: display.minY, width: display.width, height: halfHeight)
        case .bottomHalf:
            let halfHeight = floor(display.height / 2)
            return CGRect(x: display.minX, y: display.maxY - halfHeight, width: display.width, height: halfHeight)
        case .nextDisplay:
            guard visibleDisplays.count > 1 else { return currentFrame }
            let nextDisplay = visibleDisplays[(currentDisplayIndex + 1) % visibleDisplays.count]
            let width = min(currentFrame.width, nextDisplay.width)
            let height = min(currentFrame.height, nextDisplay.height)
            return CGRect(
                x: min(max(nextDisplay.minX, currentFrame.minX), nextDisplay.maxX - width),
                y: min(max(nextDisplay.minY, currentFrame.minY), nextDisplay.maxY - height),
                width: width,
                height: height
            )
        case .fill:
            return display
        case .fullScreen:
            return nil
        }
    }

    @MainActor private static func moveActiveWindow(
        _ action: MacWindowAction,
        targetApp: NSRunningApplication? = nil
    ) throws {
        guard AXIsProcessTrusted() else { throw MacActionError.accessibilityRequired }
        let application = targetApp ?? NSWorkspace.shared.frontmostApplication
        guard let application,
              let window = focusedWindow(for: application),
              let currentFrame = axFrame(of: window) else {
            throw MacActionError.windowActionFailed
        }

        let globalHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let visibleDisplays = NSScreen.screens.map { screen -> CGRect in
            let visible = screen.visibleFrame
            return CGRect(
                x: visible.minX,
                y: globalHeight - visible.maxY,
                width: visible.width,
                height: visible.height
            )
        }
        guard let frame = windowFrame(for: action, currentFrame: currentFrame, visibleDisplays: visibleDisplays) else {
            if action == .fullScreen {
                try toggleFullScreen(for: window, application: application)
                return
            }
            throw MacActionError.windowActionFailed
        }

        if application.processIdentifier == NSRunningApplication.current.processIdentifier,
           let ownWindow = NSApp.keyWindow ?? NSApp.mainWindow {
            if action == .fullScreen {
                ownWindow.toggleFullScreen(nil)
                return
            }
            let ownFrame = ownWindow.frame
            let currentQuartzFrame = CGRect(
                x: ownFrame.minX,
                y: globalHeight - ownFrame.maxY,
                width: ownFrame.width,
                height: ownFrame.height
            )
            guard let ownQuartzTarget = windowFrame(
                for: action,
                currentFrame: currentQuartzFrame,
                visibleDisplays: visibleDisplays
            ) else { throw MacActionError.windowActionFailed }
            let restoreKey = fillRestoreKey(for: application, windowNumber: ownWindow.windowNumber)
            if action == .fill, let restoreFrame = fillRestoreFrames[restoreKey] {
                ownWindow.setFrame(restoreFrame, display: true, animate: false)
                fillRestoreFrames.removeValue(forKey: restoreKey)
                return
            }
            if action == .fill {
                fillRestoreFrames[restoreKey] = ownFrame
            }
            let targetFrame = CGRect(
                x: ownQuartzTarget.minX,
                y: globalHeight - ownQuartzTarget.maxY,
                width: ownQuartzTarget.width,
                height: ownQuartzTarget.height
            )
            ownWindow.setFrame(targetFrame, display: true, animate: false)
            return
        }

        let restoreKey = fillRestoreKey(for: application, windowNumber: nil)
        if action == .fill, let restoreFrame = fillRestoreFrames[restoreKey] {
            try setAXFrame(restoreFrame, on: window)
            fillRestoreFrames.removeValue(forKey: restoreKey)
            return
        }
        if action == .fill {
            fillRestoreFrames[restoreKey] = currentFrame
        }
        try setAXFrame(frame, on: window)
    }

    @MainActor private static func toggleFullScreen(
        for window: AXUIElement,
        application: NSRunningApplication
    ) throws {
        if application.processIdentifier == NSRunningApplication.current.processIdentifier,
           let ownWindow = NSApp.keyWindow ?? NSApp.mainWindow {
            ownWindow.toggleFullScreen(nil)
            return
        }

        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXFullScreenButtonAttribute as CFString,
            &button
        ) == .success,
        let button else {
            throw MacActionError.windowActionFailed
        }
        let buttonElement = button as! AXUIElement
        guard AXUIElementPerformAction(buttonElement, kAXPressAction as CFString) == .success else {
            throw MacActionError.windowActionFailed
        }
    }

    private static func fillRestoreKey(
        for application: NSRunningApplication,
        windowNumber: Int?
    ) -> String {
        if let windowNumber {
            return "\(application.processIdentifier):\(windowNumber)"
        }
        return "\(application.processIdentifier)"
    }

    private nonisolated static func setAXFrame(_ frame: CGRect, on window: AXUIElement) throws {
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size),
              AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) == .success,
              AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success else {
            throw MacActionError.windowActionFailed
        }
    }

    private nonisolated static func focusedWindow(for application: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused) == .success,
           let focused {
            return (focused as! AXUIElement)
        }

        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows) == .success,
              let windows = windows as? [AXUIElement] else { return nil }
        return windows.first
    }

    private nonisolated static func axFrame(of window: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
              let position,
              let size else { return nil }

        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private nonisolated static func sendShortcut(_ label: String) throws {
        try validateShortcut(label)
        let tokens = label.lowercased().split(separator: "+").map(String.init)
        guard let key = tokens.last, let code = keyCode(for: key) else { throw MacActionError.unsupportedShortcut }
        var flags: CGEventFlags = []
        if tokens.contains(where: { $0 == "cmd" || $0 == "command" }) { flags.insert(.maskCommand) }
        if tokens.contains(where: { $0 == "ctrl" || $0 == "control" }) { flags.insert(.maskControl) }
        if tokens.contains("shift") { flags.insert(.maskShift) }
        if tokens.contains(where: { $0 == "alt" || $0 == "option" }) { flags.insert(.maskAlternate) }
        if tokens.contains(where: { $0 == "fn" || $0 == "function" || $0 == "globe" }) { flags.insert(.maskSecondaryFn) }
        guard let source = CGEventSource(stateID: .combinedSessionState), let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true), let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { throw MacActionError.unsupportedShortcut }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private nonisolated static func keyCode(for key: String) -> CGKeyCode? {
        let codes: [String: CGKeyCode] = [
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34,
            "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15,
            "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
            "space": 49, "return": 36, "tab": 48, "delete": 51, "escape": 53, ".": 47,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
            "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
            "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
            "volumeup": 72, "volumedown": 73, "mute": 74, "mediaplaypause": 100
        ]
        return codes[key]
    }
}
