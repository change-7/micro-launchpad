import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class CodexAppServerLaunchLifecycleTests: XCTestCase {
    func testRemoteActivity_whenNewTurnArrives_clearsPreviousDesktopCompletion() {
        XCTAssertTrue(
            CodexAppServerClient.shouldResetDesktopActivity(
                for: .running,
                desktopActivity: .completed
            )
        )
        XCTAssertTrue(
            CodexAppServerClient.shouldResetDesktopActivity(
                for: .waitingForApproval,
                desktopActivity: .completed
            )
        )
        XCTAssertFalse(
            CodexAppServerClient.shouldResetDesktopActivity(
                for: .idle,
                desktopActivity: .completed
            )
        )
    }

    func testRemoteActivity_whenStaleActiveNotificationRepeats_doesNotClearDesktopCompletion() {
        XCTAssertFalse(
            CodexAppServerClient.shouldResetDesktopActivity(
                for: .running,
                desktopActivity: .completed,
                previousAppServerActivity: .running
            ),
            "A repeated app-server running notification must not resurrect a completed desktop task."
        )
    }

    func testRemoteMessage_whenMultipleSessionsAreRunning_includesTheActiveCount() {
        XCTAssertEqual(
            CodexAppServerClient.remoteMessage(
                for: .running,
                activeSessionCount: 2,
                fallbackMessage: "fallback"
            ),
            "2개 작업 중"
        )
        XCTAssertEqual(
            CodexAppServerClient.remoteMessage(
                for: .waitingForApproval,
                activeSessionCount: 3,
                fallbackMessage: "fallback"
            ),
            "3개 작업 중 · 승인 대기"
        )
    }

    func testWeeklyUsage_whenWeeklyLimitIsSecondary_readsExactlyTheSevenDayWindow() {
        let result: [String: Any] = [
            "rateLimits": [
                "primary": ["windowDurationMins": 300, "usedPercent": 4],
                "secondary": ["windowDurationMins": 10_080, "usedPercent": 77, "resetsAt": 1_786_161_493]
            ]
        ]

        let usage = CodexAppServerClient.weeklyUsage(from: result)

        XCTAssertEqual(usage?.usedPercent, 77)
        XCTAssertEqual(usage?.resetsAt?.timeIntervalSince1970, 1_786_161_493)
    }

    func testWeeklyUsage_whenOnlyALongerWindowExists_doesNotTreatItAsWeekly() {
        let result: [String: Any] = [
            "rateLimits": [
                "primary": ["windowDurationMins": 43_200, "usedPercent": 12]
            ]
        ]

        XCTAssertNil(CodexAppServerClient.weeklyUsage(from: result))
    }

    func testUsage_whenFiveHourAndWeeklyWindowsExist_returnsBothWindows() {
        let result: [String: Any] = [
            "rateLimits": [
                "primary": ["windowDurationMins": 300, "usedPercent": 16, "resetsAt": 1_786_161_000],
                "secondary": ["windowDurationMins": 10_080, "usedPercent": 22, "resetsAt": 1_786_161_493]
            ]
        ]

        let usage = CodexAppServerClient.usage(from: result)

        XCTAssertEqual(usage.fiveHour?.usedPercent, 16)
        XCTAssertEqual(usage.fiveHour?.resetsAt?.timeIntervalSince1970, 1_786_161_000)
        XCTAssertEqual(usage.weekly?.usedPercent, 22)
        XCTAssertEqual(usage.weekly?.resetsAt?.timeIntervalSince1970, 1_786_161_493)
    }

    func testWeeklyUsage_whenOtherLimitAlsoHasSevenDayWindow_usesCodexLimit() {
        let result: [String: Any] = [
            "rateLimits": [
                "limitId": "codex",
                "secondary": ["windowDurationMins": 10_080, "usedPercent": 67]
            ],
            "rateLimitsByLimitId": [
                "codex": [
                    "limitId": "codex",
                    "secondary": ["windowDurationMins": 10_080, "usedPercent": 67]
                ],
                "base_model_inference": [
                    "limitId": "base_model_inference",
                    "primary": ["windowDurationMins": 10_080, "usedPercent": 0]
                ]
            ]
        ]

        XCTAssertEqual(
            CodexAppServerClient.weeklyUsage(from: result)?.usedPercent,
            67,
            "The unrelated base-model seven-day limit must not replace Codex weekly usage."
        )
    }

    func testUsageRefresh_whenLastRefreshIsOlderThanInterval_isDue() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(
            CodexAppServerClient.shouldRefreshUsage(
                lastRefreshAt: now.addingTimeInterval(-31),
                now: now
            )
        )
        XCTAssertFalse(
            CodexAppServerClient.shouldRefreshUsage(
                lastRefreshAt: now.addingTimeInterval(-29),
                now: now
            )
        )
    }

    func testMainApplicationWindow_whenBubblePrecedesMainWindow_selectsTheTitledWindow() {
        // Given
        let bubble = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let mainWindow = NSWindow(
            contentRect: .zero,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        // When
        let selectedWindow = AppDelegate.mainApplicationWindow(in: [bubble, mainWindow])

        // Then
        XCTAssertIdentical(selectedWindow, mainWindow)
    }

    func testMissingCLIDiagnostic_whenDirectExecutableWritesGenericNotFoundWarning_isIgnored() {
        // Given
        let diagnostic = "warning: cache entry not found; continuing"

        // When
        let isMissingCLI = CodexAppServerClient.isMissingCLIDiagnostic(
            diagnostic,
            isUsingShellFallback: false
        )

        // Then
        XCTAssertFalse(isMissingCLI)
    }

    func testMissingCLIDiagnostic_whenShellFallbackCannotExecCodex_isReported() {
        // Given
        let diagnostic = "zsh:1: command not found: codex"

        // When
        let isMissingCLI = CodexAppServerClient.isMissingCLIDiagnostic(
            diagnostic,
            isUsingShellFallback: true
        )

        // Then
        XCTAssertTrue(isMissingCLI)
    }

    func testLaunchCommand_whenVendorRuntimeIsExecutable_selectsDirectExecutableInsteadOfShellFallback() {
        // Given
        let vendorRuntimePath = NSHomeDirectory() + "/Library/Application Support/마이크로 런치패드/codex-runtime/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"

        // When
        let command = CodexAppServerClient.launchCommand(isExecutable: { path in
            path == vendorRuntimePath
        })

        // Then
        XCTAssertEqual(command.executableURL.path, vendorRuntimePath)
        XCTAssertEqual(command.arguments, ["app-server"])
    }

    func testLaunchCommand_whenNodeWrapperAndVendorRuntimeAreExecutable_prefersNativeVendorRuntime() {
        // Given
        let supportDirectory = NSHomeDirectory() + "/Library/Application Support/마이크로 런치패드/codex-runtime/node_modules"
        let nodeWrapperPath = supportDirectory + "/.bin/codex"
        let vendorRuntimePath = supportDirectory + "/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"

        // When
        let command = CodexAppServerClient.launchCommand(isExecutable: { path in
            path == nodeWrapperPath || path == vendorRuntimePath
        })

        // Then
        XCTAssertEqual(command.executableURL.path, vendorRuntimePath)
        XCTAssertEqual(command.arguments, ["app-server"])
    }

    func testLaunchCommand_whenAnInstalledRuntimeIsAvailable_runsTheSelectedExecutableVersion() throws {
        // Given
        let command = CodexAppServerClient.launchCommand(isExecutable: FileManager.default.isExecutableFile(atPath:))
        let output = Pipe()
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = ["--version"]
        process.standardOutput = output

        // When
        try process.run()
        process.waitUntilExit()

        // Then
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.contains("codex-cli") == true)
    }

    func testApplicationWillFinishLaunching_whenCalledTwice_startsConnectionOnceWithoutStartingATask() throws {
        // Given
        let fixture = try MonitorFixture()
        let controller = CodexActivityController(makeMonitor: { onEvents in
            fixture.makeMonitor(onEvents: onEvents)
        })
        let starter = ConnectionStarterSpy()
        let delegate = AppDelegate(codexActivityController: controller, connectionStarter: starter)
        let notification = Notification(name: NSApplication.willFinishLaunchingNotification)

        // When
        delegate.applicationWillFinishLaunching(notification)
        delegate.applicationWillFinishLaunching(notification)

        // Then
        XCTAssertEqual(starter.connectionRequestCount, 1)
        XCTAssertEqual(starter.taskRequestCount, 0)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }
}

@MainActor
private final class ConnectionStarterSpy: CodexAppServerConnectionStarting {
    private(set) var connectionRequestCount = 0
    private(set) var taskRequestCount = 0

    func connect() {
        connectionRequestCount += 1
    }

    func startTask(prompt: String, workingDirectory: String) {
        taskRequestCount += 1
    }
}
