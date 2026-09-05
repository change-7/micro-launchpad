import AppKit
import XCTest
@testable import ChatGPTMicroLaunchpad

final class CodexActivityIntegrationTests: XCTestCase {
    @MainActor
    func testIntegration_whenDesktopTaskStarts_reachesMotionPresentationCallbackAsRunning() async throws {
        // Given
        let fixture = try MonitorFixture()
        let controller = makeController(fixture: fixture)
        let router = CodexMotionActivityRouter()
        var presented: [CodexActivity] = []
        controller.onActivityChange = { activity in
            router.present(activity, using: { presented.append($0) })
        }
        controller.startDesktopMonitoring()
        await fixture.waitForMonitorToBecomeIdle()
        _ = try fixture.writeTranscript(
            relativePath: "2026/08/01/integration.jsonl",
            contents: userMetadata + taskStarted(turnID: "desktop-live")
        )

        // When
        fixture.scheduler.fire()
        await fixture.waitForMonitorToBecomeIdle()

        // Then
        XCTAssertEqual(controller.activity, .running)
        XCTAssertEqual(router.presentedActivity, .running)
        XCTAssertEqual(presented, [.running])
    }

    @MainActor
    func testIntegration_whenRunningTranscriptIsDeleted_publishesOneTerminalActivityThroughTheController() async throws {
        // Given
        let fixture = try MonitorFixture()
        let controller = makeController(fixture: fixture)
        var activityChanges: [CodexActivity] = []
        controller.onActivityChange = { activityChanges.append($0) }
        controller.startDesktopMonitoring()
        await fixture.waitForMonitorToBecomeIdle()
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/deleted.jsonl",
            contents: userMetadata + taskStarted(turnID: "abandoned")
        )
        fixture.scheduler.fire()
        await fixture.waitForMonitorToBecomeIdle()
        XCTAssertEqual(controller.activity, .running)
        activityChanges.removeAll()

        // When
        try FileManager.default.removeItem(at: transcript)
        fixture.scheduler.fire()
        await fixture.waitForMonitorToBecomeIdle()
        fixture.scheduler.fire()
        await fixture.waitForMonitorToBecomeIdle()

        // Then
        XCTAssertEqual(controller.activity, .completed)
        XCTAssertEqual(activityChanges, [.completed])
    }

    @MainActor
    func testCoordinator_whenAppServerTerminatesDuringDesktopWork_keepsEffectiveActivityRunning() async throws {
        // Given
        let fixture = try MonitorFixture()
        let controller = makeController(fixture: fixture)
        controller.startDesktopMonitoring()
        await fixture.waitForMonitorToBecomeIdle()
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/desktop-running.jsonl",
            contents: userMetadata + taskStarted(turnID: "desktop")
        )
        fixture.scheduler.fire()
        await fixture.waitForMonitorToBecomeIdle()
        var presentationChanges: [CodexActivity] = []
        controller.onActivityChange = { presentationChanges.append($0) }

        // When
        controller.updateAppServerActivity(.completed)

        // Then
        XCTAssertEqual(controller.activity, .running)
        XCTAssertTrue(presentationChanges.isEmpty)
        try fixture.append(taskCompleted(turnID: "desktop"), to: transcript)
        fixture.scheduler.fire()
        await fixture.waitForMonitorToBecomeIdle()
        XCTAssertEqual(controller.activity, .completed)
        XCTAssertEqual(presentationChanges, [.completed])
    }

    @MainActor
    func testMultipleDesktopSessions_whenOneCompletes_emitsCompletionAttentionWhileAnotherRuns() async throws {
        // Given
        let fixture = try MonitorFixture()
        let controller = makeController(fixture: fixture)
        var completionCount = 0
        controller.onTaskCompletion = { @MainActor _ in completionCount += 1 }
        controller.startDesktopMonitoring()
        await fixture.waitForMonitorToBecomeIdle()
        let first = try fixture.writeTranscript(
            relativePath: "2026/08/01/session-one.jsonl",
            contents: userMetadata + taskStarted(turnID: "one")
        )
        let second = try fixture.writeTranscript(
            relativePath: "2026/08/01/session-two.jsonl",
            contents: userMetadata + taskStarted(turnID: "two")
        )
        fixture.scheduler.fire()
        await fixture.waitForMonitorToBecomeIdle()
        XCTAssertEqual(controller.activeSessionCount, 1)

        // When only the first session completes
        try fixture.append(taskCompleted(turnID: "one"), to: first)
        fixture.scheduler.fire()
        await fixture.waitForMonitorToBecomeIdle()

        // Then
        XCTAssertEqual(controller.activity, .running)
        XCTAssertEqual(controller.activeSessionCount, 1)
        XCTAssertEqual(completionCount, 1)

        // And the second session can complete independently
        try fixture.append(taskCompleted(turnID: "two"), to: second)
        fixture.scheduler.fire()
        await fixture.waitForMonitorToBecomeIdle()
        XCTAssertEqual(completionCount, 2)
        XCTAssertEqual(controller.activeSessionCount, 0)
        XCTAssertEqual(controller.activity, .completed)
    }

    @MainActor
    func testCoordinator_whenDesktopTerminatesAndAppServerStatusIsStale_publishesDesktopCompletion() async throws {
        // Given
        let fixture = try MonitorFixture()
        let controller = makeController(fixture: fixture)
        controller.startDesktopMonitoring()
        await fixture.waitForMonitorToBecomeIdle()
        controller.updateAppServerActivity(.running)
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/app-server-running.jsonl",
            contents: userMetadata + taskStarted(turnID: "desktop")
        )
        fixture.scheduler.fire()
        await fixture.waitForMonitorToBecomeIdle()
        var presentationChanges: [CodexActivity] = []
        controller.onActivityChange = { presentationChanges.append($0) }

        // When
        try fixture.append(taskCompleted(turnID: "desktop"), to: transcript)
        fixture.scheduler.fire()
        await fixture.waitForMonitorToBecomeIdle()

        // Then
        XCTAssertEqual(controller.activity, .completed)
        XCTAssertEqual(presentationChanges, [.completed])
    }

    @MainActor
    func testActiveSessionCount_whenDesktopCompletesWhileAppServerIsStaleRunning_becomesZero() async throws {
        let fixture = try MonitorFixture()
        let controller = makeController(fixture: fixture)
        controller.startDesktopMonitoring()
        await fixture.waitForMonitorToBecomeIdle()
        controller.updateAppServerActivity(.running)
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/stale-running-count.jsonl",
            contents: userMetadata + taskStarted(turnID: "desktop")
        )
        fixture.scheduler.fire()
        await fixture.waitForMonitorToBecomeIdle()
        XCTAssertEqual(controller.activeSessionCount, 1)

        try fixture.append(taskCompleted(turnID: "desktop"), to: transcript)
        fixture.scheduler.fire()
        await fixture.waitForMonitorToBecomeIdle()

        XCTAssertEqual(
            controller.activeSessionCount,
            0,
            "A completed desktop task must clear the count even when app-server status is stale running."
        )
    }

    @MainActor
    func testCoordinator_whenAppServerStartsNewWorkAfterDesktopCompletion_clearsStaleCompletion() async throws {
        // Given
        let fixture = try MonitorFixture()
        let controller = makeController(fixture: fixture)
        controller.startDesktopMonitoring()
        await fixture.waitForMonitorToBecomeIdle()
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/stale-completion.jsonl",
            contents: userMetadata
                + taskStarted(turnID: "previous")
                + taskCompleted(turnID: "previous")
        )
        fixture.scheduler.fire()
        await fixture.waitForMonitorToBecomeIdle()
        XCTAssertEqual(controller.activity, .completed)

        // When a new App Server turn starts before the desktop monitor sees its task_started event
        controller.updateAppServerActivity(.running)

        // Then
        XCTAssertEqual(controller.activity, .running)
        _ = transcript
    }

    @MainActor
    func testDismissal_whenAppServerActivityIsStale_resolvesPresentationForEffectivePresentedActivity() {
        // Given
        let router = CodexMotionActivityRouter()
        router.present(.running, using: { _ in })
        var resolvedActivity: CodexActivity?

        // When
        _ = router.dismissalPresentation { activity in
            resolvedActivity = activity
            return CodexMotionPresentation(dismissal: .anyPad)
        }

        // Then
        XCTAssertEqual(resolvedActivity, .running)
    }

    @MainActor
    func testMotionRouting_whenHeldRunningActivityChanges_endsTheHeldMotionBeforePresentingTheNewStatus() {
        // Given
        let router = CodexMotionActivityRouter()
        var events: [String] = []
        router.present(
            .running,
            endingCurrentMotion: { events.append("end") },
            using: { activity in events.append("present:\(activity.rawValue)") }
        )
        events.removeAll()

        // When
        router.present(
            .completed,
            endingCurrentMotion: { events.append("end") },
            using: { activity in events.append("present:\(activity.rawValue)") }
        )

        // Then
        XCTAssertEqual(events, ["end", "present:completed"])
        XCTAssertEqual(router.presentedActivity, .completed)
    }

    @MainActor
    func testLifecycle_whenApplicationWillFinishLaunchingRepeats_startsMonitorOnceAndStopsAtTermination() async throws {
        // Given
        let fixture = try MonitorFixture()
        let controller = makeController(fixture: fixture)
        let delegate = AppDelegate(codexActivityController: controller)
        let notification = Notification(name: NSApplication.willFinishLaunchingNotification)

        // When
        delegate.applicationWillFinishLaunching(notification)
        delegate.applicationWillFinishLaunching(notification)

        // Then
        XCTAssertEqual(fixture.scheduler.scheduleCallCount, 1)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        XCTAssertTrue(fixture.scheduler.isCancelled)
    }

    @MainActor
    func testLifecycle_whenMonitoringStops_discardsStaleDesktopRunningState() async throws {
        // Given
        let fixture = try MonitorFixture()
        let controller = makeController(fixture: fixture)
        controller.startDesktopMonitoring()
        await fixture.waitForMonitorToBecomeIdle()
        controller.updateAppServerActivity(.completed)
        _ = try fixture.writeTranscript(
            relativePath: "2026/08/01/stale.jsonl",
            contents: userMetadata + taskStarted(turnID: "stale")
        )
        fixture.scheduler.fire()
        await fixture.waitForMonitorToBecomeIdle()
        XCTAssertEqual(controller.activity, .running)

        // When
        controller.stopDesktopMonitoring()

        // Then
        XCTAssertEqual(controller.activity, .completed)
    }
}

private extension CodexActivityIntegrationTests {
    @MainActor
    func makeController(fixture: MonitorFixture) -> CodexActivityController {
        CodexActivityController(makeMonitor: { onEvents in
            fixture.makeMonitor(onEvents: onEvents)
        })
    }

    var userMetadata: String {
        "{\"type\":\"session_meta\",\"payload\":{\"originator\":\"Codex Desktop\",\"thread_source\":\"user\"}}\n"
    }

    func taskStarted(turnID: String) -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"\(turnID)\"}}\n"
    }

    func taskCompleted(turnID: String) -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"\(turnID)\"}}\n"
    }
}
