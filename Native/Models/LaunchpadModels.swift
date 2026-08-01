import Foundation

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case app
    case shortcut
    case url
    case none

    var id: String { rawValue }
    var title: String {
        switch self {
        case .app: "앱 실행"
        case .shortcut: "단축키 설정"
        case .url: "웹페이지 이동"
        case .none: "없음"
        }
    }
}

struct PadAction: Codable, Hashable {
    var kind: ActionKind = .none
    var value = ""
    /// Optional app that receives this shortcut. Empty keeps the existing global behavior.
    var targetAppBundleIdentifier = ""
    /// When a shortcut has a target app, launch it before dispatching when it is not running.
    var launchTargetAppIfNeeded = true

    init(
        kind: ActionKind = .none,
        value: String = "",
        targetAppBundleIdentifier: String = "",
        launchTargetAppIfNeeded: Bool = true
    ) {
        self.kind = kind
        self.value = value
        self.targetAppBundleIdentifier = targetAppBundleIdentifier
        self.launchTargetAppIfNeeded = launchTargetAppIfNeeded
    }

    private enum CodingKeys: String, CodingKey {
        case kind, value, targetAppBundleIdentifier, launchTargetAppIfNeeded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(ActionKind.self, forKey: .kind) ?? .none
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        targetAppBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .targetAppBundleIdentifier) ?? ""
        launchTargetAppIfNeeded = try container.decodeIfPresent(Bool.self, forKey: .launchTargetAppIfNeeded) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(value, forKey: .value)
        try container.encode(targetAppBundleIdentifier, forKey: .targetAppBundleIdentifier)
        try container.encode(launchTargetAppIfNeeded, forKey: .launchTargetAppIfNeeded)
    }
}

struct Pad: Identifiable, Codable, Hashable {
    let id: String
    var title = ""
    var symbol = ""
    var idleColor = "off"
    var activeColor = "green"
    var action = PadAction()
}

struct LaunchPage: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var pads: [Pad]
    var pageIdleColor: String
    var pageActiveColor: String

    init(id: UUID = UUID(), name: String, pads: [Pad], pageIdleColor: String = "green", pageActiveColor: String = "brightGreen") {
        self.id = id
        self.name = name
        self.pads = pads
        self.pageIdleColor = pageIdleColor
        self.pageActiveColor = pageActiveColor
    }

    /// The top P button uses its selected-page color only while this page is active.
    func topButtonColor(isSelected: Bool) -> String {
        isSelected ? pageActiveColor : pageIdleColor
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, pads, pageColor, pageIdleColor, pageActiveColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        pads = try container.decode([Pad].self, forKey: .pads)
        let legacyColor = try container.decodeIfPresent(String.self, forKey: .pageColor)
        pageIdleColor = try container.decodeIfPresent(String.self, forKey: .pageIdleColor) ?? legacyColor ?? "green"
        pageActiveColor = try container.decodeIfPresent(String.self, forKey: .pageActiveColor) ?? "brightGreen"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(pads, forKey: .pads)
        try container.encode(pageIdleColor, forKey: .pageIdleColor)
        try container.encode(pageActiveColor, forKey: .pageActiveColor)
    }
}

enum PadColor: String, CaseIterable, Identifiable {
    // Launchpad Mini MK1: red + green LEDs only. No blue, purple, white, pink, or lime.
    case off, darkRed, red, brightRed, darkGreen, green, brightGreen, darkAmber, amber, yellow, orange

    var id: String { rawValue }

    static let launchpadPalette: [PadColor] = [.off, .darkRed, .red, .brightRed, .darkGreen, .green, .brightGreen, .darkAmber, .amber, .yellow, .orange]
}

/// An importable 8×8 animation preset. Coordinates in the JSON format are one-based
/// so they can be written naturally in a ChatGPT response and checked by the importer.
struct MotionPreset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var loop: Bool
    var frameDurationMs: Int
    var frames: [MotionFrame]

    init(id: UUID = UUID(), name: String, loop: Bool, frameDurationMs: Int, frames: [MotionFrame]) {
        self.id = id
        self.name = name
        self.loop = loop
        self.frameDurationMs = frameDurationMs
        self.frames = frames
    }
}

struct MotionFrame: Codable, Hashable {
    var pixels: [MotionPixel]
}

struct MotionPixel: Codable, Hashable {
    var row: Int
    var column: Int
    var color: String
}
