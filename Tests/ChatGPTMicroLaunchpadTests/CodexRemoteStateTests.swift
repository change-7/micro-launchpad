import XCTest
@testable import ChatGPTMicroLaunchpad

final class CodexRemoteStateTests: XCTestCase {
    @MainActor
    func testUsageRefresh_whenResponseIsMissingRetainsLastKnownUsage() {
        let existingWeekly = CodexWeeklyUsage(usedPercent: 33, resetsAt: nil)
        let refreshedWeekly = CodexWeeklyUsage(usedPercent: 41, resetsAt: nil)

        XCTAssertEqual(
            CodexAppServerClient.retainedUsage(existing: existingWeekly, refreshed: nil),
            existingWeekly,
            "A transient rate-limit failure must not blank the usage gauge."
        )
        XCTAssertEqual(
            CodexAppServerClient.retainedUsage(existing: existingWeekly, refreshed: refreshedWeekly),
            refreshedWeekly
        )
    }

    func testRemoteState_whenMacReportsUsedPercent_exposesMatchingRemainingPercent() {
        let usage = CodexWeeklyUsage(usedPercent: 33, resetsAt: nil)
        let fiveHourUsage = CodexFiveHourUsage(usedPercent: 16, resetsAt: nil)
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: true,
            activity: .running,
            message: "Codex 작업 중",
            weeklyUsage: usage,
            fiveHourUsage: fiveHourUsage
        )

        XCTAssertEqual(state.usedPercent, 33)
        XCTAssertEqual(state.remainingPercent, 67)
        XCTAssertEqual(state.fiveHourUsedPercent, 16)
        XCTAssertEqual(state.fiveHourRemainingPercent, 84)
    }

    func testRemoteState_whenUsageIsMissing_doesNotInventPhoneUsage() {
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: false,
            activity: .idle,
            message: "Codex App Server 연결됨",
            weeklyUsage: nil,
            fiveHourUsage: nil
        )

        XCTAssertNil(state.usedPercent)
        XCTAssertNil(state.remainingPercent)
    }

    func testRemoteCommand_roundTripsItsStableWireFields() throws {
        let command = CodexRemoteCommand(
            type: "command",
            protocolVersion: 1,
            id: "test-command",
            command: "terminal"
        )

        let encoded = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(CodexRemoteCommand.self, from: encoded)

        XCTAssertEqual(decoded, command)
    }

    func testRemoteCommandResult_usesCommandResultEnvelope() throws {
        let result = CodexRemoteCommandResult(id: "test-command", success: true, message: "앱을 열었습니다.")

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
        )

        XCTAssertEqual(object["type"] as? String, "commandResult")
        XCTAssertEqual(object["protocolVersion"] as? Int, 1)
        XCTAssertEqual(object["id"] as? String, "test-command")
        XCTAssertEqual(object["success"] as? Bool, true)
    }

    func testSmartphoneDefaults_areIndependentFromMacLaunchpadPages() {
        let smartphonePages = SmartphoneDefaults.pages()

        XCTAssertEqual(smartphonePages.count, 3)
        XCTAssertEqual(smartphonePages.flatMap(\.buttons).count, 48)
        XCTAssertEqual(smartphonePages[0].buttons[0].action, PadAction(kind: .shortcut, value: "cmd+r"))
        XCTAssertNotEqual(smartphonePages[0].buttons[0].id, "grid_0_0")
    }

    func testPadAction_repairsLegacyAppBundleIDStoredAsShortcutValue() {
        let action = PadAction(
            kind: .shortcut,
            value: "com.openai.codex",
            targetAppBundleIdentifier: "com.openai.codex"
        )

        XCTAssertEqual(action.repairedForPersistence.value, "")
        XCTAssertEqual(action.repairedForPersistence.targetAppBundleIdentifier, "com.openai.codex")
    }

    func testSmartphoneDefaults_bridgeHelperReadsSharedPageNames() throws {
        let suiteName = "test.smartphone-bridge-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }

        var pages = SmartphoneDefaults.pages()
        pages[1].name = "집중 작업"
        preferences.set(try JSONEncoder().encode(pages), forKey: "chatgpt-micro-launchpad.smartphone-pages")

        XCTAssertEqual(SmartphoneDefaults.persistedPages(from: preferences)[1].name, "집중 작업")
    }

    func testRemoteState_transmitsSmartphoneButtonActionWithoutChangingMacPadShape() throws {
        var smartphonePages = SmartphoneDefaults.pages()
        smartphonePages[1].name = "집중 작업"
        smartphonePages[0].buttons[0].action = PadAction(kind: .url, value: "https://example.com")
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: false,
            activity: .idle,
            message: "연결됨",
            weeklyUsage: nil,
            fiveHourUsage: nil,
            smartphonePages: smartphonePages
        )

        let decoded = try JSONDecoder().decode(CodexRemoteState.self, from: JSONEncoder().encode(state))

        XCTAssertEqual(decoded.smartphonePages[0].buttons[0].action, PadAction(kind: .url, value: "https://example.com"))
        XCTAssertEqual(decoded.smartphonePages[1].name, "집중 작업")
        XCTAssertEqual(decoded.smartphonePages[0].buttons.count, 16)
    }

    func testRemoteState_roundTripsSmartphoneIconAssets() throws {
        let asset = SmartphoneIconAsset(data: Data([0, 1, 2]).base64EncodedString())
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: true,
            activity: .idle,
            message: "연결됨",
            weeklyUsage: nil,
            fiveHourUsage: nil,
            smartphoneIconAssets: ["smartphone_page_0_button_0": asset]
        )

        let decoded = try JSONDecoder().decode(CodexRemoteState.self, from: JSONEncoder().encode(state))

        XCTAssertEqual(decoded.smartphoneIconAssets?["smartphone_page_0_button_0"], asset)
    }

    func testRemoteState_decodesLegacyPayloadWithoutIconAssets() throws {
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: true,
            activity: .idle,
            message: "연결됨",
            weeklyUsage: nil,
            fiveHourUsage: nil
        )
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]
        )
        object.removeValue(forKey: "smartphoneIconAssets")
        let decoded = try JSONDecoder().decode(CodexRemoteState.self, from: JSONSerialization.data(withJSONObject: object))

        XCTAssertNil(decoded.smartphoneIconAssets)
        XCTAssertEqual(decoded.smartphonePages.count, 3)
    }

    func testRemoteIconAssetsEnvelope_usesDedicatedWireMessage() throws {
        let asset = SmartphoneIconAsset(data: Data([7, 8, 9]).base64EncodedString())
        let envelope = CodexRemoteIconAssets(assets: ["button": asset])
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope)) as? [String: Any]
        )

        XCTAssertEqual(object["type"] as? String, "smartphoneIconAssets")
        XCTAssertEqual(object["protocolVersion"] as? Int, 1)
        XCTAssertNotNil((object["assets"] as? [String: Any])?["button"])
    }

    @MainActor
    func testSmartphoneIconAssetProvider_buildsAppIconAssetsForRegisteredButtons() {
        let assets = SmartphoneIconAssetProvider.assets(for: SmartphoneDefaults.pages())

        XCTAssertNotNil(assets["smartphone_page_0_button_3"])
        XCTAssertEqual(assets["smartphone_page_0_button_3"]?.mimeType, "image/png")
    }

    @MainActor
    func testSmartphoneIconAssetProvider_buildsTargetAppIconAssetsForShortcuts() {
        var pages = SmartphoneDefaults.pages()
        pages[0].buttons[0].action = PadAction(
            kind: .shortcut,
            value: "cmd+r",
            targetAppBundleIdentifier: "com.apple.Terminal"
        )

        let assets = SmartphoneIconAssetProvider.assets(for: pages)

        XCTAssertNotNil(assets["smartphone_page_0_button_0"])
        XCTAssertEqual(assets["smartphone_page_0_button_0"]?.mimeType, "image/png")
    }

    func testRemoteState_transmitsPendingApprovalPrompt() throws {
        let approval = CodexRemoteApproval(
            requestID: 42,
            title: "파일 변경 승인 필요",
            detail: "README.md를 수정합니다."
        )
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: true,
            activity: .waitingForApproval,
            message: "Codex 승인을 기다리는 중",
            weeklyUsage: nil,
            fiveHourUsage: nil,
            approval: approval
        )

        let decoded = try JSONDecoder().decode(CodexRemoteState.self, from: JSONEncoder().encode(state))

        XCTAssertEqual(decoded.approval, approval)
    }

    @MainActor
    func testRemoteActivity_pendingApprovalTakesPrecedenceOverDesktopRunningActivity() {
        XCTAssertEqual(
            CodexAppServerClient.remoteActivity(
                desktopActivity: .running,
                appServerActivity: .running,
                hasPendingApproval: true
            ),
            .waitingForApproval
        )
    }

    @MainActor
    func testRemoteActivity_desktopCompletionOverridesStaleAppServerRunning() {
        XCTAssertEqual(
            CodexAppServerClient.remoteActivity(
                desktopActivity: .completed,
                appServerActivity: .running,
                hasPendingApproval: false
            ),
            .completed,
            "A stale app-server running state must not hide desktop task completion."
        )
    }

    func testRemoteState_transmitsActiveSessionCount() throws {
        let state = CodexRemoteState(
            macConnected: true,
            codexConnected: true,
            activity: .running,
            message: "2개 작업 중",
            weeklyUsage: nil,
            fiveHourUsage: nil,
            activeSessionCount: 2
        )

        let decoded = try JSONDecoder().decode(CodexRemoteState.self, from: JSONEncoder().encode(state))

        XCTAssertEqual(decoded.activeSessionCount, 2)
    }

    func testRemoteCommand_roundTripsSmartphoneActionPayload() throws {
        let command = CodexRemoteCommand(
            type: "command",
            protocolVersion: 1,
            id: "phone-button",
            command: "smartphoneButton",
            buttonID: "smartphone_page_0_button_0",
            action: PadAction(kind: .shortcut, value: "cmd+shift+4")
        )

        let decoded = try JSONDecoder().decode(CodexRemoteCommand.self, from: JSONEncoder().encode(command))

        XCTAssertEqual(decoded.buttonID, "smartphone_page_0_button_0")
        XCTAssertEqual(decoded.action, PadAction(kind: .shortcut, value: "cmd+shift+4"))
    }

    func testRemoteCommand_roundTripsTerminalCommandActionPayload() throws {
        let action = PadAction(kind: .terminalCommand, value: "open -a Safari")
        let command = CodexRemoteCommand(
            type: "command",
            protocolVersion: 1,
            id: "phone-terminal-button",
            command: "smartphoneButton",
            buttonID: "smartphone_page_0_button_0",
            action: action
        )

        let decoded = try JSONDecoder().decode(CodexRemoteCommand.self, from: JSONEncoder().encode(command))

        XCTAssertEqual(decoded.action, action)
    }

    func testTerminalAutomationBundleDeclaresAppleEventsUsageDescription() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = projectRoot.appendingPathComponent("script/Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(
            plist["NSAppleEventsUsageDescription"] as? String,
            "마이크로 런치패드가 버튼에 등록된 터미널 명령을 실행하기 위해 Terminal을 제어합니다."
        )
    }

    @MainActor
    func testTerminalCommandScript_createsCommandWindowBeforeActivatingTerminal() {
        let source = MacActionRunner.terminalAppleScript(for: "echo test")
        let commandOffset = source.distance(from: source.startIndex, to: source.range(of: "do script")!.lowerBound)
        let activateOffset = source.distance(from: source.startIndex, to: source.range(of: "activate")!.lowerBound)

        XCTAssertLessThan(commandOffset, activateOffset)
    }

    @MainActor
    func testTerminalCommandScript_reusesExistingFrontWindowInsteadOfOpeningAnother() {
        let source = MacActionRunner.terminalAppleScript(for: "echo test")

        XCTAssertTrue(source.contains("reopen"))
        XCTAssertTrue(source.contains("repeat until (count of windows) > 0"))
        XCTAssertTrue(source.contains("in front window"))
    }

    func testRemoteCommand_roundTripsCodexApprovalDecision() throws {
        let command = CodexRemoteCommand(
            type: "command",
            protocolVersion: 1,
            id: "approval-response",
            command: "codexApproval",
            decision: "accept"
        )

        let decoded = try JSONDecoder().decode(CodexRemoteCommand.self, from: JSONEncoder().encode(command))

        XCTAssertEqual(decoded.decision, "accept")
    }
}
