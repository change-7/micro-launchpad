import AppKit
import SwiftUI

@MainActor
final class LaunchpadLEDStatusBubble: NSObject, NSWindowDelegate {
    static func contentSize(for size: LaunchpadLEDBubbleSize) -> NSSize {
        let points = CGFloat(size.points)
        return NSSize(width: points, height: points)
    }

    private let panel: NSPanel
    private weak var statusButton: NSStatusBarButton?
    private var saveOrigin: ((CGPoint) -> Void)?
    private var isApplyingFrame = false
    private var hasInstalledContent = false
    private var displayedSize: LaunchpadLEDBubbleSize?

    override init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize(for: .regular)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.delegate = self
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
    }

    func attach(to button: NSStatusBarButton?) {
        statusButton = button
    }

    func update(midi: LaunchpadMIDIManager, store: LaunchpadStore) {
        saveOrigin = { [weak store] origin in store?.setLaunchpadLEDBubbleOrigin(origin) }
        guard store.codexMotionDisplaySettings.showsLaunchpadLEDBubble else {
            close()
            return
        }

        let size = store.codexMotionDisplaySettings.launchpadLEDBubbleSize
        if !hasInstalledContent || displayedSize != size {
            panel.contentView = LaunchpadBubbleHostingView(
                rootView: LaunchpadLEDStatusBubbleView(midi: midi, size: size)
            )
            hasInstalledContent = true
            displayedSize = size
            resize(to: Self.contentSize(for: size))
            setFrameOrigin(panel.frame.origin)
        }
        if !panel.isVisible {
            setFrameOrigin(restoredOrigin(from: store))
            panel.orderFrontRegardless()
        }
    }

    func close() {
        panel.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingFrame, panel.isVisible else { return }
        saveOrigin?(panel.frame.origin)
    }

    private func restoredOrigin(from store: LaunchpadStore) -> CGPoint {
        let settings = store.codexMotionDisplaySettings
        if let x = settings.launchpadLEDBubbleOriginX,
           let y = settings.launchpadLEDBubbleOriginY {
            return clamped(CGPoint(x: x, y: y))
        }
        return defaultOrigin()
    }

    private func defaultOrigin() -> CGPoint {
        if let button = statusButton,
           let window = button.window {
            let buttonFrame = button.convert(button.bounds, to: nil)
            let screenFrame = window.convertToScreen(buttonFrame)
            return CGPoint(
                x: screenFrame.midX - panel.frame.width / 2,
                y: screenFrame.minY - panel.frame.height - 8
            )
        }
        let frame = NSScreen.main?.visibleFrame ?? .zero
        return CGPoint(x: frame.maxX - panel.frame.width - 18, y: frame.maxY - panel.frame.height - 18)
    }

    private func clamped(_ origin: CGPoint) -> CGPoint {
        let visibleFrame = (NSScreen.screens.first { $0.visibleFrame.intersects(NSRect(origin: origin, size: panel.frame.size)) } ?? NSScreen.main)?.visibleFrame
            ?? .zero
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - panel.frame.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - panel.frame.height)
        return CGPoint(
            x: min(max(origin.x, visibleFrame.minX), maximumX),
            y: min(max(origin.y, visibleFrame.minY), maximumY)
        )
    }

    private func setFrameOrigin(_ origin: CGPoint) {
        isApplyingFrame = true
        panel.setFrameOrigin(clamped(origin))
        isApplyingFrame = false
    }

    private func resize(to size: NSSize) {
        isApplyingFrame = true
        panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: true)
        isApplyingFrame = false
    }
}

private final class LaunchpadBubbleHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

private struct LaunchpadLEDStatusBubbleView: View {
    let midi: LaunchpadMIDIManager
    let size: LaunchpadLEDBubbleSize

    var body: some View {
        let state = midi.ledState
        VStack(spacing: gap) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<8, id: \.self) { column in
                        led(state.grid[row * 8 + column])
                        }
                    }
                }
        }
        .padding(padding)
        .frame(width: points, height: points)
        .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.16))
        }
    }

    private var points: CGFloat { CGFloat(size.points) }
    private var scale: CGFloat { points / 156 }
    private var padding: CGFloat { 15 * scale }
    private var gap: CGFloat { 3 * scale }

    private func led(_ value: UInt8) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color(for: value))
            .frame(width: 12 * scale, height: 12 * scale)
            .shadow(color: color(for: value).opacity(value == 12 ? 0 : 0.75), radius: 3)
    }

    private var cornerRadius: CGFloat { 2 * scale }

    private func color(for value: UInt8) -> Color {
        switch value {
        case 13: .red.opacity(0.36)
        case 14: .red.opacity(0.72)
        case 15: .red
        case 28: .green.opacity(0.36)
        case 44: .green.opacity(0.72)
        case 60: .green
        case 29: .orange.opacity(0.4)
        case 46: .orange.opacity(0.78)
        case 62: .yellow
        case 63: .orange
        default: Color.white.opacity(0.08)
        }
    }
}
