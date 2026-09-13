import Foundation

enum LaunchpadBackupError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidLaunchpadPageShape
    case invalidSmartphonePageShape

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "지원하지 않는 백업 버전입니다: \(version)"
        case .invalidLaunchpadPageShape:
            "런치패드 페이지 구성이 올바르지 않습니다."
        case .invalidSmartphonePageShape:
            "스마트폰 버튼 페이지 구성이 올바르지 않습니다."
        }
    }
}

struct LaunchpadBackup: Codable, Hashable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let createdAt: Date
    let launchpadPages: [LaunchPage]
    let smartphonePages: [SmartphonePage]
    let motionPresets: [MotionPreset]
    let codexMotionPresetIDs: [String: UUID]
    let codexMotionPresentations: [String: CodexMotionPresentation]
    let codexMotionDisplaySettings: CodexMotionDisplaySettings

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        createdAt: Date = Date(),
        launchpadPages: [LaunchPage],
        smartphonePages: [SmartphonePage],
        motionPresets: [MotionPreset],
        codexMotionPresetIDs: [String: UUID],
        codexMotionPresentations: [String: CodexMotionPresentation],
        codexMotionDisplaySettings: CodexMotionDisplaySettings
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.launchpadPages = launchpadPages
        self.smartphonePages = smartphonePages
        self.motionPresets = motionPresets
        self.codexMotionPresetIDs = codexMotionPresetIDs
        self.codexMotionPresentations = codexMotionPresentations
        self.codexMotionDisplaySettings = codexMotionDisplaySettings
    }

    func validated() throws -> LaunchpadBackup {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LaunchpadBackupError.unsupportedVersion(schemaVersion)
        }
        guard launchpadPages.count == PadDefaults.pageNames.count,
              launchpadPages.allSatisfy({ $0.pads.count == 72 }),
              Set(launchpadPages.map(\.id)).count == launchpadPages.count else {
            throw LaunchpadBackupError.invalidLaunchpadPageShape
        }
        guard smartphonePages.count == SmartphoneDefaults.pageCount,
              smartphonePages.allSatisfy({ $0.buttons.count == SmartphoneDefaults.buttonCount }),
              Set(smartphonePages.map(\.id)).count == smartphonePages.count else {
            throw LaunchpadBackupError.invalidSmartphonePageShape
        }
        return self
    }
}
