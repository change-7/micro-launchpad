import Foundation
import Network
import Observation

struct CodexRemoteState: Codable, Equatable, Sendable {
    let type: String
    let protocolVersion: Int
    let macConnected: Bool
    let codexConnected: Bool
    let activity: CodexActivity
    let message: String
    let usedPercent: Int?
    let remainingPercent: Int?
    let resetsAt: Date?
    let fiveHourUsedPercent: Int?
    let fiveHourRemainingPercent: Int?
    let fiveHourResetsAt: Date?
    let smartphonePages: [SmartphonePage]
    /// Optional for wire compatibility with older bridge clients and cached states.
    let smartphoneIconAssets: [String: SmartphoneIconAsset]?
    let approval: CodexRemoteApproval?
    let completionEventID: Int
    let activeSessionCount: Int

    init(
        macConnected: Bool,
        codexConnected: Bool,
        activity: CodexActivity,
        message: String,
        weeklyUsage: CodexWeeklyUsage?,
        fiveHourUsage: CodexFiveHourUsage?,
        smartphonePages: [SmartphonePage] = SmartphoneDefaults.pages(),
        smartphoneIconAssets: [String: SmartphoneIconAsset] = [:],
        approval: CodexRemoteApproval? = nil,
        completionEventID: Int = 0,
        activeSessionCount: Int = 0
    ) {
        let used = weeklyUsage.map { min(max($0.usedPercent, 0), 100) }
        let fiveHourUsed = fiveHourUsage.map { min(max($0.usedPercent, 0), 100) }
        self.type = "state"
        self.protocolVersion = 2
        self.macConnected = macConnected
        self.codexConnected = codexConnected
        self.activity = activity
        self.message = message
        self.usedPercent = used
        self.remainingPercent = used.map { 100 - $0 }
        self.resetsAt = weeklyUsage?.resetsAt
        self.fiveHourUsedPercent = fiveHourUsed
        self.fiveHourRemainingPercent = fiveHourUsed.map { 100 - $0 }
        self.fiveHourResetsAt = fiveHourUsage?.resetsAt
        self.smartphonePages = smartphonePages
        self.smartphoneIconAssets = smartphoneIconAssets
        self.approval = approval
        self.completionEventID = completionEventID
        self.activeSessionCount = activeSessionCount
    }
}

/// A small, transport-safe icon asset keyed by SmartphoneButton.id.
/// `data` is base64-encoded PNG data so the newline-delimited JSON bridge stays self-contained.
struct SmartphoneIconAsset: Codable, Equatable, Sendable {
    let kind: String
    let mimeType: String
    let data: String

    init(kind: String = "app", mimeType: String = "image/png", data: String) {
        self.kind = kind
        self.mimeType = mimeType
        self.data = data
    }
}

struct CodexRemoteIconAssets: Codable, Equatable, Sendable {
    let type: String
    let protocolVersion: Int
    let assets: [String: SmartphoneIconAsset]

    init(assets: [String: SmartphoneIconAsset]) {
        self.type = "smartphoneIconAssets"
        self.protocolVersion = 1
        self.assets = assets
    }
}

struct CodexRemoteApproval: Codable, Equatable, Sendable {
    let requestID: Int
    let title: String
    let detail: String
}

struct CodexRemoteCommand: Codable, Equatable, Sendable {
    let type: String
    let protocolVersion: Int
    let id: String
    let command: String
    let buttonID: String?
    let action: PadAction?
    let decision: String?

    init(
        type: String,
        protocolVersion: Int,
        id: String,
        command: String,
        buttonID: String? = nil,
        action: PadAction? = nil,
        decision: String? = nil
    ) {
        self.type = type
        self.protocolVersion = protocolVersion
        self.id = id
        self.command = command
        self.buttonID = buttonID
        self.action = action
        self.decision = decision
    }
}

struct CodexRemoteCommandResult: Codable, Equatable, Sendable {
    let type: String
    let protocolVersion: Int
    let id: String
    let success: Bool
    let message: String

    init(id: String, success: Bool, message: String) {
        self.type = "commandResult"
        self.protocolVersion = 1
        self.id = id
        self.success = success
        self.message = message
    }
}

@MainActor
@Observable
final class CodexRemoteBridge {
    static let port: UInt16 = 43_123
    static let serviceType = "_micro-launchpad._tcp"

    private(set) var isRunning = false
    private(set) var clientCount = 0
    var onCommand: ((CodexRemoteCommand) -> CodexRemoteCommandResult)?

    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var receiveBuffers: [UUID: Data] = [:]
    private var lastState: CodexRemoteState?
    private var lastIconAssets: [String: SmartphoneIconAsset]?
    private let queue = DispatchQueue(label: "MicroLaunchpad.remote-bridge", qos: .userInitiated)

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.service = NWListener.Service(name: "Micro Launchpad", type: Self.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .failed = state {
                        self.isRunning = false
                    } else if case .ready = state {
                        self.isRunning = true
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.accept(connection)
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        receiveBuffers.removeAll()
        lastIconAssets = nil
        clientCount = 0
        isRunning = false
    }

    func publish(_ state: CodexRemoteState) {
        let iconAssetsChanged = state.smartphoneIconAssets != lastIconAssets
        lastState = state
        lastIconAssets = state.smartphoneIconAssets
        guard let data = encodedLine(state, includingSmartphoneIconAssets: false) else { return }
        for connection in connections.values {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
        if iconAssetsChanged, let assets = state.smartphoneIconAssets {
            send(CodexRemoteIconAssets(assets: assets), to: connections.values)
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        connections[id] = connection
        receiveBuffers[id] = Data()
        clientCount = connections.count
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .failed = state { self.remove(connectionID: id) }
                if case .cancelled = state { self.remove(connectionID: id) }
            }
        }
        connection.start(queue: queue)
        receive(from: connection, id: id)
    }

    private func receive(from connection: NWConnection, id: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.receiveBuffers[id, default: Data()].append(data)
                    self.consumeLines(for: connection, id: id)
                }
                if isComplete { self.remove(connectionID: id) }
                else if self.connections[id] != nil { self.receive(from: connection, id: id) }
            }
        }
    }

    private func consumeLines(for connection: NWConnection, id: UUID) {
        guard var buffer = receiveBuffers[id] else { return }
        while let newlineIndex = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)
            guard let object = try? JSONSerialization.jsonObject(with: line),
                  let payload = object as? [String: Any],
                  let type = payload["type"] as? String else { continue }
            if type == "hello" {
                sendCurrentState(to: connection)
            } else if type == "command",
                      let commandData = try? JSONSerialization.data(withJSONObject: payload),
                      let command = try? JSONDecoder().decode(CodexRemoteCommand.self, from: commandData),
                      let result = onCommand?(command) {
                send(result, to: connection)
            }
        }
        receiveBuffers[id] = buffer
    }

    private func sendCurrentState(to connection: NWConnection) {
        guard let state = lastState, let data = encodedLine(state, includingSmartphoneIconAssets: false) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
        if let assets = state.smartphoneIconAssets {
            send(CodexRemoteIconAssets(assets: assets), to: [connection])
        }
    }

    private func send(_ result: CodexRemoteCommandResult, to connection: NWConnection) {
        guard let data = encodedLine(result) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func send<T: Encodable>(_ value: T, to connections: Dictionary<UUID, NWConnection>.Values) {
        guard let data = encodedLine(value) else { return }
        for connection in connections {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private func send<T: Encodable>(_ value: T, to connections: [NWConnection]) {
        guard let data = encodedLine(value) else { return }
        for connection in connections {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private func remove(connectionID id: UUID) {
        connections[id]?.cancel()
        connections.removeValue(forKey: id)
        receiveBuffers.removeValue(forKey: id)
        clientCount = connections.count
    }

    private func encodedLine(_ state: CodexRemoteState, includingSmartphoneIconAssets: Bool = true) -> Data? {
        let encoder = JSONEncoder()
        // The Android client interprets reset timestamps as Unix epoch seconds.
        // Make that wire format explicit instead of Foundation's default
        // reference-date encoding (seconds since 2001).
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let encoded = try? encoder.encode(state) else { return nil }
        if includingSmartphoneIconAssets { return encoded + Data([0x0A]) }
        guard var object = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return nil }
        object.removeValue(forKey: "smartphoneIconAssets")
        guard let stripped = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return stripped + Data([0x0A])
    }

    private func encodedLine<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let encoded = try? encoder.encode(value) else { return nil }
        return encoded + Data([0x0A])
    }
}
