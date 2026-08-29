import CoreMIDI
import Foundation
import Observation

struct LaunchpadMIDIMessage: Equatable, Sendable {
    let status: UInt8
    let number: UInt8
    let value: UInt8
}

struct LaunchpadLEDState: Equatable, Sendable {
    var top = Array(repeating: UInt8(12), count: 8)
    var grid = Array(repeating: UInt8(12), count: 64)
    var side = Array(repeating: UInt8(12), count: 8)

    mutating func apply(_ messages: [LaunchpadMIDIMessage]) {
        for message in messages {
            switch message.status & 0xF0 {
            case 0xB0 where (104...111).contains(message.number):
                top[Int(message.number - 104)] = message.value
            case 0x90:
                let row = Int(message.number / 16)
                let column = Int(message.number % 16)
                guard (0..<8).contains(row) else { continue }
                if (0..<8).contains(column) {
                    grid[row * 8 + column] = message.value
                } else if column == 8 {
                    side[row] = message.value
                }
            default:
                continue
            }
        }
    }
}

@Observable
final class LaunchpadMIDIManager: @unchecked Sendable {
    // CoreMIDI invokes its packet callback off the main thread. That callback only parses
    // immutable bytes and schedules UI/action work back on the main queue.
    private(set) var isConnected = false
    private(set) var ledState = LaunchpadLEDState()

    var onPadPressed: ((String) -> Void)?
    var onPagePressed: ((Int) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var connectedSource = MIDIEndpointRef()
    private var connectedDestination = MIDIEndpointRef()
    private var latestPages: [LaunchPage] = []
    private var latestPageIndex = 0
    private var persistentSideLEDValues: [UInt8]?
    private var gridOverlay: [UInt8]?
    private var motionTimer: Timer?
    private var activeMotion: MotionPreset?
    private var activeMotionSessionID: UUID?
    private var preservesPadLEDsDuringMotion = false
    private var motionFrameIndex = 0
    private let messageSink: (([LaunchpadMIDIMessage]) -> Void)?

    init(
        startsMIDIClient: Bool = true,
        messageSink: (([LaunchpadMIDIMessage]) -> Void)? = nil
    ) {
        self.messageSink = messageSink
        if startsMIDIClient { start() }
    }

    deinit {
        motionTimer?.invalidate()
        if connectedSource != 0 { MIDIPortDisconnectSource(inputPort, connectedSource) }
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if client != 0 { MIDIClientDispose(client) }
    }

    func start() {
        guard client == 0 else {
            refreshConnection()
            return
        }

        guard MIDIClientCreateWithBlock("마이크로 런치패드" as CFString, &client, { [weak self] _ in
            DispatchQueue.main.async { self?.refreshConnection() }
        }) == noErr else { return }

        guard MIDIInputPortCreateWithBlock(client, "Launchpad Mini Input" as CFString, &inputPort, { [weak self] packetList, _ in
            self?.receive(packetList)
        }) == noErr else { return }

        guard MIDIOutputPortCreate(client, "Launchpad Mini Output" as CFString, &outputPort) == noErr else { return }
        refreshConnection()
    }

    func updateLEDs(for pages: [LaunchPage], activePage: Int) {
        guard pages.indices.contains(activePage) else { return }
        let activePageChanged = !latestPages.isEmpty && activePage != latestPageIndex
        let currentSideLEDValues = sideLEDValues(for: pages[activePage])
        let previousSideLEDValues = latestPages.indices.contains(latestPageIndex)
            ? sideLEDValues(for: latestPages[latestPageIndex])
            : nil
        if persistentSideLEDValues == nil
            || (!activePageChanged && previousSideLEDValues != currentSideLEDValues) {
            persistentSideLEDValues = currentSideLEDValues
        }
        latestPages = pages
        latestPageIndex = activePage
        if activeMotion != nil {
            sendCurrentMotionFrame()
            return
        }
        let page = pages[activePage]

        var messages = [LaunchpadMIDIMessage(status: 0xB0, number: 0x00, value: 0x01)] // X-Y layout

        for pageIndex in 0..<8 {
            let color = color(for: pages[pageIndex].topButtonColor(isSelected: pageIndex == activePage))
            messages.append(LaunchpadMIDIMessage(status: 0xB0, number: UInt8(104 + pageIndex), value: color.midiValue))
        }

        for row in 0..<8 {
            for column in 0..<8 {
                let pad = page.pads[row * 8 + column]
                let gridIndex = row * 8 + column
                let value = gridOverlay?[gridIndex] ?? color(for: pad.idleColor).midiValue
                messages.append(LaunchpadMIDIMessage(status: 0x90, number: UInt8(row * 16 + column), value: value))
            }

            let sideValue = persistentSideLEDValues?[row] ?? LaunchpadLEDColor.off.midiValue
            messages.append(LaunchpadMIDIMessage(status: 0x90, number: UInt8(row * 16 + 8), value: sideValue))
        }

        send(messages)
    }

    func setGridOverlay(colors: [PadColor]?) {
        let values = colors?.map { LaunchpadLEDColor(rawValue: $0.rawValue)?.midiValue ?? LaunchpadLEDColor.off.midiValue }
        gridOverlay = values?.count == 64 ? values : nil
        guard !latestPages.isEmpty, activeMotion == nil else { return }
        updateLEDs(for: latestPages, activePage: latestPageIndex)
    }

    func flash(_ pad: Pad) {
        guard isConnected, let address = address(for: pad) else { return }
        send([LaunchpadMIDIMessage(status: address.status, number: address.number, value: color(for: pad.activeColor).midiValue)])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, !self.latestPages.isEmpty else { return }
            self.updateLEDs(for: self.latestPages, activePage: self.latestPageIndex)
        }
    }

    func flashPage(_ index: Int, pages: [LaunchPage]) {
        guard isConnected, pages.indices.contains(index) else { return }
        send([LaunchpadMIDIMessage(status: 0xB0, number: UInt8(104 + index), value: color(for: pages[index].pageActiveColor).midiValue)])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, !self.latestPages.isEmpty else { return }
            self.updateLEDs(for: self.latestPages, activePage: self.latestPageIndex)
        }
    }

    @discardableResult
    func playMotion(_ preset: MotionPreset, preservingPadLEDs: Bool = false) -> UUID {
        stopMotion(restorePage: false)
        let sessionID = UUID()
        activeMotionSessionID = sessionID
        activeMotion = preset
        preservesPadLEDsDuringMotion = preservingPadLEDs
        motionFrameIndex = 0
        sendCurrentMotionFrame()
        scheduleNextMotionFrame()
        return sessionID
    }

    func stopMotion(restorePage: Bool = true) {
        motionTimer?.invalidate()
        motionTimer = nil
        activeMotion = nil
        activeMotionSessionID = nil
        preservesPadLEDsDuringMotion = false
        motionFrameIndex = 0
        if restorePage, !latestPages.isEmpty {
            updateLEDs(for: latestPages, activePage: latestPageIndex)
        }
    }

    func stopMotion(ifCurrent sessionID: UUID, restorePage: Bool = true) {
        guard activeMotionSessionID == sessionID else { return }
        stopMotion(restorePage: restorePage)
    }

    private func refreshConnection() {
        let source = (0..<MIDIGetNumberOfSources())
            .map(MIDIGetSource)
            .first(where: isLaunchpad)
        let destination = (0..<MIDIGetNumberOfDestinations())
            .map(MIDIGetDestination)
            .first(where: isLaunchpad)

        if connectedSource != source ?? 0 {
            if connectedSource != 0 { MIDIPortDisconnectSource(inputPort, connectedSource) }
            connectedSource = source ?? 0
            if connectedSource != 0 { MIDIPortConnectSource(inputPort, connectedSource, nil) }
        }

        connectedDestination = destination ?? 0
        isConnected = connectedSource != 0 && connectedDestination != 0

        if !latestPages.isEmpty, isConnected {
            if activeMotion != nil {
                sendCurrentMotionFrame()
            } else {
                updateLEDs(for: latestPages, activePage: latestPageIndex)
            }
        }
    }

    private func receive(_ packetList: UnsafePointer<MIDIPacketList>) {
        var packet = UnsafeMutablePointer(mutating: withUnsafePointer(to: packetList.pointee.packet) { $0 })
        for _ in 0..<packetList.pointee.numPackets {
            let bytes = withUnsafeBytes(of: packet.pointee.data) { Array($0.prefix(Int(packet.pointee.length))) }
            parse(bytes)
            packet = MIDIPacketNext(packet)
        }
    }

    private func parse(_ bytes: [UInt8]) {
        var offset = 0
        while offset + 2 < bytes.count {
            let status = bytes[offset] & 0xF0
            let number = bytes[offset + 1]
            let value = bytes[offset + 2]
            offset += 3

            guard value > 0 else { continue }
            if status == 0x90, let padID = padID(note: number) {
                DispatchQueue.main.async { [weak self] in self?.onPadPressed?(padID) }
            } else if status == 0xB0, (104...111).contains(number) {
                DispatchQueue.main.async { [weak self] in self?.onPagePressed?(Int(number - 104)) }
            }
        }
    }

    private var canSend: Bool { messageSink != nil || isConnected }

    private func send(_ messages: [LaunchpadMIDIMessage]) {
        ledState.apply(messages)
        if let messageSink {
            messageSink(messages)
            return
        }
        guard connectedDestination != 0, outputPort != 0 else { return }
        let capacity = 4096
        let rawList = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: MemoryLayout<MIDIPacketList>.alignment)
        defer { rawList.deallocate() }
        let list = rawList.bindMemory(to: MIDIPacketList.self, capacity: 1)
        var packet = MIDIPacketListInit(list)

        for message in messages {
            var bytes = [message.status, message.number, message.value]
            packet = bytes.withUnsafeMutableBufferPointer { buffer in
                MIDIPacketListAdd(list, capacity, packet, 0, buffer.count, buffer.baseAddress!)
            }
        }
        MIDISend(outputPort, connectedDestination, list)
    }

    private func scheduleNextMotionFrame() {
        guard let preset = activeMotion else { return }
        motionTimer?.invalidate()
        motionTimer = Timer.scheduledTimer(withTimeInterval: Double(preset.frameDurationMs) / 1000, repeats: false) { [weak self] _ in
            guard let self, let current = self.activeMotion else { return }
            let nextIndex = self.motionFrameIndex + 1
            if nextIndex < current.frames.count {
                self.motionFrameIndex = nextIndex
                self.sendCurrentMotionFrame()
                self.scheduleNextMotionFrame()
            } else if current.loop {
                self.motionFrameIndex = 0
                self.sendCurrentMotionFrame()
                self.scheduleNextMotionFrame()
            } else {
                self.stopMotion()
            }
        }
    }

    private func sendCurrentMotionFrame() {
        guard let preset = activeMotion, preset.frames.indices.contains(motionFrameIndex) else { return }
        let frame = preset.frames[motionFrameIndex]
        var pixelColors = ordinaryGridColors()
        if !preservesPadLEDsDuringMotion {
            pixelColors = Array(repeating: LaunchpadLEDColor.off, count: 64)
        }
        // Omitted pixels are transparent only in preservation mode. A present `off`
        // pixel is an explicit black pixel and therefore overrides the ordinary LED.
        for pixel in frame.pixels where (1...8).contains(pixel.row) && (1...8).contains(pixel.column) {
            pixelColors[(pixel.row - 1) * 8 + pixel.column - 1] = color(for: pixel.color)
        }
        let messages = (0..<64).map { index in
            let row = index / 8
            let column = index % 8
            return LaunchpadMIDIMessage(status: 0x90, number: UInt8(row * 16 + column), value: pixelColors[index].midiValue)
        }
        send(messages)
    }

    private func ordinaryGridColors() -> [LaunchpadLEDColor] {
        guard latestPages.indices.contains(latestPageIndex) else {
            return Array(repeating: .off, count: 64)
        }
        let page = latestPages[latestPageIndex]
        return (0..<64).map { index in
            guard page.pads.indices.contains(index) else { return .off }
            return color(for: page.pads[index].idleColor)
        }
    }

    private func sideLEDValues(for page: LaunchPage) -> [UInt8] {
        (0..<8).map { row in
            let side = page.pads.first(where: { $0.id == "side_\(row)" })
            return color(for: side?.idleColor ?? "off").midiValue
        }
    }

    private func isLaunchpad(_ endpoint: MIDIEndpointRef) -> Bool {
        endpointDisplayName(endpoint).localizedCaseInsensitiveContains("launchpad")
    }

    private func endpointDisplayName(_ endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr,
           let value = name?.takeRetainedValue() {
            return value as String
        }
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name) == noErr,
           let value = name?.takeRetainedValue() {
            return value as String
        }
        return "Launchpad Mini"
    }

    private func padID(note: UInt8) -> String? {
        let row = Int(note) / 16
        let column = Int(note) % 16
        guard (0..<8).contains(row) else { return nil }
        if (0..<8).contains(column) { return "grid_\(row)_\(column)" }
        if column == 8 { return "side_\(row)" }
        return nil
    }

    private func address(for pad: Pad) -> (status: UInt8, number: UInt8)? {
        if pad.id.hasPrefix("grid_") {
            let components = pad.id.split(separator: "_")
            guard components.count == 3, let row = Int(components[1]), let column = Int(components[2]) else { return nil }
            return (0x90, UInt8(row * 16 + column))
        }
        if pad.id.hasPrefix("side_"), let row = Int(pad.id.dropFirst(5)) {
            return (0x90, UInt8(row * 16 + 8))
        }
        return nil
    }

    private func color(for rawValue: String) -> LaunchpadLEDColor {
        LaunchpadLEDColor(rawValue: rawValue) ?? .off
    }
}

private enum LaunchpadLEDColor: String {
    case off, darkRed, red, brightRed, darkGreen, green, brightGreen, darkAmber, amber, yellow, orange

    var midiValue: UInt8 {
        switch self {
        case .off: 12
        case .darkRed: 13
        case .red: 14
        case .brightRed: 15
        case .darkGreen: 28
        case .green: 44
        case .brightGreen: 60
        case .darkAmber: 29
        case .amber: 46
        case .yellow: 62
        case .orange: 63
        }
    }
}
