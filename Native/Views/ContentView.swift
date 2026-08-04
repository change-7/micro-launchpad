import SwiftUI
import CoreGraphics
import Combine

@MainActor
@Observable
final class CodexMotionActivityRouter {
    private(set) var presentedActivity: CodexActivity = .idle

    func present(
        _ activity: CodexActivity,
        endingCurrentMotion: () -> Void = {},
        using presentation: (CodexActivity) -> Void
    ) {
        endingCurrentMotion()
        presentedActivity = activity
        presentation(activity)
    }

    func dismissalPresentation(
        using resolve: (CodexActivity) -> CodexMotionPresentation
    ) -> CodexMotionPresentation {
        resolve(presentedActivity)
    }
}

struct ContentView: View {
    @Bindable var store: LaunchpadStore
    let runner: MacActionRunner
    let midi: LaunchpadMIDIManager
    let codex: CodexAppServerClient
    let codexActivity: CodexActivityController
    let launchpadLEDBubble: LaunchpadLEDStatusBubble
    @State private var editedPad = Pad(id: "grid_0_0")
    @State private var showingPermissionAlert = false
    @State private var showingMotionPresets = false
    @State private var selectedPageLEDIndex: Int?
    @State private var showingCodexConnection = false
    @State private var virtualPreviewEnabled = true
    @State private var virtualMotion = VirtualMotionPlayer()
    @State private var codexMotionActivity = CodexMotionActivityRouter()
    @State private var codexMotionStopWorkItem: DispatchWorkItem?
    @State private var isCodexMotionPlaying = false
    @State private var lastLaunchpadOrCodexActivity = Date()
    @State private var idleScreensaverSessionID: UUID?
    @State private var idleScreensaverStopWorkItem: DispatchWorkItem?
    private let idleScreensaverTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    private let weeklyUsageRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.035, blue: 0.045).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    PageQuickSwitchView(pages: store.pages, activePage: store.selectedPage, midiConnected: midi.isConnected, codexConnected: codex.isConnected, onSelect: selectPage, onOpenMotionPresets: { showingMotionPresets = true }, onOpenCodex: { showingCodexConnection = true })
                    HStack(alignment: .top, spacing: 28) {
                        InspectorView(pad: $editedPad, pages: store.pages, selectedPageLEDIndex: selectedPageLEDIndex, onSelectPageLED: { selectedPageLEDIndex = $0 }, onUpdatePageColor: { index, color, selected in
                            store.updatePageColor(color, selected: selected, at: index)
                        }, onUpdatePageName: { index, name in
                            store.updatePageName(name, at: index)
                        }, onReset: {
                            store.resetSelectedPad()
                            synchronizeSelection()
                        }, onRun: { run(editedPad) })
                        .frame(width: 360)
                        .frame(minHeight: 600)

                        LaunchpadView(page: store.currentPage, pages: store.pages, activePage: store.selectedPage, selectedPadID: store.selectedPadID, midiConnected: midi.isConnected, virtualPreviewEnabled: $virtualPreviewEnabled, motionFrame: virtualMotion.frame, gridOverlay: weeklyUsageGridColors, onSelectPage: selectPage, onSelectPageLED: { selectedPageLEDIndex = $0 }, onSelectPad: selectPad, onRunPad: run, onVirtualPadPress: virtualPadPress)
                            .frame(minWidth: 610, minHeight: 620)
                    }
                }
                .frame(maxWidth: 1120)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .frame(minWidth: 1100, minHeight: 820)
        .onAppear {
            midi.onPagePressed = { index in
                recordLaunchpadOrCodexActivity()
                selectPage(index)
            }
            midi.onPadPressed = handleHardwarePadPress
            synchronizeSelection()
            midi.updateLEDs(for: store.pages, activePage: store.selectedPage)
            synchronizeWeeklyUsageDisplay()
            codex.refreshWeeklyUsage()
            launchpadLEDBubble.update(midi: midi, store: store)
        }
        .onReceive(idleScreensaverTimer) { _ in evaluateIdleScreensaver() }
        .onReceive(weeklyUsageRefreshTimer) { _ in codex.refreshWeeklyUsage() }
        .onChange(of: editedPad) { _, pad in store.update(pad) }
        .onChange(of: store.selectedPage) { _, _ in
            midi.updateLEDs(for: store.pages, activePage: store.selectedPage)
            virtualMotion.updateUnderlyingPage(store.currentPage)
            synchronizeWeeklyUsageDisplay()
        }
        .onChange(of: store.pages) { _, _ in
            midi.updateLEDs(for: store.pages, activePage: store.selectedPage)
            virtualMotion.updateUnderlyingPage(store.currentPage)
            synchronizeWeeklyUsageDisplay()
        }
        .onChange(of: store.codexMotionDisplaySettings) { _, _ in
            if !store.shouldPresentCodexMotion(on: store.currentPage) {
                endCodexMotion()
            }
            synchronizeWeeklyUsageDisplay()
            launchpadLEDBubble.update(midi: midi, store: store)
        }
        .onChange(of: codex.weeklyUsage, initial: true) { _, _ in
            synchronizeWeeklyUsageDisplay()
        }
        .onChange(of: store.codexMotionDisplaySettings.idleScreensaver) { _, _ in
            stopIdleScreensaver()
            lastLaunchpadOrCodexActivity = Date()
        }
        .onChange(of: codex.activity, initial: true) { _, activity in
            codexActivity.updateAppServerActivity(activity)
        }
        .onChange(of: codexActivity.activity, initial: true) { _, activity in
            recordLaunchpadOrCodexActivity()
            codexMotionActivity.present(
                activity,
                endingCurrentMotion: endCodexMotion,
                using: startCodexMotion
            )
        }
        .safeAreaInset(edge: .bottom) { footer }
        .alert("손쉬운 사용 권한", isPresented: $showingPermissionAlert) {
            Button("설정 열기") { runner.requestAccessibilityPermission() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("macOS 단축키를 실행하려면 이 앱을 손쉬운 사용에 허용하세요.")
        }
        .sheet(isPresented: $showingMotionPresets) {
            MotionPresetView(store: store, midi: midi)
        }
        .sheet(isPresented: $showingCodexConnection) {
            CodexConnectionView(
                store: store,
                midi: midi,
                codex: codex
            )
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 7) { Circle().fill(midi.isConnected ? .green : .gray).frame(width: 7, height: 7); Text(store.statusMessage) }
            Spacer()
            Button("단축키 권한") { showingPermissionAlert = true }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 26)
        .frame(height: 34)
        .background(Color(red: 0.065, green: 0.065, blue: 0.08))
    }

    private func selectPage(_ index: Int) {
        dismissCodexMotionIfNeeded(for: "top_\(index)")
        selectedPageLEDIndex = nil
        store.selectPage(index)
        if !store.shouldPresentCodexMotion(on: store.currentPage) {
            endCodexMotion()
        }
        synchronizeSelection()
        midi.flashPage(index, pages: store.pages)
    }

    private func selectPad(_ pad: Pad) {
        selectedPageLEDIndex = nil
        store.selectedPadID = pad.id
        synchronizeSelection()
    }

    private func run(_ pad: Pad) {
        do { store.statusMessage = try runner.execute(pad.action) }
        catch MacActionError.accessibilityRequired {
            store.statusMessage = MacActionError.accessibilityRequired.localizedDescription
            showingPermissionAlert = true
        }
        catch { store.statusMessage = error.localizedDescription }
    }

    private func handleHardwarePadPress(_ padID: String) {
        recordLaunchpadOrCodexActivity()
        dismissCodexMotionIfNeeded(for: padID)
        selectedPageLEDIndex = nil
        guard let pad = store.currentPage.pads.first(where: { $0.id == padID }) else { return }
        store.selectedPadID = padID
        synchronizeSelection()
        midi.flash(pad)
        run(pad)
    }

    private func virtualPadPress(_ pad: Pad) {
        dismissCodexMotionIfNeeded(for: pad.id)
        selectedPageLEDIndex = nil
        store.selectedPadID = pad.id
        synchronizeSelection()
    }

    private func synchronizeSelection() {
        editedPad = store.selectedPad ?? Pad(id: store.selectedPadID)
    }

    private func startCodexMotion(for activity: CodexActivity) {
        stopIdleScreensaver(restorePage: false)
        guard activity != .idle,
              store.shouldPresentCodexMotion(on: store.currentPage),
              let preset = store.codexMotionPreset(for: activity) else { return }
        let presentation = store.codexMotionPresentation(for: activity)
        let loopingPreset = MotionPreset(name: preset.name, loop: true, frameDurationMs: preset.frameDurationMs, frames: preset.frames)
        isCodexMotionPlaying = true
        midi.playMotion(
            loopingPreset,
            preservingPadLEDs: store.shouldPreservePadLEDsDuringCodexMotion(for: activity)
        )
        virtualMotion.play(
            loopingPreset,
            over: store.currentPage,
            preservingPadLEDs: store.shouldPreservePadLEDsDuringCodexMotion(for: activity)
        )

        guard let delay = presentation.automaticStopDelay(for: activity) else { return }
        let workItem = DispatchWorkItem { endCodexMotion() }
        codexMotionStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func dismissCodexMotionIfNeeded(for padID: String) {
        let presentation = codexMotionActivity.dismissalPresentation(using: store.codexMotionPresentation)
        if presentation.shouldDismiss(for: padID) {
            endCodexMotion()
        }
    }

    private func endCodexMotion() {
        codexMotionStopWorkItem?.cancel()
        codexMotionStopWorkItem = nil
        isCodexMotionPlaying = false
        midi.stopMotion()
        virtualMotion.stop()
        lastLaunchpadOrCodexActivity = Date()
    }

    private func recordLaunchpadOrCodexActivity() {
        lastLaunchpadOrCodexActivity = Date()
        stopIdleScreensaver()
    }

    private var weeklyUsageGridColors: [String]? {
        let settings = store.codexMotionDisplaySettings.weeklyUsageDisplay
        guard settings.isEnabled,
              settings.allowsPresentation(on: store.currentPage.id),
              let weeklyUsage = codex.weeklyUsage else { return nil }
        let remainingCellCount = CodexWeeklyUsageGrid.remainingCellCount(usedPercent: weeklyUsage.usedPercent)
        let activeColor = CodexWeeklyUsageGrid.color(forUsedPercent: weeklyUsage.usedPercent).rawValue
        return (0..<64).map {
            CodexWeeklyUsageGrid.isRemainingCellActive(index: $0, remainingCellCount: remainingCellCount)
                ? activeColor
                : PadColor.off.rawValue
        }
    }

    private func synchronizeWeeklyUsageDisplay() {
        guard let colors = weeklyUsageGridColors else {
            midi.setGridOverlay(colors: nil)
            return
        }
        midi.setGridOverlay(colors: colors.compactMap(PadColor.init(rawValue:)))
    }

    private func evaluateIdleScreensaver() {
        let settings = store.codexMotionDisplaySettings.idleScreensaver
        let launchpadAndCodexIdleSeconds = Date().timeIntervalSince(lastLaunchpadOrCodexActivity)
        let macIdleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: UInt32.max)!
        )
        let shouldPlay = LaunchpadIdleScreensaverPolicy.shouldPlay(
            settings: settings,
            hasPreset: store.idleScreensaverPreset != nil,
            codexIsBusy: codexIsBusy,
            launchpadAndCodexIdleSeconds: launchpadAndCodexIdleSeconds,
            macIdleSeconds: macIdleSeconds
        )

        if shouldPlay {
            startIdleScreensaverIfNeeded()
        } else {
            stopIdleScreensaver()
        }
    }

    private func startIdleScreensaverIfNeeded() {
        guard idleScreensaverSessionID == nil,
              let preset = store.idleScreensaverPreset else { return }
        let loopingPreset = MotionPreset(
            name: preset.name,
            loop: true,
            frameDurationMs: preset.frameDurationMs,
            frames: preset.frames
        )
        let sessionID = midi.playMotion(loopingPreset)
        idleScreensaverSessionID = sessionID
        virtualMotion.play(loopingPreset, over: store.currentPage, preservingPadLEDs: false)

        let duration = store.codexMotionDisplaySettings.idleScreensaver.clampedDurationSeconds
        let workItem = DispatchWorkItem {
            guard idleScreensaverSessionID == sessionID else { return }
            stopIdleScreensaver()
            lastLaunchpadOrCodexActivity = Date()
        }
        idleScreensaverStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(duration), execute: workItem)
    }

    private func stopIdleScreensaver(restorePage: Bool = true) {
        idleScreensaverStopWorkItem?.cancel()
        idleScreensaverStopWorkItem = nil
        guard let sessionID = idleScreensaverSessionID else { return }
        idleScreensaverSessionID = nil
        midi.stopMotion(ifCurrent: sessionID, restorePage: restorePage)
        virtualMotion.stop()
    }

    private var codexIsBusy: Bool {
        if isCodexMotionPlaying { return true }
        return switch codexActivity.activity {
        case .connecting, .running, .waitingForApproval: true
        case .idle, .completed, .failed: false
        }
    }
}

private struct PageQuickSwitchView: View {
    let pages: [LaunchPage]
    let activePage: Int
    let midiConnected: Bool
    let codexConnected: Bool
    let onSelect: (Int) -> Void
    let onOpenMotionPresets: () -> Void
    let onOpenCodex: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "square.3.layers.3d").foregroundStyle(.orange).frame(width: 22, height: 22).background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                Text("페이지 퀵 스위처").font(.system(size: 14, weight: .bold))
                Text("(TOP CC 1~8 연동)").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button(action: onOpenMotionPresets) {
                    Label("모션 프리셋", systemImage: "sparkles.square.filled.on.square")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                Button(action: onOpenCodex) {
                    Label("Codex", systemImage: "cpu")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                Circle().fill(codexConnected ? .green : .gray).frame(width: 7, height: 7)
                Circle().fill(midiConnected ? .green : .gray).frame(width: 7, height: 7)
            }
            .foregroundStyle(.white)

            HStack(spacing: 10) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    Button { onSelect(index) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("P\(index + 1)").foregroundStyle(.orange)
                                Text("CC\(104 + index)").foregroundStyle(.secondary)
                                Spacer()
                                let count = page.pads.filter { $0.action.kind != .none }.count
                                if count > 0 { Text("\(count)").padding(.horizontal, 6).padding(.vertical, 2).background(.white.opacity(0.10), in: Capsule()) }
                            }
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            Text(page.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(11)
                        .foregroundStyle(.white.opacity(index == activePage ? 1 : 0.72))
                        .background(index == activePage ? Color(red: 0.11, green: 0.11, blue: 0.14) : Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(index == activePage ? Color.orange : .white.opacity(0.12), lineWidth: index == activePage ? 1.5 : 1))
                        .shadow(color: index == activePage ? .orange.opacity(0.24) : .clear, radius: 9)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }

        }
        .padding(14)
        .background(Color(red: 0.065, green: 0.065, blue: 0.08), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12)))
    }

}
