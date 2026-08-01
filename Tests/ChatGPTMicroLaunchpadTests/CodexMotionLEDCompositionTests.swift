import XCTest
@testable import ChatGPTMicroLaunchpad

final class CodexMotionLEDCompositionTests: XCTestCase {
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

    private func page(gridColors: [String]) -> LaunchPage {
        let pads = (0..<64).map { index in
            Pad(id: "grid_\(index / 8)_\(index % 8)", idleColor: gridColors.indices.contains(index) ? gridColors[index] : "off")
        } + (0..<8).map { Pad(id: "side_\($0)") }
        return LaunchPage(name: "Test", pads: pads)
    }

    private func eightPages(first: LaunchPage) -> [LaunchPage] {
        [first] + (1..<8).map { _ in page(gridColors: []) }
    }

    private func value(forNote note: UInt8, in messages: [LaunchpadMIDIMessage]?) -> UInt8? {
        messages?.last(where: { $0.status == 0x90 && $0.number == note })?.value
    }
}
