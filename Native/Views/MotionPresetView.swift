import SwiftUI

struct MotionPresetView: View {
    @Bindable var store: LaunchpadStore
    let midi: LaunchpadMIDIManager
    let isEmbedded: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var jsonText = ""
    @State private var selectedPresetID: UUID?
    @State private var previewFrameIndex = 0
    @State private var isPlaying = false
    @State private var importMessage = ""
    @State private var isImportError = false
    @State private var previewTimer: Timer?
    @State private var editingPresetID: UUID?
    @State private var editedPresetName = ""
    @FocusState private var focusedPresetID: UUID?

    init(store: LaunchpadStore, midi: LaunchpadMIDIManager, isEmbedded: Bool = false) {
        self.store = store
        self.midi = midi
        self.isEmbedded = isEmbedded
    }

    var body: some View {
        HStack(spacing: 0) {
            presetSidebar
                .frame(width: isEmbedded ? 190 : 220)
            Divider().overlay(.white.opacity(0.12))
            editor
                .frame(minWidth: isEmbedded ? 0 : 520)
        }
        .frame(
            width: isEmbedded ? nil : 820,
            height: isEmbedded ? nil : 620
        )
        .frame(maxWidth: isEmbedded ? .infinity : nil, maxHeight: isEmbedded ? .infinity : nil)
        .background(Color(red: 0.035, green: 0.035, blue: 0.045))
        .onAppear { selectedPresetID = store.motionPresets.first?.id }
        .onDisappear { stopPreview() }
    }

    private var presetSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("프리셋 목록").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(store.motionPresets) { preset in
                            Button { select(preset) } label: {
                                HStack(spacing: 9) {
                                    MiniMotionPreview(preset: preset)
                                        .fixedSize()
                                    VStack(alignment: .leading, spacing: 3) {
                                        if editingPresetID == preset.id {
                                            TextField("프리셋 이름", text: $editedPresetName)
                                                .textFieldStyle(.roundedBorder)
                                                .focused($focusedPresetID, equals: preset.id)
                                                .onSubmit { finishRenaming(preset) }
                                                .onExitCommand { cancelRenaming() }
                                        } else {
                                            Text(preset.name)
                                                .font(.system(size: 12, weight: .semibold))
                                                .lineLimit(2)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(.white)
                                .background(selectedPresetID == preset.id ? .orange.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedPresetID == preset.id ? .orange : .white.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("이름 변경") {
                                    beginRenaming(preset)
                                }
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
        }
        .padding(isEmbedded ? 12 : 16)
        .background(Color(red: 0.055, green: 0.055, blue: 0.07))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CHATGPT 모션 가져오기").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                }
                Spacer()
                if !isEmbedded {
                    Button("닫기") { dismiss() }.buttonStyle(.bordered)
                }
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
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(preset.name) 미리보기").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Button(isPlaying ? "재생 중지" : "실제 Launchpad에서 재생") {
                        isPlaying ? stopPreview() : startPreview(preset)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isPlaying ? .red : .orange)
                }
                MotionMatrix(frame: preset.frames[previewFrameIndex])
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

    private func select(_ preset: MotionPreset) {
        stopPreview()
        selectedPresetID = preset.id
        previewFrameIndex = 0
    }

    private func beginRenaming(_ preset: MotionPreset) {
        selectedPresetID = preset.id
        editingPresetID = preset.id
        editedPresetName = preset.name
        DispatchQueue.main.async { focusedPresetID = preset.id }
    }

    private func finishRenaming(_ preset: MotionPreset) {
        if store.renameMotionPreset(id: preset.id, to: editedPresetName) {
            editingPresetID = nil
            focusedPresetID = nil
        }
    }

    private func cancelRenaming() {
        editingPresetID = nil
        focusedPresetID = nil
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
                    .frame(width: 5, height: 5)
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
