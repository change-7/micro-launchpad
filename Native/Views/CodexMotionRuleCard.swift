import SwiftUI

struct CodexMotionRuleCard: View {
    @Bindable var store: LaunchpadStore
    let midi: LaunchpadMIDIManager
    let activity: CodexActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(activity.title)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 58, alignment: .leading)

                Picker("\(activity.title) 모션", selection: presetBinding) {
                    Text("모션 없음").tag(UUID?.none)
                    ForEach(store.motionPresets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
                .labelsHidden()
                .frame(width: 130)

                Text("종료")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Picker("\(activity.title) 종료 방식", selection: dismissalBinding) {
                    ForEach(CodexMotionDismissal.allCases) { dismissal in
                        Text(dismissal.title).tag(dismissal)
                    }
                }
                .labelsHidden()
                .frame(width: 122)

                dismissalDetail
                    .frame(width: 150, alignment: .leading)

                if CodexMotionRuleLayout.holdTogglePlacement(for: activity) == .mainRuleRow {
                    Toggle("계속 표시", isOn: keepsRunningBinding)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .toggleStyle(.switch)
                        .frame(width: 120)
                        .accessibilityLabel("작업이 끝날 때까지 계속 표시")
                        .accessibilityIdentifier("codex-motion-running-hold-toggle")
                }

                Spacer(minLength: 0)
                Button("미리보기") { preview() }
                    .font(.system(size: 10, weight: .medium))
                    .disabled(store.codexMotionPreset(for: activity) == nil)
            }

        }
        .padding(.vertical, 6)
    }

    private var presentation: CodexMotionPresentation { store.codexMotionPresentation(for: activity) }

    private var presetBinding: Binding<UUID?> {
        Binding(
            get: { presentation.presetID },
            set: { value in
                var updated = presentation
                updated.presetID = value
                store.setCodexMotionPresentation(updated, for: activity)
            }
        )
    }

    private var dismissalBinding: Binding<CodexMotionDismissal> {
        Binding(
            get: { presentation.dismissal },
            set: { value in
                var updated = presentation
                updated.dismissal = value
                store.setCodexMotionPresentation(updated, for: activity)
            }
        )
    }

    private var keepsRunningBinding: Binding<Bool> {
        Binding(
            get: { presentation.keepsRunningUntilActivityChanges },
            set: { value in
                var updated = presentation
                updated.keepsRunningUntilActivityChanges = value
                store.setCodexMotionPresentation(updated, for: activity)
            }
        )
    }

    @ViewBuilder private var dismissalDetail: some View {
        switch presentation.dismissal {
        case .afterDuration:
            Stepper(value: durationBinding, in: 1...120) {
                Text("\(presentation.durationSeconds)초")
                    .font(.system(size: 11, design: .monospaced))
            }
        case .anyPad:
            Text("아무 버튼")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .assignedPad:
            Picker("종료 버튼", selection: dismissPadBinding) {
                ForEach(CodexMotionPadChoice.all) { choice in
                    Text(choice.title).tag(choice.id)
                }
            }
            .labelsHidden()
        }
    }

    private var durationBinding: Binding<Int> {
        Binding(
            get: { presentation.durationSeconds },
            set: { value in
                var updated = presentation
                updated.durationSeconds = value
                store.setCodexMotionPresentation(updated, for: activity)
            }
        )
    }

    private var dismissPadBinding: Binding<String> {
        Binding(
            get: { presentation.dismissPadID },
            set: { value in
                var updated = presentation
                updated.dismissPadID = value
                store.setCodexMotionPresentation(updated, for: activity)
            }
        )
    }

    private func preview() {
        guard let preset = store.codexMotionPreset(for: activity) else { return }
        let loopingPreset = MotionPreset(
            name: preset.name,
            loop: true,
            frameDurationMs: preset.frameDurationMs,
            frames: preset.frames
        )
        let sessionID = midi.playMotion(
            loopingPreset,
            preservingPadLEDs: store.shouldPreservePadLEDsDuringCodexMotion(for: activity)
        )
        guard let delay = presentation.automaticStopDelay else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak midi] in
            midi?.stopMotion(ifCurrent: sessionID)
        }
    }

    private var symbol: String {
        switch activity {
        case .idle: "circle"
        case .connecting: "arrow.triangle.2.circlepath"
        case .running: "gearshape.2"
        case .waitingForApproval: "exclamationmark.triangle.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch activity {
        case .idle: .gray
        case .connecting: .yellow
        case .running: .green
        case .waitingForApproval: .orange
        case .completed: .green
        case .failed: .red
        }
    }
}

struct CodexMotionPadChoice: Identifiable {
    let id: String
    let title: String

    static let all: [CodexMotionPadChoice] = {
        let top = (0..<8).map { CodexMotionPadChoice(id: "top_\($0)", title: "상단 P\($0 + 1)") }
        let grid = (0..<8).flatMap { row in
            (0..<8).map { column in
                CodexMotionPadChoice(id: "grid_\(row)_\(column)", title: "그리드 \(row + 1)행 \(column + 1)열")
            }
        }
        let side = (0..<8).map { CodexMotionPadChoice(id: "side_\($0)", title: "우측 \(Character(UnicodeScalar(65 + $0)!))") }
        return top + grid + side
    }()
}
