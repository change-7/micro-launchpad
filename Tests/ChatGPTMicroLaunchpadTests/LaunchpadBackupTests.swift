import XCTest
@testable import ChatGPTMicroLaunchpad

final class LaunchpadBackupTests: XCTestCase {
    func testBackup_roundTripsButtonAndCodexSettings() throws {
        var macPages = PadDefaults.pages()
        macPages[0].pads[0].title = "복구 버튼"

        var smartphonePages = SmartphoneDefaults.pages()
        smartphonePages[0].buttons[0].title = "휴대폰 버튼"

        let preset = MotionPreset(
            name: "작업 중",
            loop: true,
            frameDurationMs: 120,
            frames: [MotionFrame(pixels: [MotionPixel(row: 1, column: 1, color: "green")])]
        )
        var displaySettings = CodexMotionDisplaySettings()
        displaySettings.preservesPadLEDsDuringMotion = true

        let backup = LaunchpadBackup(
            launchpadPages: macPages,
            smartphonePages: smartphonePages,
            motionPresets: [preset],
            codexMotionPresetIDs: [CodexActivity.running.rawValue: preset.id],
            codexMotionPresentations: [CodexActivity.running.rawValue: CodexMotionPresentation(presetID: preset.id)],
            codexMotionDisplaySettings: displaySettings
        )

        let decoded = try JSONDecoder().decode(
            LaunchpadBackup.self,
            from: JSONEncoder().encode(backup)
        )

        XCTAssertEqual(decoded.launchpadPages[0].pads[0].title, "복구 버튼")
        XCTAssertEqual(decoded.smartphonePages[0].buttons[0].title, "휴대폰 버튼")
        XCTAssertEqual(decoded.motionPresets, [preset])
        XCTAssertEqual(decoded.codexMotionPresetIDs[CodexActivity.running.rawValue], preset.id)
        XCTAssertTrue(decoded.codexMotionDisplaySettings.preservesPadLEDsDuringMotion)
    }

    func testBackup_validationRejectsIncompleteButtonPages() {
        var smartphonePages = SmartphoneDefaults.pages()
        smartphonePages[0].buttons.removeLast()
        let backup = LaunchpadBackup(
            launchpadPages: PadDefaults.pages(),
            smartphonePages: smartphonePages,
            motionPresets: [],
            codexMotionPresetIDs: [:],
            codexMotionPresentations: [:],
            codexMotionDisplaySettings: CodexMotionDisplaySettings()
        )

        XCTAssertThrowsError(try backup.validated()) { error in
            XCTAssertEqual(error as? LaunchpadBackupError, .invalidSmartphonePageShape)
        }
    }
}
