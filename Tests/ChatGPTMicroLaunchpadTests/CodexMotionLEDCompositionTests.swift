import XCTest
@testable import ChatGPTMicroLaunchpad

final class CodexMotionLEDCompositionTests: XCTestCase {
    func testWeeklyUsageGrid_whenWeeklyLimitIsUsed_calculatesRemainingCells() {
        XCTAssertEqual(CodexWeeklyUsageGrid.remainingCellCount(usedPercent: 0), 64)
        XCTAssertEqual(CodexWeeklyUsageGrid.remainingCellCount(usedPercent: 77), 15)
        XCTAssertEqual(CodexWeeklyUsageGrid.remainingCellCount(usedPercent: 100), 0)
    }

    func testWeeklyUsageGrid_whenRemainingCellsAreShown_fillsFromBottomToTop() {
        XCTAssertFalse(CodexWeeklyUsageGrid.isRemainingCellActive(index: 48, remainingCellCount: 15))
        XCTAssertTrue(CodexWeeklyUsageGrid.isRemainingCellActive(index: 49, remainingCellCount: 15))
        XCTAssertTrue(CodexWeeklyUsageGrid.isRemainingCellActive(index: 63, remainingCellCount: 15))
    }

    func testDisplaySettings_whenWeeklyUsageIsLimitedToOnePage_roundTripsThePage() throws {
        let pageID = UUID()
        let settings = CodexMotionDisplaySettings(
            weeklyUsageDisplay: CodexWeeklyUsageDisplaySettings(
                isEnabled: true,
                scope: .specificPage,
                pageID: pageID
            )
        )

        let restored = try JSONDecoder().decode(
            CodexMotionDisplaySettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertTrue(restored.weeklyUsageDisplay.isEnabled)
        XCTAssertTrue(restored.weeklyUsageDisplay.allowsPresentation(on: pageID))
        XCTAssertFalse(restored.weeklyUsageDisplay.allowsPresentation(on: UUID()))
    }

    @MainActor
    func testLEDState_whenLaunchpadOutputChanges_keepsTheExactVisibleButtonValues() {
        // Given
        let midi = LaunchpadMIDIManager(startsMIDIClient: false, messageSink: { _ in })
        let pages = eightPages(first: page(gridColors: ["green"]))

        // When
        midi.updateLEDs(for: pages, activePage: 0)

        // Then
        XCTAssertEqual(midi.ledState.grid[0], 44)
        XCTAssertEqual(midi.ledState.side[0], 12)
        XCTAssertEqual(midi.ledState.top[0], 60)
    }

    func testDisplaySettings_whenLEDBubbleIsEnabled_roundTripsItsVisibilityAndPosition() throws {
        // Given
        let settings = CodexMotionDisplaySettings(
            showsLaunchpadLEDBubble: true,
            launchpadLEDBubbleOriginX: 320,
            launchpadLEDBubbleOriginY: 540
        )

        // When
        let restored = try JSONDecoder().decode(
            CodexMotionDisplaySettings.self,
            from: JSONEncoder().encode(settings)
        )

        // Then
        XCTAssertTrue(restored.showsLaunchpadLEDBubble)
        XCTAssertEqual(restored.launchpadLEDBubbleOriginX, 320)
        XCTAssertEqual(restored.launchpadLEDBubbleOriginY, 540)
    }

    func testDisplaySettings_whenLEDBubbleSizeIsChosen_roundTripsTheSize() throws {
        // Given
        let settings = CodexMotionDisplaySettings(launchpadLEDBubbleSize: .large)

        // When
        let restored = try JSONDecoder().decode(
            CodexMotionDisplaySettings.self,
            from: JSONEncoder().encode(settings)
        )

        // Then
        XCTAssertEqual(restored.launchpadLEDBubbleSize, .large)
    }

    func testDisplaySettings_whenIdleScreensaverIsConfigured_roundTripsItsSettings() throws {
        let presetID = UUID()
        let settings = CodexMotionDisplaySettings(
            idleScreensaver: LaunchpadIdleScreensaverSettings(
                isEnabled: true,
                inputScope: .macAndCodex,
                delaySeconds: 45,
                durationSeconds: 20,
                presetID: presetID
            )
        )

        let restored = try JSONDecoder().decode(
            CodexMotionDisplaySettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertTrue(restored.idleScreensaver.isEnabled)
        XCTAssertEqual(restored.idleScreensaver.inputScope, .macAndCodex)
        XCTAssertEqual(restored.idleScreensaver.delaySeconds, 45)
        XCTAssertEqual(restored.idleScreensaver.durationSeconds, 20)
        XCTAssertEqual(restored.idleScreensaver.presetID, presetID)
    }

    func testDisplaySettings_whenDecodingLegacyJSON_disablesIdleScreensaverByDefault() throws {
        let data = Data("""
        {
          "scope": "allPages"
        }
        """.utf8)

        let settings = try JSONDecoder().decode(CodexMotionDisplaySettings.self, from: data)

        XCTAssertFalse(settings.idleScreensaver.isEnabled)
        XCTAssertEqual(settings.idleScreensaver.delaySeconds, 300)
        XCTAssertEqual(settings.idleScreensaver.durationSeconds, 60)
    }

    func testDisplaySettings_whenDecodingExistingScreensaverSettings_defaultsDurationToOneMinute() throws {
        let data = Data("""
        {
          "scope": "allPages",
          "idleScreensaver": {
            "isEnabled": true,
            "inputScope": "launchpadAndCodex",
            "delaySeconds": 120
          }
        }
        """.utf8)

        let settings = try JSONDecoder().decode(CodexMotionDisplaySettings.self, from: data)

        XCTAssertTrue(settings.idleScreensaver.isEnabled)
        XCTAssertEqual(settings.idleScreensaver.delaySeconds, 120)
        XCTAssertEqual(settings.idleScreensaver.durationSeconds, 60)
    }

    func testIdleScreensaverPolicy_whenUsingLaunchpadScope_ignoresRecentMacInput() {
        let settings = LaunchpadIdleScreensaverSettings(
            isEnabled: true,
            inputScope: .launchpadAndCodex,
            delaySeconds: 30,
            presetID: UUID()
        )

        let shouldPlay = LaunchpadIdleScreensaverPolicy.shouldPlay(
            settings: settings,
            hasPreset: true,
            codexIsBusy: false,
            launchpadAndCodexIdleSeconds: 31,
            macIdleSeconds: 1
        )

        XCTAssertTrue(shouldPlay)
    }

    func testIdleScreensaverPolicy_whenUsingMacScope_stopsForRecentMacInputAndCodexWork() {
        let settings = LaunchpadIdleScreensaverSettings(
            isEnabled: true,
            inputScope: .macAndCodex,
            delaySeconds: 30,
            presetID: UUID()
        )

        XCTAssertFalse(LaunchpadIdleScreensaverPolicy.shouldPlay(
            settings: settings,
            hasPreset: true,
            codexIsBusy: false,
            launchpadAndCodexIdleSeconds: 60,
            macIdleSeconds: 2
        ))
        XCTAssertFalse(LaunchpadIdleScreensaverPolicy.shouldPlay(
            settings: settings,
            hasPreset: true,
            codexIsBusy: true,
            launchpadAndCodexIdleSeconds: 60,
            macIdleSeconds: 60
        ))
    }

    func testDisplaySettings_whenDecodingLegacyJSON_defaultsGlobalPadLEDPreservationToFalse() throws {
        // Given
        let data = Data("""
        {
          "scope": "allPages"
        }
        """.utf8)

        // When
        let settings = try JSONDecoder().decode(CodexMotionDisplaySettings.self, from: data)

        // Then
        XCTAssertFalse(settings.preservesPadLEDsDuringMotion)
    }

    func testDisplaySettings_whenLegacyPresentationPreservesPadLEDs_migratesTheGlobalPreference() {
        // Given
        let legacySettingsData = Data("""
        {
          "scope": "allPages"
        }
        """.utf8)
        let legacyPresentations = [
            CodexActivity.connecting.rawValue: CodexMotionPresentation(preservesPadLEDsDuringMotion: false),
            CodexActivity.completed.rawValue: CodexMotionPresentation(preservesPadLEDsDuringMotion: true)
        ]

        // When
        let restored = CodexMotionDisplaySettings.restored(
            from: legacySettingsData,
            legacyPresentations: legacyPresentations
        )

        // Then
        XCTAssertTrue(restored.settings.preservesPadLEDsDuringMotion)
        XCTAssertTrue(restored.didMigrateLegacyPreservation)
    }

    func testDisplaySettings_whenGlobalPreservationIsEnabled_usesItForEveryStatus() {
        // Given
        let settings = CodexMotionDisplaySettings(preservesPadLEDsDuringMotion: true)

        // When
        let preservationByActivity = Dictionary(
            uniqueKeysWithValues: CodexActivity.allCases.map { activity in
                (activity, settings.shouldPreservePadLEDsDuringMotion(for: activity))
            }
        )

        // Then
        XCTAssertEqual(Set(preservationByActivity.values), [true])
    }

    func testRuleLayout_whenRunning_keepsTheHoldToggleOnTheMainRuleRowOnly() {
        // Given
        let activities = CodexActivity.allCases

        // When
        let placementByActivity = Dictionary(
            uniqueKeysWithValues: activities.map { activity in
                (activity, CodexMotionRuleLayout.holdTogglePlacement(for: activity))
            }
        )

        // Then
        XCTAssertEqual(placementByActivity[.running], .mainRuleRow)
        XCTAssertTrue(activities.filter { $0 != .running }.allSatisfy {
            placementByActivity[$0] == .hidden
        })
    }

    func testPresentation_whenDecodingLegacyJSON_defaultsToReplacingOrdinaryPadLEDs() throws {
        // Given
        let data = Data("""
        {
          "presetID": null,
          "dismissal": "afterDuration",
          "durationSeconds": 5,
          "dismissPadID": "grid_0_0"
        }
        """.utf8)

        // When
        let presentation = try JSONDecoder().decode(CodexMotionPresentation.self, from: data)

        // Then
        XCTAssertFalse(presentation.preservesPadLEDsDuringMotion)
    }

    func testPresentation_whenPreservationIsEnabled_roundTripsThePersistedOption() throws {
        // Given
        let presentation = CodexMotionPresentation(preservesPadLEDsDuringMotion: true)

        // When
        let decoded = try JSONDecoder().decode(
            CodexMotionPresentation.self,
            from: JSONEncoder().encode(presentation)
        )

        // Then
        XCTAssertTrue(decoded.preservesPadLEDsDuringMotion)
    }

    @MainActor
    func testMotionFrame_whenPreservationIsEnabled_keepsAbsentPadAndOverridesPresentPad() {
        // Given
        var sent: [[LaunchpadMIDIMessage]] = []
        let midi = LaunchpadMIDIManager(startsMIDIClient: false, messageSink: { sent.append($0) })
        let page = page(gridColors: ["green", "darkRed"])
        midi.updateLEDs(for: eightPages(first: page), activePage: 0)
        sent.removeAll()
        let motion = MotionPreset(
            name: "Overlay",
            loop: true,
            frameDurationMs: 60_000,
            frames: [MotionFrame(pixels: [MotionPixel(row: 1, column: 2, color: "yellow")])]
        )

        // When
        _ = midi.playMotion(motion, preservingPadLEDs: true)

        // Then
        XCTAssertEqual(value(forNote: 0, in: sent.last), 44)
        XCTAssertEqual(value(forNote: 1, in: sent.last), 62)
        midi.stopMotion(restorePage: false)
    }

    @MainActor
    func testMotionFrame_whenPreservationIsDisabled_replacesAbsentPadWithOff() {
        // Given
        var sent: [[LaunchpadMIDIMessage]] = []
        let midi = LaunchpadMIDIManager(startsMIDIClient: false, messageSink: { sent.append($0) })
        midi.updateLEDs(for: eightPages(first: page(gridColors: ["green"])), activePage: 0)
        sent.removeAll()
        let motion = MotionPreset(
            name: "Replace",
            loop: true,
            frameDurationMs: 60_000,
            frames: [MotionFrame(pixels: [MotionPixel(row: 1, column: 2, color: "yellow")])]
        )

        // When
        _ = midi.playMotion(motion, preservingPadLEDs: false)

        // Then
        XCTAssertEqual(value(forNote: 0, in: sent.last), 12)
        XCTAssertEqual(value(forNote: 1, in: sent.last), 62)
        midi.stopMotion(restorePage: false)
    }

    @MainActor
    func testMotionFrame_whenPreservationIsEnabled_treatsExplicitOffAsAuthoritative() {
        // Given
        var sent: [[LaunchpadMIDIMessage]] = []
        let midi = LaunchpadMIDIManager(startsMIDIClient: false, messageSink: { sent.append($0) })
        midi.updateLEDs(for: eightPages(first: page(gridColors: ["green"])), activePage: 0)
        sent.removeAll()
        let motion = MotionPreset(
            name: "Black pixel",
            loop: true,
            frameDurationMs: 60_000,
            frames: [MotionFrame(pixels: [MotionPixel(row: 1, column: 1, color: "off")])]
        )

        // When
        _ = midi.playMotion(motion, preservingPadLEDs: true)

        // Then
        XCTAssertEqual(value(forNote: 0, in: sent.last), 12)
        midi.stopMotion(restorePage: false)
    }

    @MainActor
    func testMotionStop_whenPageChanges_restoresNewPageWithoutMutatingSavedPads() {
        // Given
        var sent: [[LaunchpadMIDIMessage]] = []
        let midi = LaunchpadMIDIManager(startsMIDIClient: false, messageSink: { sent.append($0) })
        let first = page(gridColors: ["green"])
        let second = page(gridColors: ["red"])
        var pages = eightPages(first: first)
        pages[1] = second
        midi.updateLEDs(for: pages, activePage: 0)
        let motion = MotionPreset(
            name: "Overlay",
            loop: true,
            frameDurationMs: 60_000,
            frames: [MotionFrame(pixels: [MotionPixel(row: 1, column: 2, color: "yellow")])]
        )
        _ = midi.playMotion(motion, preservingPadLEDs: true)
        let savedPages = pages
        sent.removeAll()

        // When
        midi.updateLEDs(for: pages, activePage: 1)
        midi.stopMotion()

        // Then
        XCTAssertEqual(value(forNote: 0, in: sent.last), 14)
        XCTAssertEqual(pages, savedPages)
    }

    @MainActor
    func testSideLEDs_whenPageChanges_keepTheirExistingValues() {
        // Given
        var sent: [[LaunchpadMIDIMessage]] = []
        let midi = LaunchpadMIDIManager(startsMIDIClient: false, messageSink: { sent.append($0) })
        var pages = eightPages(first: page(gridColors: [], sideColors: ["green"]))
        pages[1] = page(gridColors: [], sideColors: ["red"])
        midi.updateLEDs(for: pages, activePage: 0)
        sent.removeAll()

        // When
        midi.updateLEDs(for: pages, activePage: 1)

        // Then
        XCTAssertEqual(value(forNote: 8, in: sent.last), 44)
        XCTAssertEqual(midi.ledState.side[0], 44)
    }

    @MainActor
    func testVirtualMotionFrame_whenPreservationIsEnabled_matchesHardwareComposition() {
        // Given
        let player = VirtualMotionPlayer()
        let underlyingPage = page(gridColors: ["green", "darkRed"])
        let motion = MotionPreset(
            name: "Virtual overlay",
            loop: true,
            frameDurationMs: 60_000,
            frames: [MotionFrame(pixels: [MotionPixel(row: 1, column: 2, color: "yellow")])]
        )

        // When
        player.play(motion, over: underlyingPage, preservingPadLEDs: true)

        // Then
        XCTAssertEqual(player.frame?.pixels.first(where: { $0.row == 1 && $0.column == 1 })?.color, "green")
        XCTAssertEqual(player.frame?.pixels.first(where: { $0.row == 1 && $0.column == 2 })?.color, "yellow")
        player.stop()
    }

    private func page(gridColors: [String], sideColors: [String] = []) -> LaunchPage {
        let pads = (0..<64).map { index in
            Pad(id: "grid_\(index / 8)_\(index % 8)", idleColor: gridColors.indices.contains(index) ? gridColors[index] : "off")
        } + (0..<8).map { index in
            Pad(id: "side_\(index)", idleColor: sideColors.indices.contains(index) ? sideColors[index] : "off")
        }
        return LaunchPage(name: "Test", pads: pads)
    }

    private func eightPages(first: LaunchPage) -> [LaunchPage] {
        [first] + (1..<8).map { _ in page(gridColors: []) }
    }

    private func value(forNote note: UInt8, in messages: [LaunchpadMIDIMessage]?) -> UInt8? {
        messages?.last(where: { $0.status == 0x90 && $0.number == note })?.value
    }
}
