import Foundation
import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class ManualMonitorScheduler {
    private let cancellationState = ManualMonitorCancellationState()
    private var tick: (@MainActor @Sendable () -> Void)?

    var isCancelled: Bool { cancellationState.isCancelled }
    private(set) var scheduleCallCount = 0

    func schedule(
        _: URL,
        _ tick: @escaping @MainActor @Sendable () -> Void
    ) -> CodexDesktopTaskMonitorCancellation {
        scheduleCallCount += 1
        self.tick = tick
        cancellationState.reset()
        return CodexDesktopTaskMonitorCancellation { [cancellationState] in
            cancellationState.cancel()
        }
    }

    func fire() {
        if !isCancelled { tick?() }
    }
}

private final class ManualMonitorCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func reset() {
        lock.withLock { cancelled = false }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

final class LockedTestValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func update<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock { body(&value) }
    }

    func get() -> Value {
        lock.withLock { value }
    }
}

@MainActor
final class MonitorFixture {
    let root: URL
    let scheduler = ManualMonitorScheduler()
    private weak var monitor: CodexDesktopTaskMonitor?

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopCodexTaskMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func makeMonitor(
        onEvents: @escaping ([DesktopCodexTaskLifecycleEvent]) -> Void,
        onDiagnostic: @escaping (CodexDesktopTaskMonitorDiagnostic) -> Void = { _ in }
    ) -> CodexDesktopTaskMonitor {
        let monitor = CodexDesktopTaskMonitor(
            sessionsRootURL: root,
            schedule: scheduler.schedule,
            onEvents: onEvents,
            onDiagnostic: onDiagnostic
        )
        self.monitor = monitor
        return monitor
    }

    func waitForMonitorToBecomeIdle() async {
        await monitor?.waitUntilIdleForTesting()
    }

    @discardableResult
    func writeTranscript(relativePath: String, contents: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func append(_ contents: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(contents.utf8))
    }

    func overwrite(_ contents: String, at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(contents.utf8))
    }

    func inode(of url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap((attributes[.systemFileNumber] as? NSNumber)?.uint64Value)
    }
}
