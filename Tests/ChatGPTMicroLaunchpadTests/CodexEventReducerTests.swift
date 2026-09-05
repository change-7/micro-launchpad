import XCTest
@testable import ChatGPTMicroLaunchpad

final class CodexEventReducerTests: XCTestCase {
    func testActivity_whenExistingReducerReceivesMixedCaseTurnStart_remainsRunning() {
        XCTAssertEqual(CodexEventReducer.activity(for: "TURN/STARTED"), .running)
    }

    func testActivity_whenCodexStreamsAnyTurnOrItemProgress_remainsRunning() {
        let progressMethods = [
            "item/agentMessage/delta",
            "item/commandExecution/outputDelta",
            "item/completed",
            "turn/diff/updated",
            "thread/realtime/itemAdded",
            "rawResponse/completed"
        ]

        for method in progressMethods {
            XCTAssertEqual(CodexEventReducer.activity(for: method), .running, "Expected \(method) to keep Codex marked as running")
        }
    }

    func testActivity_whenTurnCompletes() {
        XCTAssertEqual(CodexEventReducer.activity(for: "turn/completed"), .completed)
    }

    func testActivity_whenApprovalIsRequested() {
        XCTAssertEqual(CodexEventReducer.activity(for: "item/commandExecution/requestApproval"), .waitingForApproval)
    }

    func testActivity_whenCodexIsAwaitingConfirmationOrInput() {
        XCTAssertEqual(CodexEventReducer.activity(for: "turn/awaitingInput"), .waitingForApproval)
        XCTAssertEqual(CodexEventReducer.activity(for: "confirmation/required"), .waitingForApproval)
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

    func testCodexMotionPresentation_whenDecodingLegacyTimedRunningRule_keepsLiveWorkHeld() throws {
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
        XCTAssertNil(presentation.automaticStopDelay(for: .running))
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

    func testCodexMotionPresentation_whenRunningRuleIsNotHeld_stillHoldsLiveWork() {
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
        XCTAssertNil(liveStopDelay)
    }

    func testCodexMotionPresentation_whenWaitingForApproval_holdsUntilTerminalState() {
        let presentation = CodexMotionPresentation(durationSeconds: 9)

        XCTAssertNil(presentation.automaticStopDelay(for: .waitingForApproval))
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

    func testGridPadSwap_movesConfigurationWithoutMovingPhysicalIDs() {
        var page = LaunchPage(
            name: "P1",
            pads: [
                Pad(id: "grid_0_0", title: "ChatGPT", symbol: "sparkles", idleColor: "green", activeColor: "brightGreen", action: PadAction(kind: .app, value: "ChatGPT")),
                Pad(id: "grid_0_1", title: "브라우저", symbol: "globe", idleColor: "amber", activeColor: "yellow", action: PadAction(kind: .url, value: "https://example.com"))
            ]
        )

        XCTAssertTrue(page.swapGridPadConfigurations(from: "grid_0_0", to: "grid_0_1"))
        XCTAssertEqual(page.pads[0].id, "grid_0_0")
        XCTAssertEqual(page.pads[0].title, "브라우저")
        XCTAssertEqual(page.pads[0].action.kind, .url)
        XCTAssertEqual(page.pads[1].id, "grid_0_1")
        XCTAssertEqual(page.pads[1].title, "ChatGPT")
        XCTAssertEqual(page.pads[1].action.kind, .app)
    }

    func testGridPadClear_removesConfigurationWithoutRemovingPhysicalPad() {
        var page = LaunchPage(name: "Test", pads: [
            Pad(id: "grid_0_0", title: "Delete me", symbol: "trash", idleColor: "red", activeColor: "green", action: PadAction(kind: .url, value: "https://example.com"))
        ])

        XCTAssertTrue(page.clearGridPadConfiguration("grid_0_0"))
        XCTAssertEqual(page.pads, [Pad(id: "grid_0_0")])
    }

    func testSmartphoneButtonSwap_movesConfigurationWithoutMovingPhysicalIDs() {
        var page = SmartphonePage(
            id: "smartphone_page_0",
            name: "PAGE 01",
            buttons: [
                SmartphoneButton(id: "smartphone_page_0_button_0", title: "실행", symbol: "play.fill", action: PadAction(kind: .shortcut, value: "cmd+r")),
                SmartphoneButton(id: "smartphone_page_0_button_1", title: "브라우저", symbol: "globe", action: PadAction(kind: .url, value: "https://example.com"))
            ]
        )

        XCTAssertTrue(page.swapButtonConfigurations(
            from: "smartphone_page_0_button_0",
            to: "smartphone_page_0_button_1"
        ))
        XCTAssertEqual(page.buttons[0].id, "smartphone_page_0_button_0")
        XCTAssertEqual(page.buttons[0].title, "브라우저")
        XCTAssertEqual(page.buttons[0].action.kind, .url)
        XCTAssertEqual(page.buttons[1].id, "smartphone_page_0_button_1")
        XCTAssertEqual(page.buttons[1].title, "실행")
        XCTAssertEqual(page.buttons[1].action.kind, .shortcut)
    }

    func testMotionPresetRename_trimsAndPersistsTheNewName() {
        let store = LaunchpadStore()
        let preset = MotionPreset(name: "Old", loop: false, frameDurationMs: 100, frames: [MotionFrame(pixels: [])])
        store.addMotionPreset(preset)

        XCTAssertTrue(store.renameMotionPreset(id: preset.id, to: "  New Name  "))
        XCTAssertEqual(store.motionPresets.first(where: { $0.id == preset.id })?.name, "New Name")

        store.removeMotionPreset(preset)
    }
}
