import AppKit
import Observation

@MainActor
@Observable
final class ShortcutRecorder {
    private(set) var isRecording = false
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var onPreview: ((String) -> Void)?
    private var onCapture: ((String) -> Void)?
    private var selectedModifiers = Set<RecordedModifier>()

    func begin(onPreview: @escaping (String) -> Void, onCapture: @escaping (String) -> Void) {
        stop()
        isRecording = true
        selectedModifiers.removeAll()
        self.onPreview = onPreview
        self.onCapture = onCapture
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            DispatchQueue.main.async {
                guard let self, self.isRecording else { return }
                _ = self.handle(event)
            }
        }
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        onPreview = nil
        onCapture = nil
        selectedModifiers.removeAll()
        isRecording = false
    }

    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .flagsChanged {
            recordModifier(from: event)
            return false
        }
        if event.keyCode == 53 { // Escape cancels recording.
            stop()
            return true
        }
        guard let key = ShortcutNotation.keyName(for: event) else { return false }
        let shortcut = (RecordedModifier.allCases.filter { selectedModifiers.contains($0) }.map(\.token) + [key]).joined(separator: "+")
        onCapture?(shortcut)
        stop()
        return true
    }

    private func recordModifier(from event: NSEvent) {
        guard let modifier = RecordedModifier(keyCode: event.keyCode) else { return }
        let isPressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(modifier.flag)
        guard isPressed else { return }
        selectedModifiers.insert(modifier)
        onPreview?(RecordedModifier.allCases.filter { selectedModifiers.contains($0) }.map(\.token).joined(separator: "+"))
    }
}

private enum RecordedModifier: CaseIterable, Hashable {
    case command, control, shift, option

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .command: .command
        case .control: .control
        case .shift: .shift
        case .option: .option
        }
    }

    var token: String {
        switch self {
        case .command: "Cmd"
        case .control: "Ctrl"
        case .shift: "Shift"
        case .option: "Option"
        }
    }

    init?(keyCode: UInt16) {
        switch keyCode {
        case 54, 55: self = .command
        case 59, 62: self = .control
        case 56, 60: self = .shift
        case 58, 61: self = .option
        default: return nil
        }
    }
}

enum ShortcutNotation {
    static func modifierLabel(for event: NSEvent) -> String {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("Cmd") }
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        return parts.joined(separator: "+")
    }

    static func label(for event: NSEvent) -> String? {
        let parts = modifierLabel(for: event).split(separator: "+").map(String.init)
        guard !parts.isEmpty, let key = keyName(for: event) else { return nil }
        return (parts + [key]).joined(separator: "+")
    }

    static func keyName(for event: NSEvent) -> String? {
        let keyCodes: [UInt16: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
            38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R",
            1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
            123: "Left", 124: "Right", 125: "Down", 126: "Up",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        return keyCodes[event.keyCode]
    }
}
