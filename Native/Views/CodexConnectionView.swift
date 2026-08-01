import SwiftUI

struct CodexConnectionView: View {
    enum Section: Hashable {
        case statusMotion
    }

    static let visibleSections: [Section] = [.statusMotion]

    @Bindable var store: LaunchpadStore
    let midi: LaunchpadMIDIManager
    let codex: CodexAppServerClient

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            header
            connectionCard

            settingsContent
            .frame(maxHeight: .infinity)

            Text("이 앱에서 시작한 Codex 작업만 상태·모션으로 추적합니다. 기존 ChatGPT 앱 작업은 포함되지 않습니다.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(22)
        .frame(width: 820, height: 580)
        .background(Color(red: 0.035, green: 0.035, blue: 0.045))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CODEX 연결")
                    .font(.system(size: 20, weight: .bold))
                Text("Codex 상태를 Launchpad LED와 모션으로 표시합니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("닫기") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectionCard: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 9, height: 9)
            Text(codex.message)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
            Spacer(minLength: 12)
            Button(codex.isConnected ? "연결 종료" : "Codex 연결") {
                codex.isConnected ? codex.disconnect() : codex.connect()
            }
            .buttonStyle(.borderedProminent)
            .tint(codex.isConnected ? .red : .green)
        }
        .padding(12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var settingsContent: some View {
        if Self.visibleSections.contains(.statusMotion) {
            motionPane
        }
    }

    private var motionPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("상태별 모션")
                        .font(.system(size: 15, weight: .semibold))
                    Text("표시 페이지와 각 상태의 모션·종료 조건을 설정합니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("MK1 팔레트")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.yellow)
            }

            motionDisplayLocation

            ScrollView {
                VStack(spacing: 0) {
                    ForEach([CodexActivity.connecting, .running, .waitingForApproval, .completed, .failed]) { activity in
                        CodexMotionRuleCard(
                            store: store,
                            midi: midi,
                            activity: activity
                        )
                        if activity != .failed {
                            Divider().overlay(.white.opacity(0.12))
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.top, 12)
    }

    private var motionDisplayLocation: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Text("표시 위치")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("Codex 상태 모션 표시 위치", selection: motionDisplayScopeBinding) {
                    ForEach(CodexMotionDisplayScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                if store.codexMotionDisplaySettings.scope == .specificPage {
                    Picker("Codex 상태 모션 표시 페이지", selection: motionDisplayPageBinding) {
                        ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, page in
                            Text("P\(index + 1) · \(page.name)").tag(page.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                } else {
                    Text("현재 페이지와 관계없이 표시")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Toggle("모션 중 기존 패드 LED 유지", isOn: preservesPadLEDsBinding)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("codex-motion-preserve-pad-leds-toggle")
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 6)
    }

    private var motionDisplayScopeBinding: Binding<CodexMotionDisplayScope> {
        Binding(
            get: { store.codexMotionDisplaySettings.scope },
            set: { store.setCodexMotionDisplayScope($0) }
        )
    }

    private var motionDisplayPageBinding: Binding<UUID> {
        Binding(
            get: { store.codexMotionDisplaySettings.pageID ?? store.pages[0].id },
            set: { store.setCodexMotionDisplayPageID($0) }
        )
    }

    private var preservesPadLEDsBinding: Binding<Bool> {
        Binding(
            get: { store.codexMotionDisplaySettings.preservesPadLEDsDuringMotion },
            set: { store.setCodexMotionPreservesPadLEDsDuringMotion($0) }
        )
    }

    private var statusColor: Color {
        switch codex.activity {
        case .idle: .gray
        case .connecting: .yellow
        case .running: .green
        case .waitingForApproval: .orange
        case .completed: .green
        case .failed: .red
        }
    }
}
