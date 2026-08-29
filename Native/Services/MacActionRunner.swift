import AppKit

enum MacActionError: LocalizedError {
    case appNotFound
    case invalidAddress
    case accessibilityRequired
    case shortcutNotConfigured
    case unsupportedShortcut
    case targetAppNotRunning

    var errorDescription: String? {
        switch self {
        case .appNotFound: "설치된 앱을 찾지 못했습니다."
        case .invalidAddress: "웹페이지 주소가 올바르지 않습니다."
        case .accessibilityRequired: "단축키 실행에는 손쉬운 사용 권한이 필요합니다."
        case .shortcutNotConfigured: "등록된 단축키가 없습니다."
        case .unsupportedShortcut: "지원하지 않는 단축키 형식입니다."
        case .targetAppNotRunning: "대상 앱이 실행 중이 아닙니다. ‘앱이 꺼져 있으면 실행’ 옵션을 켜세요."
        }
    }
}

@MainActor
final class MacActionRunner {
    func execute(_ action: PadAction) throws -> String {
        switch action.kind {
        case .app:
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: action.value) else { throw MacActionError.appNotFound }
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
            return "앱을 열었습니다."
        case .url:
            let address = action.value.hasPrefix("http") || action.value.hasPrefix("x-apple.")
                ? action.value
                : "https://\(action.value)"
            guard let url = URL(string: address) else { throw MacActionError.invalidAddress }
            NSWorkspace.shared.open(url)
            return "웹페이지를 열었습니다."
        case .shortcut:
            guard !action.value.isEmpty else { throw MacActionError.shortcutNotConfigured }
            try Self.validateShortcut(action.value)

            guard !action.targetAppBundleIdentifier.isEmpty else {
                try Self.sendShortcut(action.value)
                return "단축키를 실행했습니다."
            }

            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: action.targetAppBundleIdentifier) else {
                throw MacActionError.appNotFound
            }

            if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: action.targetAppBundleIdentifier).first {
                runningApp.activate(options: [.activateAllWindows])
                scheduleShortcut(action.value, after: 0.18)
                return "대상 앱으로 전환한 뒤 단축키를 보냅니다."
            }

            guard action.launchTargetAppIfNeeded else { throw MacActionError.targetAppNotRunning }
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
            scheduleShortcut(action.value, after: 0.65)
            return "앱을 실행한 뒤 단축키를 보냅니다."
        case .none:
            return "동작이 지정되지 않았습니다."
        }
    }

    func requestAccessibilityPermission() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private func scheduleShortcut(_ label: String, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            try? Self.sendShortcut(label)
        }
    }

    private nonisolated static func validateShortcut(_ label: String) throws {
        guard AXIsProcessTrusted() else { throw MacActionError.accessibilityRequired }
        let tokens = label.lowercased().split(separator: "+").map(String.init)
        guard let key = tokens.last, let code = keyCode(for: key) else { throw MacActionError.unsupportedShortcut }
        _ = code
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
