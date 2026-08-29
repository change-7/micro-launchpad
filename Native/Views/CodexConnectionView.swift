import SwiftUI

struct CodexConnectionView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case display
        case motion
        case presets

        var id: Self { self }

        var title: String {
            switch self {
            case .display: "표시 설정"
            case .motion: "상태별 모션"
            case .presets: "모션 프리셋"
            }
        }

        var symbol: String {
            switch self {
            case .display: "display"
            case .motion: "waveform.path"
            case .presets: "square.grid.3x3"
            }
        }
    }

    static var availableTabTitles: [String] { Tab.allCases.map(\.title) }

    @Bindable var store: LaunchpadStore
    let midi: LaunchpadMIDIManager
    let codex: CodexAppServerClient

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Tab = .display

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            .frame(width: 190)
            .layoutPriority(1)

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text(selectedTab.title)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button("완료") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider()

                switch selectedTab {
                case .display:
                    displayPane
                case .motion:
                    motionRulesPane
                case .presets:
                    MotionPresetView(store: store, midi: midi, isEmbedded: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 820, height: 560)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(
                            selectedTab == tab ? Color.accentColor.opacity(0.22) : .clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
            Spacer()
        }
        .padding(10)
        .background(.regularMaterial)
    }

    private var connectionCard: some View {
        LabeledContent {
            Button(codex.isConnected ? "연결 종료" : "연결") {
                if codex.isConnected {
                    codex.disconnect()
                } else {
                    codex.connect()
                }
            }
            .tint(codex.isConnected ? .red : .accentColor)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(codex.isConnected ? "연결됨" : "연결 안 됨")
                    Text(codex.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var displayPane: some View {
        Form {
            Section("Codex 연결") {
                connectionCard
            }

            Section("LED 표시") {
                motionDisplayLocation
                weeklyUsageDisplaySetting
            }

            Section("말풍선") {
                launchpadLEDBubbleSetting
            }

            Section("LED 화면보호기") {
                idleScreensaverSetting
            }

            Section {
                Text("이 앱에서 시작한 Codex 작업만 상태·모션으로 추적합니다. 기존 ChatGPT 앱 작업은 포함되지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var motionRulesPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("상태").frame(width: 74, alignment: .leading)
                Text("모션").frame(width: 104, alignment: .leading)
                Text("").frame(width: 58)
                Text("종료 방식").frame(width: 108, alignment: .leading)
                Text("조건").frame(width: 70, alignment: .leading)
                Text("옵션").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 7)

            GroupBox {
                VStack(spacing: 0) {
                    ForEach(Array(motionActivities.enumerated()), id: \.element.id) { index, activity in
                        CodexMotionRuleCard(store: store, midi: midi, activity: activity)
                        if index < motionActivities.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var motionActivities: [CodexActivity] {
        [.connecting, .running, .waitingForApproval, .completed, .failed]
    }

    private var motionDisplayLocation: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("상태 모션 페이지") {
                Picker("Codex 상태 모션 표시 페이지", selection: motionDisplayPageBinding) {
                    ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, page in
                        Text("P\(index + 1) · \(page.name)").tag(page.id)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            Toggle("모션 재생 중에도 기존 패드 LED 유지", isOn: preservesPadLEDsBinding)
                .accessibilityIdentifier("codex-motion-preserve-pad-leds-toggle")
        }
    }

    private var launchpadLEDBubbleSetting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launchpad LED 말풍선 표시", isOn: launchpadLEDBubbleBinding)
                .accessibilityIdentifier("launchpad-led-bubble-toggle")
            LabeledContent("크기") {
                Picker("Launchpad LED 말풍선 크기", selection: launchpadLEDBubbleSizeBinding) {
                    ForEach(LaunchpadLEDBubbleSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                .accessibilityIdentifier("launchpad-led-bubble-size-picker")
            }
            .disabled(!store.codexMotionDisplaySettings.showsLaunchpadLEDBubble)
        }
    }

    private var idleScreensaverSetting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("사용", isOn: idleScreensaverEnabledBinding)
                .accessibilityIdentifier("idle-screensaver-toggle")

            LabeledContent("입력 기준") {
                Picker("화면보호기 입력 기준", selection: idleScreensaverInputScopeBinding) {
                    ForEach(LaunchpadIdleInputScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            LabeledContent("시작 및 재생 시간") {
                HStack(spacing: 6) {
                TextField("초", value: idleScreensaverDelayBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 58)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("화면보호기 시작 대기 시간(초)")
                Text("초 후")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                TextField("초", value: idleScreensaverDurationBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 58)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("화면보호기 지속 시간(초)")
                Text("초 재생")
                    .foregroundStyle(.secondary)
                }
            }

            LabeledContent("재생 모션") {
                Picker("화면보호기 모션", selection: idleScreensaverPresetBinding) {
                    Text("모션 선택").tag(UUID?.none)
                    ForEach(store.motionPresets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            .disabled(!store.codexMotionDisplaySettings.idleScreensaver.isEnabled)
        }
    }

    private var weeklyUsageDisplaySetting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("주간 잔여량 표시", isOn: weeklyUsageEnabledBinding)
                .accessibilityIdentifier("weekly-usage-display-toggle")

            LabeledContent("표시 방식") {
                Picker("주간 잔여량 표시 방식", selection: weeklyUsageStyleBinding) {
                    ForEach(CodexWeeklyUsageDisplayStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            LabeledContent("표시 페이지") {
                Picker("주간 잔여량 표시 페이지", selection: weeklyUsagePageBinding) {
                    ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, page in
                        Text("P\(index + 1) · \(page.name)").tag(page.id)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            .disabled(!store.codexMotionDisplaySettings.weeklyUsageDisplay.isEnabled)
            Text(store.codexMotionDisplaySettings.weeklyUsageDisplay.style == .level
                ? "평소 사용량 표시 · 모션 종료 후 자동 복귀"
                : "0%=0 · 100%=00 · 모션 종료 후 자동 복귀")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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

    private var launchpadLEDBubbleBinding: Binding<Bool> {
        Binding(
            get: { store.codexMotionDisplaySettings.showsLaunchpadLEDBubble },
            set: { store.setLaunchpadLEDBubbleVisible($0) }
        )
    }

    private var launchpadLEDBubbleSizeBinding: Binding<LaunchpadLEDBubbleSize> {
        Binding(
            get: { store.codexMotionDisplaySettings.launchpadLEDBubbleSize },
            set: { store.setLaunchpadLEDBubbleSize($0) }
        )
    }

    private var idleScreensaverEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.codexMotionDisplaySettings.idleScreensaver.isEnabled },
            set: { store.setIdleScreensaverEnabled($0) }
        )
    }

    private var idleScreensaverInputScopeBinding: Binding<LaunchpadIdleInputScope> {
        Binding(
            get: { store.codexMotionDisplaySettings.idleScreensaver.inputScope },
            set: { store.setIdleScreensaverInputScope($0) }
        )
    }

    private var idleScreensaverDelayBinding: Binding<Int> {
        Binding(
            get: { store.codexMotionDisplaySettings.idleScreensaver.delaySeconds },
            set: { store.setIdleScreensaverDelaySeconds($0) }
        )
    }

    private var idleScreensaverPresetBinding: Binding<UUID?> {
        Binding(
            get: { store.codexMotionDisplaySettings.idleScreensaver.presetID },
            set: { store.setIdleScreensaverPresetID($0) }
        )
    }

    private var idleScreensaverDurationBinding: Binding<Int> {
        Binding(
            get: { store.codexMotionDisplaySettings.idleScreensaver.durationSeconds },
            set: { store.setIdleScreensaverDurationSeconds($0) }
        )
    }

    private var weeklyUsageEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.codexMotionDisplaySettings.weeklyUsageDisplay.isEnabled },
            set: { store.setWeeklyUsageDisplayEnabled($0) }
        )
    }

    private var weeklyUsagePageBinding: Binding<UUID> {
        Binding(
            get: { store.codexMotionDisplaySettings.weeklyUsageDisplay.pageID ?? store.pages[0].id },
            set: { store.setWeeklyUsageDisplayPageID($0) }
        )
    }

    private var weeklyUsageStyleBinding: Binding<CodexWeeklyUsageDisplayStyle> {
        Binding(
            get: { store.codexMotionDisplaySettings.weeklyUsageDisplay.style },
            set: { store.setWeeklyUsageDisplayStyle($0) }
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
