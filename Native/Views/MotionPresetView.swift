import SwiftUI

struct MotionPresetView: View {
    @Bindable var store: LaunchpadStore
    let midi: LaunchpadMIDIManager

    @Environment(\.dismiss) private var dismiss
    @State private var jsonText = ""
    @State private var selectedPresetID: UUID?
    @State private var previewFrameIndex = 0
    @State private var isPlaying = false
    @State private var importMessage = ""
    @State private var isImportError = false
    @State private var previewTimer: Timer?

    var body: some View {
        HStack(spacing: 0) {
            presetSidebar
                .frame(width: 220)
            Divider().overlay(.white.opacity(0.12))
            editor
                .frame(minWidth: 520)
        }
        .frame(width: 820, height: 620)
        .background(Color(red: 0.035, green: 0.035, blue: 0.045))
        .onAppear { selectedPresetID = store.motionPresets.first?.id }
        .onDisappear { stopPreview() }
    }

    private var presetSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MOTION PRESETS").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.yellow)
                    Text("8×8 LED 모션").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                }
                Spacer()
                Button(action: { selectedPresetID = nil; jsonText = "" }) {
                    Image(systemName: "plus").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            }

            if store.motionPresets.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "sparkles.square.filled.on.square").font(.system(size: 28)).foregroundStyle(.orange)
                    Text("아직 프리셋이 없습니다").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    Text("오른쪽에 ChatGPT의 JSON 답변을 붙여 넣으세요.").font(.system(size: 11)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(store.motionPresets) { preset in
                            Button { select(preset) } label: {
                                HStack(spacing: 9) {
                                    MiniMotionPreview(preset: preset)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(preset.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                        Text("\(preset.frames.count) 프레임 · \(preset.frameDurationMs)ms").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(8)
                                .foregroundStyle(.white)
                                .background(selectedPresetID == preset.id ? .orange.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedPresetID == preset.id ? .orange : .white.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("삭제", role: .destructive) {
                                    if selectedPresetID == preset.id { stopPreview(); selectedPresetID = nil }
                                    store.removeMotionPreset(preset)
                                }
                            }
                        }
                    }
                }
            }
            Spacer()
            Text("MK1 팔레트만 허용됨").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(red: 0.055, green: 0.055, blue: 0.07))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CHATGPT 모션 가져오기").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    Text("프롬프트를 복사해 원하는 모션을 요청한 뒤 JSON 답변을 붙여 넣으세요.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("닫기") { dismiss() }.buttonStyle(.bordered)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Button("제작 프롬프트 복사") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(MotionPresetImportService.chatGPTPrompt, forType: .string)
                            importMessage = "프롬프트를 복사했습니다. ChatGPT에 붙여 넣고 마지막 ‘요청:’ 뒤에 원하는 모션을 쓰세요."
                            isImportError = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        Button("클립보드 붙여넣기") {
                            jsonText = NSPasteboard.general.string(forType: .string) ?? ""
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Text("JSON 전용").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.yellow)
                    }

                    TextEditor(text: $jsonText)
                        .font(.system(size: 11, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(8)
                        .frame(height: 150)
                        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.17)))

                    HStack {
                        Button("프리셋으로 등록") { importPreset() }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        if !importMessage.isEmpty {
                            Text(importMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(isImportError ? .red : .green)
                                .lineLimit(2)
                        }
                        Spacer()
                    }

                    Divider().overlay(.white.opacity(0.14))
                    previewSection
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder private var previewSection: some View {
        if let preset = selectedPreset {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("\(preset.name) 미리보기").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    MotionMatrix(frame: preset.frames[previewFrameIndex])
                    Text("프레임 \(previewFrameIndex + 1) / \(preset.frames.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    presetMetric("재생", preset.loop ? "반복" : "한 번")
                    presetMetric("속도", "\(preset.frameDurationMs)ms / 프레임")
                    presetMetric("색상", usedColors(in: preset))
                    Button(isPlaying ? "재생 중지" : "실제 Launchpad에서 재생") {
                        isPlaying ? stopPreview() : startPreview(preset)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isPlaying ? .red : .orange)
                    Text(midi.isConnected ? "연결된 MK1에도 동시에 표시됩니다." : "MK1 미연결: 화면 미리보기만 재생합니다.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        } else {
            ContentUnavailableView("프리셋을 선택하세요", systemImage: "square.grid.3x3")
                .frame(maxWidth: .infinity, minHeight: 160)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedPreset: MotionPreset? {
        store.motionPresets.first { $0.id == selectedPresetID }
    }

    private func presetMetric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 38, alignment: .leading)
            Text(value).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.86))
        }
    }

    private func usedColors(in preset: MotionPreset) -> String {
        let values = Set(preset.frames.flatMap(\.pixels).map(\.color)).sorted()
        return values.joined(separator: ", ")
    }

    private func select(_ preset: MotionPreset) {
        stopPreview()
        selectedPresetID = preset.id
        previewFrameIndex = 0
    }

    private func importPreset() {
        do {
            let preset = try MotionPresetImportService.decode(jsonText)
            stopPreview()
            store.addMotionPreset(preset)
            selectedPresetID = preset.id
            previewFrameIndex = 0
            importMessage = "‘\(preset.name)’ 프리셋을 등록했습니다."
            isImportError = false
        } catch {
            importMessage = error.localizedDescription
            isImportError = true
        }
    }

    private func startPreview(_ preset: MotionPreset) {
        stopPreview(restoreMIDI: false)
        isPlaying = true
        previewFrameIndex = 0
        midi.playMotion(preset)
        scheduleNextPreviewFrame(for: preset)
    }

    private func scheduleNextPreviewFrame(for preset: MotionPreset) {
        previewTimer?.invalidate()
        previewTimer = Timer.scheduledTimer(withTimeInterval: Double(preset.frameDurationMs) / 1000, repeats: false) { _ in
            Task { @MainActor in
                advancePreview(for: preset)
            }
        }
    }

    private func advancePreview(for preset: MotionPreset) {
        guard isPlaying, selectedPresetID == preset.id else { return }
        if previewFrameIndex + 1 < preset.frames.count {
            previewFrameIndex += 1
            scheduleNextPreviewFrame(for: preset)
        } else if preset.loop {
            previewFrameIndex = 0
            scheduleNextPreviewFrame(for: preset)
        } else {
            stopPreview()
        }
    }

    private func stopPreview(restoreMIDI: Bool = true) {
        previewTimer?.invalidate()
        previewTimer = nil
        isPlaying = false
        if restoreMIDI { midi.stopMotion() }
    }
}

private struct MotionMatrix: View {
    let frame: MotionFrame

    var body: some View {
        let colors = pixelColors(from: frame)
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(23), spacing: 4), count: 8), spacing: 4) {
            ForEach(1...64, id: \.self) { index in
                let row = (index - 1) / 8 + 1
                let column = (index - 1) % 8 + 1
                RoundedRectangle(cornerRadius: 4)
                    .fill((PadColor(rawValue: colors["\(row)_\(column)"] ?? "off") ?? .off).color)
                    .frame(width: 23, height: 23)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.12)))
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct MiniMotionPreview: View {
    let preset: MotionPreset

    var body: some View {
        let frame = preset.frames.first ?? MotionFrame(pixels: [])
        let colors = pixelColors(from: frame)
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(5), spacing: 1), count: 8), spacing: 1) {
            ForEach(1...64, id: \.self) { index in
                let row = (index - 1) / 8 + 1
                let column = (index - 1) % 8 + 1
                Rectangle().fill((PadColor(rawValue: colors["\(row)_\(column)"] ?? "off") ?? .off).color)
            }
        }
        .frame(width: 47, height: 47)
        .padding(4)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }
}

private func pixelColors(from frame: MotionFrame) -> [String: String] {
    frame.pixels.reduce(into: [:]) { result, pixel in
        result["\(pixel.row)_\(pixel.column)"] = pixel.color
    }
}
