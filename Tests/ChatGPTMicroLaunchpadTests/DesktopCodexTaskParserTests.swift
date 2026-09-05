import XCTest
@testable import ChatGPTMicroLaunchpad

final class DesktopCodexTaskParserTests: XCTestCase {
    func testParser_whenRolloutFilesShareSessionID_usesSessionIDToDeduplicateTaskIdentity() {
        var parser = DesktopCodexTaskParser(transcriptID: "rollout-copy.jsonl")
        let metadata = "{\"type\":\"session_meta\",\"payload\":{\"session_id\":\"root-session\",\"id\":\"rollout-copy\",\"originator\":\"Codex Desktop\",\"thread_source\":\"user\"}}\n"

        let events = parser.consume(Data((metadata + taskStarted(turnID: "turn-1")).utf8))

        XCTAssertEqual(
            events,
            [.started(DesktopCodexTaskID(transcriptID: "root-session", turnID: "turn-1"))],
            "Rollout copies from one Codex session must count as one active task."
        )
    }

    func testParser_whenEligibleTranscriptStartsAndCompletesATask_publishesLifecycleAndActivity() {
        var parser = DesktopCodexTaskParser(transcriptID: "2026/07/31/user.jsonl")
        var coordinator = CodexActivityCoordinator()

        let started = parser.consume(Data((userMetadata + taskStarted(turnID: "turn-1")).utf8))
        let running = coordinator.consume(started)
        let completed = parser.consume(Data(taskCompleted(turnID: "turn-1").utf8))
        let terminal = coordinator.consume(completed)

        XCTAssertEqual(started, [.started(DesktopCodexTaskID(transcriptID: "2026/07/31/user.jsonl", turnID: "turn-1"))])
        XCTAssertEqual(running, .running)
        XCTAssertEqual(completed, [.completed(DesktopCodexTaskID(transcriptID: "2026/07/31/user.jsonl", turnID: "turn-1"))])
        XCTAssertEqual(terminal, .completed)
    }

    func testParser_whenAnActiveTurnIsAborted_endsTheTaskLifecycle() {
        var parser = DesktopCodexTaskParser(transcriptID: "aborted.jsonl")
        let taskID = DesktopCodexTaskID(transcriptID: "aborted.jsonl", turnID: "turn-1")

        let events = parser.consume(Data((
            userMetadata
                + taskStarted(turnID: "turn-1")
                + turnAborted(turnID: "turn-1")
        ).utf8))

        XCTAssertEqual(events, [.started(taskID), .completed(taskID)])
        XCTAssertTrue(parser.activeTaskIDs.isEmpty)
    }

    func testParser_whenMetadataIsSplitAcrossChunks_buffersItAndReadsMultipleRecordsInTheNextChunk() {
        var parser = DesktopCodexTaskParser(transcriptID: "split.jsonl")
        let metadata = userMetadata
        let splitIndex = metadata.index(metadata.startIndex, offsetBy: 29)

        let beforeNewline = parser.consume(Data(metadata[..<splitIndex].utf8))
        let afterNewline = parser.consume(Data((metadata[splitIndex...] + taskStarted(turnID: "turn-1") + taskStarted(turnID: "turn-2")).utf8))

        XCTAssertTrue(beforeNewline.isEmpty)
        XCTAssertEqual(afterNewline, [
            .started(DesktopCodexTaskID(transcriptID: "split.jsonl", turnID: "turn-1")),
            .started(DesktopCodexTaskID(transcriptID: "split.jsonl", turnID: "turn-2"))
        ])
    }

    func testParser_whenInitialMetadataIsPrimed_ignoresHistoricalTasksAndAcceptsTheNextTask() {
        // Given
        var parser = DesktopCodexTaskParser(transcriptID: "preexisting.jsonl")
        parser.primeInitialMetadata(from: Data((userMetadata + taskStarted(turnID: "historical")).utf8))

        // When
        let updates = parser.consume(Data(taskStarted(turnID: "new").utf8))

        // Then
        let taskID = DesktopCodexTaskID(transcriptID: "preexisting.jsonl", turnID: "new")
        XCTAssertEqual(updates, [.started(taskID)])
        XCTAssertEqual(parser.activeTaskIDs, [taskID])
    }

    func testParser_whenTranscriptIsASubagent_acceptsCodexDesktopTaskEvents() {
        var parser = DesktopCodexTaskParser(transcriptID: "subagent.jsonl")
        let transcript = desktopMetadata(threadSource: "subagent") + userMetadata + taskStarted(turnID: "turn-1") + taskCompleted(turnID: "turn-1")

        let updates = parser.consume(Data(transcript.utf8))

        XCTAssertEqual(updates, [
            .started(DesktopCodexTaskID(transcriptID: "subagent.jsonl", turnID: "turn-1")),
            .completed(DesktopCodexTaskID(transcriptID: "subagent.jsonl", turnID: "turn-1"))
        ])
        XCTAssertTrue(parser.activeTaskIDs.isEmpty)
    }

    func testParser_whenTurnContextPrecedesTaskStarted_recognizesWorkImmediatelyAndCompletesIt() {
        var parser = DesktopCodexTaskParser(transcriptID: "early-work.jsonl")
        let transcript = userMetadata
            + turnContext(turnID: "turn-1")
            + progressEvent(turnID: "turn-1", type: "item_started")
            + taskCompleted(turnID: "turn-1")

        let updates = parser.consume(Data(transcript.utf8))

        XCTAssertEqual(updates, [
            .started(DesktopCodexTaskID(transcriptID: "early-work.jsonl", turnID: "turn-1")),
            .completed(DesktopCodexTaskID(transcriptID: "early-work.jsonl", turnID: "turn-1"))
        ])
        XCTAssertTrue(parser.activeTaskIDs.isEmpty)
    }

    func testParser_whenTranscriptIsAGuardianReview_ignoresTaskEvents() {
        var parser = DesktopCodexTaskParser(transcriptID: "guardian-review.jsonl")
        let transcript = desktopMetadata(threadSource: "guardian_review")
            + taskStarted(turnID: "turn-1")
            + taskCompleted(turnID: "turn-1")

        let updates = parser.consume(Data(transcript.utf8))

        XCTAssertTrue(updates.isEmpty)
        XCTAssertTrue(parser.activeTaskIDs.isEmpty)
    }

    func testParser_whenTaskArrivesBeforeMetadata_ignoresItWithoutReplayingAfterMetadata() {
        var parser = DesktopCodexTaskParser(transcriptID: "out-of-order.jsonl")

        let beforeMetadata = parser.consume(Data(taskStarted(turnID: "turn-1").utf8))
        let afterMetadata = parser.consume(Data((userMetadata + taskStarted(turnID: "turn-1")).utf8))

        XCTAssertTrue(beforeMetadata.isEmpty)
        XCTAssertEqual(afterMetadata, [.started(DesktopCodexTaskID(transcriptID: "out-of-order.jsonl", turnID: "turn-1"))])
    }

    func testParser_whenMalformedUnknownOrPartialRecordsArrive_ignoresInvalidRecordsAndBuffersThePartialRecord() {
        var parser = DesktopCodexTaskParser(transcriptID: "malformed.jsonl")
        let partialStart = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-1\""

        let firstUpdates = parser.consume(Data((userMetadata + "not json\n" + unknownRecord + partialStart).utf8))
        let secondUpdates = parser.consume(Data("}}\n".utf8))

        XCTAssertTrue(firstUpdates.isEmpty)
        XCTAssertEqual(secondUpdates, [.started(DesktopCodexTaskID(transcriptID: "malformed.jsonl", turnID: "turn-1"))])
    }

    func testParser_whenANewlineFreeRecordExceedsTheLimit_discardsItAndRecoversAtTheNextRecord() {
        // Given
        var parser = DesktopCodexTaskParser(transcriptID: "overlong.jsonl")
        _ = parser.consume(Data(userMetadata.utf8))
        let overlongRecord = String(
            repeating: "x",
            count: DesktopCodexTaskParser.maximumIncompleteRecordByteCount + 1
        )

        // When
        let discarded = parser.consume(Data(overlongRecord.utf8))
        let recovered = parser.consume(Data(("\n" + taskStarted(turnID: "recovered")).utf8))

        // Then
        XCTAssertTrue(discarded.isEmpty)
        XCTAssertEqual(parser.discardedOverlongRecordCount, 1)
        XCTAssertEqual(recovered, [
            .started(DesktopCodexTaskID(transcriptID: "overlong.jsonl", turnID: "recovered"))
        ])
    }

    func testParser_whenEventsAreDuplicateMissingOrUnmatched_emitsOnlyRealStateChanges() {
        var parser = DesktopCodexTaskParser(transcriptID: "idempotent.jsonl")
        _ = parser.consume(Data(userMetadata.utf8))

        let started = parser.consume(Data((taskStarted(turnID: "turn-1") + taskStarted(turnID: "turn-1") + taskStarted(turnID: " ")).utf8))
        let completed = parser.consume(Data((taskCompleted(turnID: "missing") + taskCompleted(turnID: "turn-1") + taskCompleted(turnID: "turn-1")).utf8))

        XCTAssertEqual(started, [.started(DesktopCodexTaskID(transcriptID: "idempotent.jsonl", turnID: "turn-1"))])
        XCTAssertEqual(completed, [
            .completed(DesktopCodexTaskID(transcriptID: "idempotent.jsonl", turnID: "turn-1"))
        ])
        XCTAssertTrue(parser.activeTaskIDs.isEmpty)
    }

    func testParser_whenTwoTurnsShareATranscript_tracksTheirLifecyclesIndependently() {
        var parser = DesktopCodexTaskParser(transcriptID: "two-turns.jsonl")
        _ = parser.consume(Data(userMetadata.utf8))

        _ = parser.consume(Data((taskStarted(turnID: "turn-1") + taskStarted(turnID: "turn-2")).utf8))
        let firstCompletion = parser.consume(Data(taskCompleted(turnID: "turn-1").utf8))

        XCTAssertEqual(parser.activeTaskIDs, [DesktopCodexTaskID(transcriptID: "two-turns.jsonl", turnID: "turn-2")])
        XCTAssertEqual(firstCompletion, [.completed(DesktopCodexTaskID(transcriptID: "two-turns.jsonl", turnID: "turn-1"))])
    }

    func testCoordinator_whenTheSameTurnIDComesFromTwoTranscripts_treatsThemAsIndependentWork() {
        var coordinator = CodexActivityCoordinator()
        let first = DesktopCodexTaskID(transcriptID: "first.jsonl", turnID: "turn-1")
        let second = DesktopCodexTaskID(transcriptID: "second.jsonl", turnID: "turn-1")

        _ = coordinator.consume([.started(first), .started(second)])
        let afterFirstCompletion = coordinator.consume([.completed(first)])
        let afterSecondCompletion = coordinator.consume([.completed(second)])

        XCTAssertEqual(afterFirstCompletion, .running)
        XCTAssertEqual(afterSecondCompletion, .completed)
    }

    @MainActor
    func testActivityController_countsOneSessionOnceAcrossMultipleActiveTurns() {
        let firstTurn = DesktopCodexTaskID(transcriptID: "root-session", turnID: "turn-1")
        let secondTurn = DesktopCodexTaskID(transcriptID: "root-session", turnID: "turn-2")

        XCTAssertEqual(
            CodexActivityController.sessionCount(for: [firstTurn, secondTurn]),
            1,
            "Multiple active turns from one root session must be shown as one session."
        )
    }

    func testCoordinator_whenDesktopTaskCompletesAndAppServerRemainsStaleRunning_reportsDesktopCompletion() {
        var coordinator = CodexActivityCoordinator()
        let desktopID = DesktopCodexTaskID(transcriptID: "desktop.jsonl", turnID: "turn-1")

        _ = coordinator.updateAppServerActivity(.running)
        _ = coordinator.consume([.started(desktopID)])
        let desktopCompleted = coordinator.consume([.completed(desktopID)])

        XCTAssertEqual(desktopCompleted, .completed)
    }

    func testCoordinator_whenStaleAppServerRunningRepeatsAfterDesktopCompletion_remainsCompleted() {
        var coordinator = CodexActivityCoordinator()
        let desktopID = DesktopCodexTaskID(transcriptID: "desktop.jsonl", turnID: "turn-1")

        _ = coordinator.updateAppServerActivity(.running)
        _ = coordinator.consume([.started(desktopID)])
        _ = coordinator.consume([.completed(desktopID)])

        let repeatedStaleRunning = coordinator.updateAppServerActivity(.running)

        XCTAssertEqual(
            repeatedStaleRunning,
            .completed,
            "Repeating the old app-server running state must not resurrect a completed desktop task."
        )
    }

    func testCoordinator_whenDesktopAndAppServerOverlap_keepsRunningUntilAllWorkEnds() {
        var coordinator = CodexActivityCoordinator()
        let desktopID = DesktopCodexTaskID(transcriptID: "desktop.jsonl", turnID: "turn-1")

        _ = coordinator.updateAppServerActivity(.running)
        let desktopStarted = coordinator.consume([.started(desktopID)])
        let appServerCompleted = coordinator.updateAppServerActivity(.completed)
        let desktopCompleted = coordinator.consume([.completed(desktopID)])

        XCTAssertEqual(desktopStarted, .running)
        XCTAssertEqual(appServerCompleted, .running)
        XCTAssertEqual(desktopCompleted, .completed)
    }

    func testCoordinator_whenAppServerWaitsOrFailsDuringDesktopWork_defersThoseExistingStatesUntilDesktopCompletes() {
        var coordinator = CodexActivityCoordinator()
        let desktopID = DesktopCodexTaskID(transcriptID: "desktop.jsonl", turnID: "turn-1")

        _ = coordinator.consume([.started(desktopID)])
        let whileWaiting = coordinator.updateAppServerActivity(.waitingForApproval)
        let afterDesktopCompletes = coordinator.consume([.completed(desktopID)])
        _ = coordinator.consume([.started(desktopID)])
        let whileFailed = coordinator.updateAppServerActivity(.failed)
        let afterFailureAndCompletion = coordinator.consume([.completed(desktopID)])

        XCTAssertEqual(whileWaiting, .running)
        XCTAssertEqual(afterDesktopCompletes, .waitingForApproval)
        XCTAssertEqual(whileFailed, .running)
        XCTAssertEqual(afterFailureAndCompletion, .failed)
    }
}

private extension DesktopCodexTaskParserTests {
    var userMetadata: String {
        desktopMetadata(threadSource: "user")
    }

    func desktopMetadata(threadSource: String) -> String {
        "{\"type\":\"session_meta\",\"payload\":{\"originator\":\"Codex Desktop\",\"thread_source\":\"\(threadSource)\"}}\n"
    }

    func taskStarted(turnID: String) -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"\(turnID)\"}}\n"
    }

    func turnContext(turnID: String) -> String {
        "{\"type\":\"turn_context\",\"payload\":{\"turn_id\":\"\(turnID)\"}}\n"
    }

    func progressEvent(turnID: String, type: String) -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\",\"turn_id\":\"\(turnID)\"}}\n"
    }

    func taskCompleted(turnID: String) -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"\(turnID)\"}}\n"
    }

    func turnAborted(turnID: String) -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"turn_aborted\",\"turn_id\":\"" + turnID + "\"}}\n"
    }

    var unknownRecord: String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"unknown_event\",\"turn_id\":\"turn-1\"}}\n"
    }
}
