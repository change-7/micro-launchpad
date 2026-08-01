import Foundation
import Observation

@MainActor
@Observable
final class VirtualMotionPlayer {
    private(set) var frame: MotionFrame?
    private var timer: Timer?
    private var preset: MotionPreset?
    private var underlyingPage: LaunchPage?
    private var preservesPadLEDs = false
    private var frameIndex = 0

    func play(_ motion: MotionPreset, over page: LaunchPage, preservingPadLEDs: Bool = false) {
        stop()
        preset = motion
        underlyingPage = page
        preservesPadLEDs = preservingPadLEDs
        frameIndex = 0
        updateDisplayedFrame()
        scheduleNextFrame()
    }

    func updateUnderlyingPage(_ page: LaunchPage) {
        underlyingPage = page
        updateDisplayedFrame()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        preset = nil
        underlyingPage = nil
        preservesPadLEDs = false
        frameIndex = 0
        frame = nil
    }

    private func scheduleNextFrame() {
        guard let preset else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Double(preset.frameDurationMs) / 1000, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.advanceFrame() }
        }
    }

    private func advanceFrame() {
        guard let preset else { return }
        if frameIndex + 1 < preset.frames.count {
            frameIndex += 1
        } else if preset.loop {
            frameIndex = 0
        } else {
            stop()
            return
        }
        updateDisplayedFrame()
        scheduleNextFrame()
    }

    private func updateDisplayedFrame() {
        guard let preset, preset.frames.indices.contains(frameIndex) else {
            frame = nil
            return
        }
        let motionFrame = preset.frames[frameIndex]
        guard preservesPadLEDs, let underlyingPage else {
            frame = motionFrame
            return
        }

        var colors = (0..<64).map { index in
            underlyingPage.pads.indices.contains(index) ? underlyingPage.pads[index].idleColor : "off"
        }
        for pixel in motionFrame.pixels where (1...8).contains(pixel.row) && (1...8).contains(pixel.column) {
            colors[(pixel.row - 1) * 8 + pixel.column - 1] = pixel.color
        }
        frame = MotionFrame(pixels: colors.enumerated().map { index, color in
            MotionPixel(row: index / 8 + 1, column: index % 8 + 1, color: color)
        })
    }
}
