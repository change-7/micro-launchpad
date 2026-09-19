import AppKit

@MainActor
final class CodexStatusBarIndicator {
    private static let preferenceKey = "chatgpt-micro-launchpad.status-bar-codex-motion-enabled"
    private static let iconSize = NSSize(width: 18, height: 18)
    private static let dotCenters: [NSPoint] = [
        NSPoint(x: 4, y: 14), NSPoint(x: 9, y: 14), NSPoint(x: 14, y: 14),
        NSPoint(x: 4, y: 9), NSPoint(x: 9, y: 9), NSPoint(x: 14, y: 9),
        NSPoint(x: 4, y: 4), NSPoint(x: 9, y: 4), NSPoint(x: 14, y: 4)
    ]
    private static let outerDotIndices = [0, 1, 2, 5, 8, 7, 6, 3]

    private let preferences = UserDefaults(suiteName: "com.pdg.chatgpt-micro-launchpad.native") ?? .standard
    private weak var statusButton: NSStatusBarButton?
    private var animationTimer: Timer?
    private var frameIndex = 0
    private var activity: CodexActivity = .idle

    private(set) var isEnabled: Bool

    init() {
        isEnabled = preferences.object(forKey: Self.preferenceKey) as? Bool ?? true
    }

    func attach(to button: NSStatusBarButton?) {
        statusButton = button
        button?.setAccessibilityLabel("마이크로 런치패드")
        updateAnimationTimer()
        render()
    }

    func update(activity: CodexActivity) {
        self.activity = activity
        updateAnimationTimer()
        render()
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        preferences.set(enabled, forKey: Self.preferenceKey)
        preferences.synchronize()
        updateAnimationTimer()
        render()
    }

    private var shouldAnimate: Bool {
        isEnabled && Self.isAnimatedActivity(activity)
    }

    static func isAnimatedActivity(_ activity: CodexActivity) -> Bool {
        switch activity {
        case .connecting, .running, .waitingForApproval, .failed:
            return true
        case .idle, .completed:
            return false
        }
    }

    private func updateAnimationTimer() {
        guard shouldAnimate else {
            animationTimer?.invalidate()
            animationTimer = nil
            frameIndex = 0
            return
        }
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advanceFrame()
            }
        }
    }

    private func advanceFrame() {
        guard shouldAnimate else {
            updateAnimationTimer()
            render()
            return
        }
        frameIndex += 1
        render()
    }

    private func render() {
        guard let statusButton else { return }
        guard isEnabled, Self.isAnimatedActivity(activity) else {
            statusButton.image = Self.staticImage()
            return
        }
        statusButton.image = Self.makeImage(activity: activity, frameIndex: frameIndex)
    }

    private static func staticImage() -> NSImage? {
        let image = NSImage(
            systemSymbolName: "square.grid.3x3.fill",
            accessibilityDescription: "마이크로 런치패드"
        )
        image?.isTemplate = true
        return image
    }

    private static func makeImage(activity: CodexActivity, frameIndex: Int) -> NSImage {
        let image = NSImage(size: iconSize)
        image.lockFocus()

        let baseColor = NSColor.white.withAlphaComponent(0.82)
        for center in dotCenters {
            drawDot(at: center, radius: 2.05, color: baseColor)
        }

        switch activity {
        case .connecting, .running:
            let activeIndex = outerDotIndices[frameIndex % outerDotIndices.count]
            let previousIndex = outerDotIndices[(frameIndex + outerDotIndices.count - 1) % outerDotIndices.count]
            drawGlow(at: dotCenters[previousIndex], color: .systemOrange, intensity: 0.45)
            drawGlow(at: dotCenters[activeIndex], color: .systemOrange, intensity: 1)
            drawDot(at: dotCenters[previousIndex], radius: 2.05, color: NSColor.systemOrange.withAlphaComponent(0.55))
            drawDot(at: dotCenters[activeIndex], radius: 2.15, color: .systemOrange)
        case .waitingForApproval, .failed:
            let isOn = frameIndex % 2 == 0
            if isOn {
                for index in outerDotIndices {
                    drawGlow(at: dotCenters[index], color: .systemRed, intensity: 0.8)
                    drawDot(at: dotCenters[index], radius: 2.1, color: .systemRed)
                }
                drawGlow(at: dotCenters[4], color: .systemRed, intensity: 0.55)
                drawDot(at: dotCenters[4], radius: 2.05, color: .systemRed.withAlphaComponent(0.9))
            }
        case .idle, .completed:
            break
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawGlow(at center: NSPoint, color: NSColor, intensity: CGFloat) {
        let glowColor = color.withAlphaComponent(0.16 * intensity)
        drawDot(at: center, radius: 4.4, color: glowColor)
        drawDot(at: center, radius: 3.2, color: color.withAlphaComponent(0.28 * intensity))
    }

    private static func drawDot(at center: NSPoint, radius: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )).fill()
    }
}
