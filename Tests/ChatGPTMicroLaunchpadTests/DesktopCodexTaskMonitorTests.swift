import XCTest
@testable import ChatGPTMicroLaunchpad

final class DesktopCodexTaskMonitorTests: XCTestCase {
    @MainActor
    func testMonitor_whenACompleteTranscriptPredatesStart_seedsAtEOFWithoutPublishingHistory() async throws {
        // Given
        let fixture = try MonitorFixture()
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/07/31/preexisting.jsonl",
            contents: userMetadata + taskStarted(turnID: "old") + taskCompleted(turnID: "old")
        )
        var publications: [[DesktopCodexTaskLifecycleEvent]] = []
        let monitor = fixture.makeMonitor { publications.append($0) }

        // When
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        XCTAssertTrue(publications.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: transcript.path))
    }

    @MainActor
    func testMonitor_whenAnEligibleTranscriptPredatesStart_publishesItsFirstNewTaskLifecycle() async throws {
        // Given
        let fixture = try MonitorFixture()
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/preexisting-eligible.jsonl",
            contents: userMetadata + taskStarted(turnID: "historical") + taskCompleted(turnID: "historical")
        )
        var events: [DesktopCodexTaskLifecycleEvent] = []
        var coordinator = CodexActivityCoordinator()
        var activities: [CodexActivity] = []
        let monitor = fixture.makeMonitor {
            events.append(contentsOf: $0)
            activities.append(coordinator.consume($0))
        }
        monitor.start()
        await monitor.waitUntilIdleForTesting()

        // When
        try fixture.append(taskStarted(turnID: "new"), to: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()
        try fixture.append(taskCompleted(turnID: "new"), to: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        let taskID = DesktopCodexTaskID(transcriptID: "2026/08/01/preexisting-eligible.jsonl", turnID: "new")
        XCTAssertEqual(events, [.started(taskID), .completed(taskID)])
        XCTAssertEqual(activities, [.running, .completed])
    }

    @MainActor
    func testMonitor_whenTaskIsAlreadyRunningAtStartup_restoresStartAndThenPublishesCompletion() async throws {
        // Given
        let fixture = try MonitorFixture()
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/in-flight.jsonl",
            contents: userMetadata + taskStarted(turnID: "in-flight")
        )
        var events: [DesktopCodexTaskLifecycleEvent] = []
        var coordinator = CodexActivityCoordinator()
        _ = coordinator.updateAppServerActivity(.running)
        let monitor = fixture.makeMonitor {
            events.append(contentsOf: $0)
            _ = coordinator.consume($0)
        }

        // When
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        try fixture.append(taskCompleted(turnID: "in-flight"), to: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        let taskID = DesktopCodexTaskID(transcriptID: "2026/08/01/in-flight.jsonl", turnID: "in-flight")
        XCTAssertEqual(events, [.started(taskID), .completed(taskID)])
        XCTAssertEqual(coordinator.activity, .completed)
    }

    @MainActor
    func testMonitor_whenTranscriptAppearsAfterStart_readsHeaderAndTaskStartFromByteZero() async throws {
        // Given
        let fixture = try MonitorFixture()
        var publications: [[DesktopCodexTaskLifecycleEvent]] = []
        let monitor = fixture.makeMonitor { publications.append($0) }
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        _ = try fixture.writeTranscript(
            relativePath: "2026/07/31/new.jsonl",
            contents: userMetadata + taskStarted(turnID: "turn-1")
        )

        // When
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        XCTAssertEqual(publications.flatMap { $0 }, [
            .started(DesktopCodexTaskID(transcriptID: "2026/07/31/new.jsonl", turnID: "turn-1"))
        ])
    }

    @MainActor
    func testMonitor_whenARecordIsSplitAcrossAppends_buffersUntilTheNewlineArrives() async throws {
        // Given
        let fixture = try MonitorFixture()
        var events: [DesktopCodexTaskLifecycleEvent] = []
        let monitor = fixture.makeMonitor { events.append(contentsOf: $0) }
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        let partial = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"split\""
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/split.jsonl",
            contents: userMetadata + partial
        )
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // When
        try fixture.append("}}\n", to: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        XCTAssertEqual(events, [
            .started(DesktopCodexTaskID(transcriptID: "2026/08/01/split.jsonl", turnID: "split"))
        ])
    }

    @MainActor
    func testMonitor_whenMultipleFilesAppear_recursesDeterministicallyAndFiltersSubagents() async throws {
        // Given
        let fixture = try MonitorFixture()
        var events: [DesktopCodexTaskLifecycleEvent] = []
        let monitor = fixture.makeMonitor { events.append(contentsOf: $0) }
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        _ = try fixture.writeTranscript(
            relativePath: "2026/08/01/a.jsonl",
            contents: userMetadata + taskStarted(turnID: "a")
        )
        _ = try fixture.writeTranscript(
            relativePath: "2026/08/02/nested/b.jsonl",
            contents: userMetadata + taskStarted(turnID: "b")
        )
        _ = try fixture.writeTranscript(
            relativePath: "2026/08/03/subagent.jsonl",
            contents: desktopMetadata(threadSource: "subagent") + taskStarted(turnID: "ignored")
        )

        // When
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        XCTAssertEqual(events, [
            .started(DesktopCodexTaskID(transcriptID: "2026/08/01/a.jsonl", turnID: "a")),
            .started(DesktopCodexTaskID(transcriptID: "2026/08/02/nested/b.jsonl", turnID: "b"))
        ])
    }

    @MainActor
    func testMonitor_whenTrackedFileIsTruncatedOrReplaced_resetsOffsetAndParser() async throws {
        // Given
        let fixture = try MonitorFixture()
        var events: [DesktopCodexTaskLifecycleEvent] = []
        let monitor = fixture.makeMonitor { events.append(contentsOf: $0) }
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/rotating.jsonl",
            contents: userMetadata + taskStarted(turnID: "first")
        )
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // When
        try fixture.overwrite("", at: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()
        try fixture.append(userMetadata + taskStarted(turnID: "after-truncate"), to: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()
        try FileManager.default.removeItem(at: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()
        _ = try fixture.writeTranscript(
            relativePath: "2026/08/01/rotating.jsonl",
            contents: userMetadata + taskStarted(turnID: "after-replace")
        )
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        XCTAssertEqual(events, [
            .started(DesktopCodexTaskID(transcriptID: "2026/08/01/rotating.jsonl", turnID: "first")),
            .completed(DesktopCodexTaskID(transcriptID: "2026/08/01/rotating.jsonl", turnID: "first")),
            .started(DesktopCodexTaskID(transcriptID: "2026/08/01/rotating.jsonl", turnID: "after-truncate")),
            .completed(DesktopCodexTaskID(transcriptID: "2026/08/01/rotating.jsonl", turnID: "after-truncate")),
            .started(DesktopCodexTaskID(transcriptID: "2026/08/01/rotating.jsonl", turnID: "after-replace"))
        ])
    }

    @MainActor
    func testMonitor_whenDeletedTranscriptHasMultipleActiveTasks_terminatesEachOnceInStableOrder() async throws {
        // Given
        let fixture = try MonitorFixture()
        var events: [DesktopCodexTaskLifecycleEvent] = []
        let monitor = fixture.makeMonitor { events.append(contentsOf: $0) }
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/multiple-active.jsonl",
            contents: userMetadata + taskStarted(turnID: "z-last") + taskStarted(turnID: "a-first")
        )
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // When
        try FileManager.default.removeItem(at: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        let first = DesktopCodexTaskID(transcriptID: "2026/08/01/multiple-active.jsonl", turnID: "a-first")
        let last = DesktopCodexTaskID(transcriptID: "2026/08/01/multiple-active.jsonl", turnID: "z-last")
        XCTAssertEqual(events, [.started(last), .started(first), .completed(first), .completed(last)])
    }

    @MainActor
    func testMonitor_whenStopped_cancelsScheduleAndPublishesNothingFurther() async throws {
        // Given
        let fixture = try MonitorFixture()
        var events: [DesktopCodexTaskLifecycleEvent] = []
        let monitor = fixture.makeMonitor { events.append(contentsOf: $0) }
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/stopped.jsonl",
            contents: userMetadata + taskStarted(turnID: "first")
        )
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // When
        monitor.stop()
        try fixture.append(taskCompleted(turnID: "first"), to: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        XCTAssertTrue(fixture.scheduler.isCancelled)
        XCTAssertEqual(events, [
            .started(DesktopCodexTaskID(transcriptID: "2026/08/01/stopped.jsonl", turnID: "first"))
        ])
    }

    @MainActor
    func testMonitor_whenRestarted_primesExistingMetadataWithoutRestoringHistoricalTaskState() async throws {
        // Given
        let fixture = try MonitorFixture()
        var events: [DesktopCodexTaskLifecycleEvent] = []
        let monitor = fixture.makeMonitor { events.append(contentsOf: $0) }
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/restart.jsonl",
            contents: userMetadata + taskStarted(turnID: "before-stop")
        )
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()
        monitor.stop()
        try fixture.append(taskCompleted(turnID: "before-stop"), to: transcript)

        // When
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        try fixture.append(taskStarted(turnID: "without-new-header"), to: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        XCTAssertEqual(events, [
            .started(DesktopCodexTaskID(transcriptID: "2026/08/01/restart.jsonl", turnID: "before-stop")),
            .started(DesktopCodexTaskID(transcriptID: "2026/08/01/restart.jsonl", turnID: "without-new-header"))
        ])
    }

    @MainActor
    func testMonitor_whenRootIsMissing_emitsANonfatalDiagnosticAndCanLaterDiscoverWork() async throws {
        // Given
        let fixture = try MonitorFixture()
        try FileManager.default.removeItem(at: fixture.root)
        var diagnostics: [CodexDesktopTaskMonitorDiagnostic] = []
        var events: [DesktopCodexTaskLifecycleEvent] = []
        let monitor = fixture.makeMonitor(
            onEvents: { events.append(contentsOf: $0) },
            onDiagnostic: { diagnostics.append($0) }
        )

        // When
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        _ = try fixture.writeTranscript(
            relativePath: "2026/08/01/recovered.jsonl",
            contents: userMetadata + taskStarted(turnID: "recovered")
        )
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        XCTAssertEqual(diagnostics, [.sessionsRootUnavailable(fixture.root.standardizedFileURL)])
        XCTAssertEqual(events, [
            .started(DesktopCodexTaskID(transcriptID: "2026/08/01/recovered.jsonl", turnID: "recovered"))
        ])
    }

    @MainActor
    func testMonitor_whenMalformedInputPrecedesValidInput_continuesTailingTheTranscript() async throws {
        // Given
        let fixture = try MonitorFixture()
        var events: [DesktopCodexTaskLifecycleEvent] = []
        let monitor = fixture.makeMonitor { events.append(contentsOf: $0) }
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/malformed.jsonl",
            contents: userMetadata + "not-json\n"
        )
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // When
        try fixture.append(taskStarted(turnID: "valid"), to: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        XCTAssertEqual(events, [
            .started(DesktopCodexTaskID(transcriptID: "2026/08/01/malformed.jsonl", turnID: "valid"))
        ])
    }

    @MainActor
    func testMonitor_whenOverlongRecordIsDiscarded_reportsDiagnosticAndContinuesTailing() async throws {
        // Given
        let fixture = try MonitorFixture()
        var diagnostics: [CodexDesktopTaskMonitorDiagnostic] = []
        var events: [DesktopCodexTaskLifecycleEvent] = []
        let monitor = fixture.makeMonitor(
            onEvents: { events.append(contentsOf: $0) },
            onDiagnostic: { diagnostics.append($0) }
        )
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/overlong.jsonl",
            contents: userMetadata + String(
                repeating: "x",
                count: DesktopCodexTaskParser.maximumIncompleteRecordByteCount + 1
            )
        )
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // When
        try fixture.append("\n" + taskStarted(turnID: "recovered"), to: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        XCTAssertEqual(diagnostics, [
            .overlongRecordDiscarded(
                transcript.standardizedFileURL,
                byteLimit: DesktopCodexTaskParser.maximumIncompleteRecordByteCount
            )
        ])
        XCTAssertEqual(events, [
            .started(DesktopCodexTaskID(transcriptID: "2026/08/01/overlong.jsonl", turnID: "recovered"))
        ])
    }

    @MainActor
    func testMonitor_whenTrackedTranscriptBecomesUnreadable_terminatesItsActiveTaskBeforeDiscardingState() async throws {
        // Given
        let fixture = try MonitorFixture()
        let transcript = fixture.root.appendingPathComponent("2026/08/01/unreadable.jsonl")
        var diagnostics: [CodexDesktopTaskMonitorDiagnostic] = []
        var events: [DesktopCodexTaskLifecycleEvent] = []
        let monitor = CodexDesktopTaskMonitor(
            sessionsRootURL: fixture.root,
            discoverTranscripts: { _ in [transcript] },
            schedule: fixture.scheduler.schedule,
            onEvents: { events.append(contentsOf: $0) },
            onDiagnostic: { diagnostics.append($0) }
        )
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        diagnostics.removeAll()
        _ = try fixture.writeTranscript(
            relativePath: "2026/08/01/unreadable.jsonl",
            contents: userMetadata + taskStarted(turnID: "active")
        )
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // When
        try FileManager.default.removeItem(at: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        let taskID = DesktopCodexTaskID(transcriptID: "2026/08/01/unreadable.jsonl", turnID: "active")
        XCTAssertEqual(events, [.started(taskID), .completed(taskID)])
        XCTAssertEqual(diagnostics, [.transcriptUnreadable(transcript.standardizedFileURL)])
    }

    @MainActor
    func testMonitorIntegration_whenNewTaskStartsThenCompletes_publishesForwardLifecycle() async throws {
        // Given
        let fixture = try MonitorFixture()
        var events: [DesktopCodexTaskLifecycleEvent] = []
        let monitor = fixture.makeMonitor { events.append(contentsOf: $0) }
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/integration.jsonl",
            contents: userMetadata + taskStarted(turnID: "manual-fixture")
        )
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // When
        try fixture.append(taskCompleted(turnID: "manual-fixture"), to: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        let taskID = DesktopCodexTaskID(transcriptID: "2026/08/01/integration.jsonl", turnID: "manual-fixture")
        XCTAssertEqual(events, [.started(taskID), .completed(taskID)])
    }

    @MainActor
    func testMonitor_whenAppendingToALargeTranscript_usesBoundedReadsWithoutRevisitingTheWholePrefix() async throws {
        // Given
        let fixture = try MonitorFixture()
        let reads = LockedTestValue([(offset: UInt64, count: Int)]())
        let monitor = CodexDesktopTaskMonitor(
            sessionsRootURL: fixture.root,
            schedule: fixture.scheduler.schedule,
            onEvents: { _ in },
            onRead: { offset, count in reads.update { $0.append((offset, count)) } }
        )
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        let padding = String(repeating: "{\"type\":\"ignored\"}\n", count: 8_000)
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/large.jsonl",
            contents: userMetadata + padding
        )
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()
        let prefixByteCount = UInt64(try Data(contentsOf: transcript).count)
        reads.update { $0.removeAll() }

        // When
        try fixture.append(taskStarted(turnID: "incremental"), to: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        let observedReads = reads.get()
        XCTAssertFalse(observedReads.isEmpty)
        XCTAssertTrue(observedReads.allSatisfy { $0.count <= CodexDesktopTaskMonitor.maximumReadByteCount })
        XCTAssertFalse(observedReads.contains { $0.offset == 0 })
        XCTAssertTrue(observedReads.contains { $0.offset == prefixByteCount })
    }

}

extension DesktopCodexTaskMonitorTests {
    var userMetadata: String {
        desktopMetadata(threadSource: "user")
    }

    func desktopMetadata(threadSource: String) -> String {
        "{\"type\":\"session_meta\",\"payload\":{\"originator\":\"Codex Desktop\",\"thread_source\":\"\(threadSource)\"}}\n"
    }

    func taskStarted(turnID: String) -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"\(turnID)\"}}\n"
    }

    func taskCompleted(turnID: String) -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"\(turnID)\"}}\n"
    }

    var unknownRecord: String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"item_started\",\"turn_id\":\"turn-1\"}}\n"
    }
}
