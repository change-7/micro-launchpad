import Foundation

enum CodexActivity: String, CaseIterable, Codable, Identifiable {
    case idle
    case connecting
    case running
    case waitingForApproval
    case completed
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle: "대기"
        case .connecting: "연결 중"
        case .running: "작업 중"
        case .waitingForApproval: "승인 대기"
        case .completed: "완료"
        case .failed: "오류"
        }
    }
}

enum CodexEventReducer {
    static func activity(for method: String) -> CodexActivity? {
        let normalized = method.lowercased()
        if normalized == "turn/completed" { return .completed }
        if normalized == "turn/failed" || normalized == "turn/cancelled" { return .failed }
        if normalized.contains("approval") || normalized.contains("requestuserinput") { return .waitingForApproval }
        if normalized.contains("turn/started") || normalized.contains("turn/start") || normalized.contains("item/started") {
            return .running
        }
        return nil
    }
}

struct DesktopCodexTaskID: Hashable, Sendable {
    let transcriptID: String
    let turnID: String
}

enum DesktopCodexTaskLifecycleEvent: Equatable, Sendable {
    case started(DesktopCodexTaskID)
    case completed(DesktopCodexTaskID)
}

struct DesktopCodexTaskParser {
    static let maximumIncompleteRecordByteCount = 256 * 1_024

    let transcriptID: String
    private var bufferedData = Data()
    private var isDiscardingOverlongRecord = false
    private var transcriptIsEligible: Bool?
    private(set) var activeTaskIDs: Set<DesktopCodexTaskID> = []
    private var completedTaskIDs: Set<DesktopCodexTaskID> = []
    private(set) var discardedOverlongRecordCount = 0

    init(transcriptID: String) {
        self.transcriptID = transcriptID
    }

    mutating func primeInitialMetadata(from data: Data) {
        guard transcriptIsEligible == nil else { return }

        var remainingData = data[...]
        while let newlineIndex = remainingData.firstIndex(of: 10) {
            let line = Data(remainingData[..<newlineIndex])
            remainingData = remainingData[remainingData.index(after: newlineIndex)...]
            guard line.count <= Self.maximumIncompleteRecordByteCount,
                  !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line),
                  let record = object as? [String: Any],
                  record["type"] as? String == "session_meta" else {
                continue
            }

            consumeMetadata(record)
            if transcriptIsEligible != nil { return }
        }
    }

    mutating func consume(_ data: Data) -> [DesktopCodexTaskLifecycleEvent] {
        bufferedData.append(data)
        var events: [DesktopCodexTaskLifecycleEvent] = []

        while true {
            if isDiscardingOverlongRecord {
                guard let newlineIndex = bufferedData.firstIndex(of: 10) else {
                    bufferedData.removeAll(keepingCapacity: true)
                    break
                }
                bufferedData.removeSubrange(...newlineIndex)
                isDiscardingOverlongRecord = false
                continue
            }

            guard let newlineIndex = bufferedData.firstIndex(of: 10) else {
                if bufferedData.count > Self.maximumIncompleteRecordByteCount {
                    bufferedData.removeAll(keepingCapacity: true)
                    isDiscardingOverlongRecord = true
                    discardedOverlongRecordCount += 1
                }
                break
            }

            let line = Data(bufferedData[..<newlineIndex])
            bufferedData.removeSubrange(...newlineIndex)
            guard line.count <= Self.maximumIncompleteRecordByteCount else {
                discardedOverlongRecordCount += 1
                continue
            }
            if let event = consumeRecord(line) {
                events.append(event)
            }
        }

        return events
    }

    private mutating func consumeRecord(_ line: Data) -> DesktopCodexTaskLifecycleEvent? {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line),
              let record = object as? [String: Any],
              let recordType = record["type"] as? String else {
            return nil
        }

        if recordType == "session_meta" {
            consumeMetadata(record)
            return nil
        }

        guard transcriptIsEligible == true,
              recordType == "event_msg",
              let payload = record["payload"] as? [String: Any],
              let eventType = payload["type"] as? String,
              let rawTurnID = payload["turn_id"] as? String else {
            return nil
        }

        let turnID = rawTurnID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !turnID.isEmpty else { return nil }

        let taskID = DesktopCodexTaskID(transcriptID: transcriptID, turnID: turnID)
        switch eventType {
        case "task_started":
            guard activeTaskIDs.insert(taskID).inserted else { return nil }
            completedTaskIDs.remove(taskID)
            return .started(taskID)
        case "task_complete":
            guard completedTaskIDs.insert(taskID).inserted else { return nil }
            activeTaskIDs.remove(taskID)
            return .completed(taskID)
        default:
            return nil
        }
    }

    private mutating func consumeMetadata(_ record: [String: Any]) {
        guard transcriptIsEligible == nil,
              let payload = record["payload"] as? [String: Any],
              let originator = payload["originator"] as? String,
              let threadSource = payload["thread_source"] as? String else {
            return
        }

        transcriptIsEligible = originator == "Codex Desktop" && threadSource == "user"
    }
}

struct CodexActivityCoordinator {
    private var appServerActivity: CodexActivity = .idle
    private var desktopActiveTaskIDs: Set<DesktopCodexTaskID> = []
    private var desktopTerminalActivity: CodexActivity?
    private(set) var activity: CodexActivity = .idle

    @discardableResult
    mutating func consume(_ events: [DesktopCodexTaskLifecycleEvent]) -> CodexActivity {
        for event in events {
            switch event {
            case let .started(taskID):
                if desktopActiveTaskIDs.insert(taskID).inserted {
                    desktopTerminalActivity = nil
                }
            case let .completed(taskID):
                desktopActiveTaskIDs.remove(taskID)
                if desktopActiveTaskIDs.isEmpty {
                    desktopTerminalActivity = .completed
                }
            }
        }
        activity = effectiveActivity
        return activity
    }

    @discardableResult
    mutating func updateAppServerActivity(_ activity: CodexActivity) -> CodexActivity {
        appServerActivity = activity
        self.activity = effectiveActivity
        return self.activity
    }

    private var effectiveActivity: CodexActivity {
        if !desktopActiveTaskIDs.isEmpty {
            return .running
        }

        // Desktop transcript events are the source of truth for Desktop tasks.
        // A running App Server status can be left behind after such a task finishes.
        if appServerActivity == .running {
            return desktopTerminalActivity ?? .running
        }

        switch appServerActivity {
        case .waitingForApproval, .failed, .completed:
            return appServerActivity
        case .idle, .connecting, .running:
            return desktopTerminalActivity ?? appServerActivity
        }
    }
}

enum CodexMotionDismissal: String, CaseIterable, Codable, Identifiable {
    case afterDuration
    case anyPad
    case assignedPad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .afterDuration: "시간 후 종료"
        case .anyPad: "아무 버튼까지"
        case .assignedPad: "지정 버튼까지"
        }
    }
}

enum CodexMotionDisplayScope: String, CaseIterable, Codable, Identifiable {
    case allPages
    case specificPage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allPages: "모든 페이지"
        case .specificPage: "특정 페이지"
        }
    }
}

enum LaunchpadLEDBubbleSize: String, CaseIterable, Codable, Identifiable {
    case small
    case regular
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "작게"
        case .regular: "보통"
        case .large: "크게"
        }
    }

    var points: Double {
        switch self {
        case .small: 124
        case .regular: 156
        case .large: 196
        }
    }
}

struct CodexMotionDisplaySettings: Codable, Hashable {
    var scope: CodexMotionDisplayScope = .allPages
    var pageID: UUID?
    var preservesPadLEDsDuringMotion = false
    var showsLaunchpadLEDBubble = true
    var launchpadLEDBubbleSize: LaunchpadLEDBubbleSize = .regular
    var launchpadLEDBubbleOriginX: Double?
    var launchpadLEDBubbleOriginY: Double?

    init(
        scope: CodexMotionDisplayScope = .allPages,
        pageID: UUID? = nil,
        preservesPadLEDsDuringMotion: Bool = false,
        showsLaunchpadLEDBubble: Bool = true,
        launchpadLEDBubbleSize: LaunchpadLEDBubbleSize = .regular,
        launchpadLEDBubbleOriginX: Double? = nil,
        launchpadLEDBubbleOriginY: Double? = nil
    ) {
        self.scope = scope
        self.pageID = pageID
        self.preservesPadLEDsDuringMotion = preservesPadLEDsDuringMotion
        self.showsLaunchpadLEDBubble = showsLaunchpadLEDBubble
        self.launchpadLEDBubbleSize = launchpadLEDBubbleSize
        self.launchpadLEDBubbleOriginX = launchpadLEDBubbleOriginX
        self.launchpadLEDBubbleOriginY = launchpadLEDBubbleOriginY
    }

    func allowsPresentation(on pageID: UUID) -> Bool {
        switch scope {
        case .allPages: true
        case .specificPage: self.pageID == pageID
        }
    }

    func shouldPreservePadLEDsDuringMotion(for activity: CodexActivity) -> Bool {
        preservesPadLEDsDuringMotion
    }

    static func restored(
        from persistedData: Data?,
        legacyPresentations: [String: CodexMotionPresentation]
    ) -> (settings: Self, didMigrateLegacyPreservation: Bool) {
        let settings = persistedData
            .flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
            ?? Self()
        let hasPersistedGlobalPreference = persistedData
            .flatMap { try? JSONDecoder().decode(PersistedPreference.self, from: $0) }
            .flatMap(\.preservesPadLEDsDuringMotion) != nil
        let shouldMigrateLegacyPreservation = !hasPersistedGlobalPreference
            && legacyPresentations.values.contains(where: \.preservesPadLEDsDuringMotion)

        guard shouldMigrateLegacyPreservation else {
            return (settings, false)
        }

        var migratedSettings = settings
        migratedSettings.preservesPadLEDsDuringMotion = true
        return (migratedSettings, true)
    }

    private enum CodingKeys: String, CodingKey {
        case scope
        case pageID
        case preservesPadLEDsDuringMotion
        case showsLaunchpadLEDBubble
        case launchpadLEDBubbleSize
        case launchpadLEDBubbleOriginX
        case launchpadLEDBubbleOriginY
    }

    private struct PersistedPreference: Decodable {
        let preservesPadLEDsDuringMotion: Bool?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scope = try container.decodeIfPresent(CodexMotionDisplayScope.self, forKey: .scope) ?? .allPages
        pageID = try container.decodeIfPresent(UUID.self, forKey: .pageID)
        preservesPadLEDsDuringMotion = try container.decodeIfPresent(Bool.self, forKey: .preservesPadLEDsDuringMotion) ?? false
        showsLaunchpadLEDBubble = try container.decodeIfPresent(Bool.self, forKey: .showsLaunchpadLEDBubble) ?? true
        launchpadLEDBubbleSize = try container.decodeIfPresent(LaunchpadLEDBubbleSize.self, forKey: .launchpadLEDBubbleSize) ?? .regular
        launchpadLEDBubbleOriginX = try container.decodeIfPresent(Double.self, forKey: .launchpadLEDBubbleOriginX)
        launchpadLEDBubbleOriginY = try container.decodeIfPresent(Double.self, forKey: .launchpadLEDBubbleOriginY)
    }
}

enum CodexMotionRuleControlPlacement: Equatable {
    case mainRuleRow
    case hidden
}

enum CodexMotionRuleLayout {
    static func holdTogglePlacement(for activity: CodexActivity) -> CodexMotionRuleControlPlacement {
        activity == .running ? .mainRuleRow : .hidden
    }
}

struct CodexMotionPresentation: Codable, Hashable {
    var presetID: UUID?
    var dismissal: CodexMotionDismissal = .afterDuration
    var durationSeconds = 5
    var dismissPadID = "grid_0_0"
    var keepsRunningUntilActivityChanges = false
    var preservesPadLEDsDuringMotion = false

    init(
        presetID: UUID? = nil,
        dismissal: CodexMotionDismissal = .afterDuration,
        durationSeconds: Int = 5,
        dismissPadID: String = "grid_0_0",
        keepsRunningUntilActivityChanges: Bool = false,
        preservesPadLEDsDuringMotion: Bool = false
    ) {
        self.presetID = presetID
        self.dismissal = dismissal
        self.durationSeconds = durationSeconds
        self.dismissPadID = dismissPadID
        self.keepsRunningUntilActivityChanges = keepsRunningUntilActivityChanges
        self.preservesPadLEDsDuringMotion = preservesPadLEDsDuringMotion
    }

    var automaticStopDelay: TimeInterval? {
        dismissal == .afterDuration ? TimeInterval(durationSeconds) : nil
    }

    func automaticStopDelay(for activity: CodexActivity) -> TimeInterval? {
        if activity == .running, keepsRunningUntilActivityChanges {
            return nil
        }
        return automaticStopDelay
    }

    func shouldDismiss(for padID: String) -> Bool {
        switch dismissal {
        case .afterDuration: false
        case .anyPad: true
        case .assignedPad: dismissPadID == padID
        }
    }

    private enum CodingKeys: String, CodingKey {
        case presetID
        case dismissal
        case durationSeconds
        case dismissPadID
        case keepsRunningUntilActivityChanges
        case preservesPadLEDsDuringMotion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presetID = try container.decodeIfPresent(UUID.self, forKey: .presetID)
        dismissal = try container.decodeIfPresent(CodexMotionDismissal.self, forKey: .dismissal) ?? .afterDuration
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 5
        dismissPadID = try container.decodeIfPresent(String.self, forKey: .dismissPadID) ?? "grid_0_0"
        keepsRunningUntilActivityChanges = try container.decodeIfPresent(Bool.self, forKey: .keepsRunningUntilActivityChanges) ?? false
        preservesPadLEDsDuringMotion = try container.decodeIfPresent(Bool.self, forKey: .preservesPadLEDsDuringMotion) ?? false
    }
}
