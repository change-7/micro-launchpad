import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class CodexAppServerLaunchLifecycleTests: XCTestCase {
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
