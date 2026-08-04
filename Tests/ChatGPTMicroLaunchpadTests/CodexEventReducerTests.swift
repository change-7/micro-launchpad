import XCTest
@testable import ChatGPTMicroLaunchpad

final class CodexEventReducerTests: XCTestCase {
    func testActivity_whenExistingReducerReceivesMixedCaseTurnStart_remainsRunning() {
        XCTAssertEqual(CodexEventReducer.activity(for: "TURN/STARTED"), .running)
    }

    func testActivity_whenTurnCompletes() {
        XCTAssertEqual(CodexEventReducer.activity(for: "turn/completed"), .completed)
    }

    func testActivity_whenApprovalIsRequested() {
        XCTAssertEqual(CodexEventReducer.activity(for: "item/commandExecution/requestApproval"), .waitingForApproval)
    }

    func testActivity_whenUnrelatedNotificationArrives() {
        XCTAssertNil(CodexEventReducer.activity(for: "thread/updated"))
    }

    func testPadAction_whenDecodingLegacyShortcut_usesTargetAppDefaults() throws {
        let data = Data("""
        { "kind": "shortcut", "value": "Cmd+Ctrl+Shift+4" }
        """.utf8)

        let action = try JSONDecoder().decode(PadAction.self, from: data)

        XCTAssertEqual(action.targetAppBundleIdentifier, "")
        XCTAssertTrue(action.launchTargetAppIfNeeded)
    }

    func testSideButtonDefaults_assignOnlyClearMacFunctions() {
        XCTAssertEqual(PadDefaults.sideButtonDescriptor(for: "side_0")?.defaultAction?.value, "VolumeUp")
        XCTAssertEqual(PadDefaults.sideButtonDescriptor(for: "side_1")?.defaultAction?.value, "VolumeDown")
        XCTAssertEqual(PadDefaults.sideButtonDescriptor(for: "side_2")?.defaultAction?.value, "Mute")
        XCTAssertEqual(PadDefaults.sideButtonDescriptor(for: "side_3")?.defaultAction?.value, "MediaPlayPause")
        XCTAssertEqual(PadDefaults.sideButtonDescriptor(for: "side_4")?.defaultAction?.value, "MediaPlayPause")
        XCTAssertEqual(PadDefaults.sideButtonDescriptor(for: "side_5")?.defaultAction?.value, "Cmd+.")
        XCTAssertEqual(PadDefaults.sideButtonDescriptor(for: "side_7")?.defaultAction?.value, "Cmd+Shift+5")

        XCTAssertNil(PadDefaults.sideButtonDescriptor(for: "side_6")?.defaultAction)
    }

    func testCommonSideButtons_whenPagesHaveDifferentValues_useTheFirstPageAsTheSharedSource() {
        var pages = PadDefaults.pages()
        let firstIndex = pages[0].pads.firstIndex(where: { $0.id == "side_0" })!
        let secondIndex = pages[1].pads.firstIndex(where: { $0.id == "side_0" })!
        pages[0].pads[firstIndex].title = "공통 버튼"
        pages[0].pads[firstIndex].idleColor = "green"
        pages[1].pads[secondIndex].title = "페이지 전용 버튼"
        pages[1].pads[secondIndex].idleColor = "red"

        let synchronized = PadDefaults.applyingCommonSideButtons(to: pages)

        XCTAssertEqual(synchronized[1].pads[secondIndex], synchronized[0].pads[firstIndex])
    }

    func testCommonSideButtonUpdate_updatesEveryPage() {
        let pages = PadDefaults.pages()
        var edited = pages[3].pads.first(where: { $0.id == "side_2" })!
        edited.title = "공통 음소거"
        edited.idleColor = "orange"

        let updated = PadDefaults.updatingCommonSideButton(edited, in: pages)

        XCTAssertTrue(updated.allSatisfy { page in
            page.pads.first(where: { $0.id == "side_2" }) == edited
        })
    }

    func testTopButtonColor_whenPageIsSelected_usesSelectedPageColor() {
        let page = LaunchPage(
            name: "P1",
            pads: [],
            pageIdleColor: "darkGreen",
            pageActiveColor: "orange"
        )

        XCTAssertEqual(page.topButtonColor(isSelected: false), "darkGreen")
        XCTAssertEqual(page.topButtonColor(isSelected: true), "orange")
    }

    func testCodexMotionDisplaySettings_whenSpecificPageIsSelected_limitsMotionToThatPage() {
        let allowedPageID = UUID()
        let settings = CodexMotionDisplaySettings(scope: .specificPage, pageID: allowedPageID)

        XCTAssertTrue(settings.allowsPresentation(on: allowedPageID))
        XCTAssertFalse(settings.allowsPresentation(on: UUID()))
    }

    func testCodexMotionPresentation_whenTimedDismissal_usesConfiguredPreviewDuration() {
        let presentation = CodexMotionPresentation(
            presetID: nil,
            dismissal: .afterDuration,
            durationSeconds: 9,
            dismissPadID: "grid_0_0"
        )

        XCTAssertEqual(presentation.automaticStopDelay, 9)
    }

    func testCodexMotionPresentation_whenDecodingLegacyTimedRunningRule_keepsTimedBehavior() throws {
        // Given
        let data = Data("""
        {
          "presetID": null,
          "dismissal": "afterDuration",
          "durationSeconds": 9,
          "dismissPadID": "grid_0_0"
        }
        """.utf8)

        // When
        let presentation = try JSONDecoder().decode(CodexMotionPresentation.self, from: data)

        // Then
        XCTAssertEqual(presentation.automaticStopDelay(for: .running), 9)
    }

    func testCodexMotionPresentation_whenRunningRuleIsHeld_skipsOnlyLiveAutomaticStop() {
        // Given
        let presentation = CodexMotionPresentation(
            presetID: nil,
            dismissal: .afterDuration,
            durationSeconds: 9,
            dismissPadID: "grid_0_0",
            keepsRunningUntilActivityChanges: true
        )

        // When
        let liveStopDelay = presentation.automaticStopDelay(for: .running)
        let previewStopDelay = presentation.automaticStopDelay

        // Then
        XCTAssertNil(liveStopDelay)
        XCTAssertEqual(previewStopDelay, 9)
    }

    func testCodexMotionPresentation_whenRunningRuleIsNotHeld_remainsTimed() {
        // Given
        let presentation = CodexMotionPresentation(
            presetID: nil,
            dismissal: .afterDuration,
            durationSeconds: 9,
            dismissPadID: "grid_0_0",
            keepsRunningUntilActivityChanges: false
        )

        // When
        let liveStopDelay = presentation.automaticStopDelay(for: .running)

        // Then
        XCTAssertEqual(liveStopDelay, 9)
    }

    func testCodexMotionPresentation_whenHeldRunningRuleUsesAnyPadDismissal_stillEndsOnManualPadPress() {
        // Given
        let presentation = CodexMotionPresentation(
            presetID: nil,
            dismissal: .anyPad,
            durationSeconds: 9,
            dismissPadID: "grid_0_0",
            keepsRunningUntilActivityChanges: true
        )

        // When
        let shouldDismiss = presentation.shouldDismiss(for: "side_3")

        // Then
        XCTAssertTrue(shouldDismiss)
    }
}
