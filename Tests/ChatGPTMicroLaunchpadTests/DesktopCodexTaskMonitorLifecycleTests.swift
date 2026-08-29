import XCTest
@testable import ChatGPTMicroLaunchpad

extension DesktopCodexTaskMonitorTests {
    @MainActor
    func testMonitor_whenUsingTheDefaultScheduleAndTheSessionsDirectoryIsQuiet_doesNotPollForScans() async throws {
        // Given
        let fixture = try MonitorFixture()
        let filesystemScan = expectation(description: "filesystem-triggered scan")
        let unexpectedScan = expectation(description: "unexpected scheduled scan")
        unexpectedScan.isInverted = true
        let scanState = LockedTestValue((calls: 0, expectFilesystemScan: false, detectUnexpectedScan: false))
        let monitor = CodexDesktopTaskMonitor(
            sessionsRootURL: fixture.root,
            discoverTranscripts: { _ in
                let state = scanState.update {
                    $0.calls += 1
                    return $0
                }
                if state.expectFilesystemScan { filesystemScan.fulfill() }
                if state.detectUnexpectedScan { unexpectedScan.fulfill() }
                return []
            },
            onEvents: { _ in }
        )
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        scanState.update { $0.expectFilesystemScan = true }
        _ = try fixture.writeTranscript(relativePath: "sentinel.jsonl", contents: "")
        await fulfillment(of: [filesystemScan], timeout: 2)
        await monitor.waitUntilIdleForTesting()
        scanState.update {
            $0.expectFilesystemScan = false
            $0.detectUnexpectedScan = true
        }

        // When
        await fulfillment(of: [unexpectedScan], timeout: 0.7)
        monitor.stop()

        // Then
        XCTAssertGreaterThanOrEqual(scanState.get().calls, 2)
    }

    @MainActor
    func testMonitor_whenTicksArriveDuringAScan_neverRunsScansConcurrently() async throws {
        // Given
        let fixture = try MonitorFixture()
        let firstScanEntered = expectation(description: "first background scan entered discovery")
        let releaseFirstScan = DispatchSemaphore(value: 0)
        let state = LockedTestValue((calls: 0, active: 0, maximumActive: 0))
        let monitor = CodexDesktopTaskMonitor(
            sessionsRootURL: fixture.root,
            discoverTranscripts: { _ in
                let call = state.update {
                    $0.calls += 1
                    $0.active += 1
                    $0.maximumActive = max($0.maximumActive, $0.active)
                    return $0.calls
                }
                if call == 1 {
                    firstScanEntered.fulfill()
                    releaseFirstScan.wait()
                }
                state.update { $0.active -= 1 }
                return []
            },
            schedule: fixture.scheduler.schedule,
            onEvents: { _ in }
        )
        monitor.start()
        await fulfillment(of: [firstScanEntered], timeout: 1)

        // When
        fixture.scheduler.fire()
        fixture.scheduler.fire()
        fixture.scheduler.fire()
        releaseFirstScan.signal()
        await monitor.waitUntilIdleForTesting()

        // Then
        let result = state.get()
        XCTAssertEqual(result.calls, 4)
        XCTAssertEqual(result.maximumActive, 1)
    }

    @MainActor
    func testMonitor_whenScanningAndPublishing_usesBackgroundWorkAndMainActorCallbacks() async throws {
        // Given
        let fixture = try MonitorFixture()
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/context.jsonl",
            contents: userMetadata + taskStarted(turnID: "context")
        )
        let discoveryState = LockedTestValue((callCount: 0, wasMainThread: Optional<Bool>.none))
        var callbackWasMainThread: Bool?
        let monitor = CodexDesktopTaskMonitor(
            sessionsRootURL: fixture.root,
            discoverTranscripts: { _ in
                let callCount = discoveryState.update {
                    $0.callCount += 1
                    $0.wasMainThread = Thread.isMainThread
                    return $0.callCount
                }
                return callCount == 1 ? [] : [transcript]
            },
            schedule: fixture.scheduler.schedule,
            onEvents: { _ in callbackWasMainThread = Thread.isMainThread }
        )
        monitor.start()
        await monitor.waitUntilIdleForTesting()

        // When
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        XCTAssertEqual(discoveryState.get().wasMainThread, false)
        XCTAssertEqual(callbackWasMainThread, true)
    }

    @MainActor
    func testMonitor_whenSameInodeIsTruncatedAndRewrittenPastOldOffset_resetsAndReadsReplacementFromZero() async throws {
        // Given
        let fixture = try MonitorFixture()
        var events: [DesktopCodexTaskLifecycleEvent] = []
        let monitor = fixture.makeMonitor { events.append(contentsOf: $0) }
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        let transcript = try fixture.writeTranscript(
            relativePath: "2026/08/01/same-inode.jsonl",
            contents: userMetadata + taskStarted(turnID: "old")
        )
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()
        let oldInode = try fixture.inode(of: transcript)
        let oldByteCount = try Data(contentsOf: transcript).count
        let replacement = userMetadata + taskStarted(turnID: "replacement-is-longer-than-old")
        XCTAssertGreaterThanOrEqual(replacement.utf8.count, oldByteCount)

        // When
        try fixture.overwrite(replacement, at: transcript)
        let replacementInode = try fixture.inode(of: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()
        try fixture.append(taskCompleted(turnID: "replacement-is-longer-than-old"), to: transcript)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        XCTAssertEqual(replacementInode, oldInode)
        XCTAssertEqual(events, [
            .started(DesktopCodexTaskID(transcriptID: "2026/08/01/same-inode.jsonl", turnID: "old")),
            .completed(DesktopCodexTaskID(transcriptID: "2026/08/01/same-inode.jsonl", turnID: "old")),
            .started(DesktopCodexTaskID(transcriptID: "2026/08/01/same-inode.jsonl", turnID: "replacement-is-longer-than-old")),
            .completed(DesktopCodexTaskID(transcriptID: "2026/08/01/same-inode.jsonl", turnID: "replacement-is-longer-than-old"))
        ])
    }

    @MainActor
    func testMonitor_whenDeinitialized_cancelsTheScheduledScan() async throws {
        // Given
        let fixture = try MonitorFixture()
        var monitor: CodexDesktopTaskMonitor? = fixture.makeMonitor { _ in }
        monitor?.start()
        XCTAssertFalse(fixture.scheduler.isCancelled)

        // When
        monitor = nil

        // Then
        XCTAssertTrue(fixture.scheduler.isCancelled)
    }

    @MainActor
    func testMonitor_whenInjectedDiscoveryCannotReadRoot_reportsDiagnosticWithoutSchedulingFailure() async throws {
        // Given
        let fixture = try MonitorFixture()
        var diagnostics: [CodexDesktopTaskMonitorDiagnostic] = []
        var diagnosticWasMainThread: Bool?
        let monitor = CodexDesktopTaskMonitor(
            sessionsRootURL: fixture.root,
            discoverTranscripts: { _ in throw CocoaError(.fileReadNoPermission) },
            schedule: fixture.scheduler.schedule,
            onEvents: { _ in },
            onDiagnostic: {
                diagnostics.append($0)
                diagnosticWasMainThread = Thread.isMainThread
            }
        )

        // When
        monitor.start()
        await monitor.waitUntilIdleForTesting()

        // Then
        XCTAssertEqual(diagnostics, [.sessionsRootUnavailable(fixture.root.standardizedFileURL)])
        XCTAssertEqual(diagnosticWasMainThread, true)
        XCTAssertFalse(fixture.scheduler.isCancelled)
    }

    @MainActor
    func testMonitor_whenFileIsCreatedInsideInitialDiscovery_restoresItsActiveTask() async throws {
        // Given
        let fixture = try MonitorFixture()
        let admitted = fixture.root.appendingPathComponent("2026/08/01/admitted.jsonl")
        let later = fixture.root.appendingPathComponent("2026/08/01/later.jsonl")
        let admittedContents = Data((userMetadata + taskStarted(turnID: "admitted-history")).utf8)
        var events: [DesktopCodexTaskLifecycleEvent] = []
        let monitor = CodexDesktopTaskMonitor(
            sessionsRootURL: fixture.root,
            discoverTranscripts: { _ in
                if !FileManager.default.fileExists(atPath: admitted.path) {
                    try FileManager.default.createDirectory(at: admitted.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try admittedContents.write(to: admitted)
                }
                return [admitted, later].filter { FileManager.default.fileExists(atPath: $0.path) }
            },
            schedule: fixture.scheduler.schedule,
            onEvents: { events.append(contentsOf: $0) }
        )

        // When
        monitor.start()
        await monitor.waitUntilIdleForTesting()
        try Data((userMetadata + taskStarted(turnID: "later-live")).utf8).write(to: later)
        fixture.scheduler.fire()
        await monitor.waitUntilIdleForTesting()

        // Then
        XCTAssertEqual(events, [
            .started(DesktopCodexTaskID(transcriptID: "2026/08/01/admitted.jsonl", turnID: "admitted-history")),
            .started(DesktopCodexTaskID(transcriptID: "2026/08/01/later.jsonl", turnID: "later-live"))
        ])
    }
}
