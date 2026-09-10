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

private enum MainScreen: Hashable {
    case launchpadMini
    case smartphoneButtons
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
    @State private var selectedPageLEDIndex: Int?
    @State private var showingCodexConnection = false
    @State private var selectedMainScreen: MainScreen = .launchpadMini
    private let launchpadPanelHeight: CGFloat = 620
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
            launchpadContent
        }
        .frame(minWidth: 1100, minHeight: 820)
        .onAppear {
            midi.onPagePressed = { index in
                recordLaunchpadOrCodexActivity()
                selectPage(index)
            }
            midi.onPadPressed = handleHardwarePadPress
            launchpadLEDBubble.onSelectPage = { index in
                selectPage(index)
            }
            codex.setRemoteSmartphonePagesProvider { SmartphoneDefaults.persistedPages() }
            synchronizeSelection()
            midi.updateLEDs(for: store.pages, activePage: store.selectedPage)
            synchronizeWeeklyUsageDisplay()
            codex.refreshWeeklyUsage()
            updateStatusBubble()
        }
        .onReceive(idleScreensaverTimer) { _ in evaluateIdleScreensaver() }
        .onReceive(weeklyUsageRefreshTimer) { _ in codex.refreshWeeklyUsage() }
        .onChange(of: editedPad) { _, pad in store.update(pad) }
        .onChange(of: store.selectedPage) { _, _ in
            midi.updateLEDs(for: store.pages, activePage: store.selectedPage)
            virtualMotion.updateUnderlyingPage(store.currentPage)
            synchronizeWeeklyUsageDisplay()
            resumeCodexMotionForCurrentPageIfNeeded()
        }
        .onChange(of: store.pages) { _, _ in
            midi.updateLEDs(for: store.pages, activePage: store.selectedPage)
            virtualMotion.updateUnderlyingPage(store.currentPage)
            synchronizeWeeklyUsageDisplay()
        }
        .onChange(of: store.smartphonePages) { _, _ in
            codex.publishRemoteState()
        }
        .onChange(of: store.codexMotionDisplaySettings) { _, _ in
            if !store.shouldPresentCodexMotion(on: store.currentPage) {
                endCodexMotion()
            }
            synchronizeWeeklyUsageDisplay()
            updateStatusBubble()
        }
        .onChange(of: codex.weeklyUsage, initial: true) { _, _ in
            synchronizeWeeklyUsageDisplay()
            updateStatusBubble()
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
        .sheet(isPresented: $showingCodexConnection) {
            CodexConnectionView(
                store: store,
                midi: midi,
                codex: codex
            )
        }
    }

    private var launchpadContent: some View {
        VStack(spacing: 18) {
            launchpadToolbar
            switch selectedMainScreen {
            case .launchpadMini:
                launchpadMiniContent
            case .smartphoneButtons:
                SmartphoneSettingsView(store: store, runner: runner)
                    .frame(minWidth: 900, minHeight: 680)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private var launchpadMiniContent: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                InspectorView(
                    pad: $editedPad,
                    pages: store.pages,
                    selectedPageLEDIndex: selectedPageLEDIndex,
                    onSelectPageLED: { selectedPageLEDIndex = $0 },
                    onUpdatePageColor: { index, color, selected in
                        store.updatePageColor(color, selected: selected, at: index)
                    },
                    onUpdatePageName: { index, name in store.updatePageName(name, at: index) },
                    onReset: {
                        if editedPad.id.hasPrefix("grid_") {
                            deleteGridPad(editedPad.id)
                        } else {
                            store.resetSelectedPad()
                            synchronizeSelection()
                        }
                    },
                    onRun: { run(editedPad) }
                )
                .frame(width: 360, height: launchpadPanelHeight)

                LaunchpadView(
                    page: store.currentPage,
                    pages: store.pages,
                    activePage: store.selectedPage,
                    selectedPadID: store.selectedPadID,
                    midiConnected: midi.isConnected,
                    virtualPreviewEnabled: $virtualPreviewEnabled,
                    motionFrame: virtualMotion.frame,
                    gridOverlay: weeklyUsageGridColors,
                    onSelectPage: selectPage,
                    onSelectPageLED: { selectedPageLEDIndex = $0 },
                    onSelectPad: selectPad,
                    onRunPad: run,
                    onVirtualPadPress: virtualPadPress,
                    onMoveGridPad: moveGridPad
                )
                .frame(minWidth: 610)
                .frame(height: launchpadPanelHeight)
            }
            .frame(maxWidth: 1120)
            .frame(height: launchpadPanelHeight, alignment: .top)
        }
    }

    private var launchpadToolbar: some View {
        ZStack {
            HStack(spacing: 4) {
                mainScreenButton(
                    .launchpadMini,
                    title: "런치패드 미니",
                    systemImage: "square.grid.3x3"
                )
                mainScreenButton(
                    .smartphoneButtons,
                    title: "휴대폰",
                    systemImage: "iphone"
                )
            }
            .padding(3)
            .background(.regularMaterial.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.10)))
            .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("화면 모드 선택")

            HStack(spacing: 9) {
                Spacer()
                Button { showingCodexConnection = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 28)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Codex 설정")
                Circle().fill(codex.isConnected ? .green : .gray).frame(width: 7, height: 7)
                Circle().fill(midi.isConnected ? .green : .gray).frame(width: 7, height: 7)
            }
        }
        .frame(maxWidth: 1120)
        .foregroundStyle(.white)
        .offset(y: -24)
    }

    private func mainScreenButton(
        _ screen: MainScreen,
        title: String,
        systemImage: String
    ) -> some View {
        Button { selectedMainScreen = screen } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 118, height: 32)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(selectedMainScreen == screen ? .white : .white.opacity(0.65))
            .background(
                selectedMainScreen == screen ? Color.orange.opacity(0.22) : .clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selectedMainScreen == screen ? Color.orange.opacity(0.72) : .clear)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .accessibilityLabel(title)
        .help(title)
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
        .background(Color(red: 0.035, green: 0.035, blue: 0.045))
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

    private func moveGridPad(from sourceID: String, to destinationID: String) {
        guard store.swapGridPadConfigurations(from: sourceID, to: destinationID) else { return }
        selectedPageLEDIndex = nil
        synchronizeSelection()
        midi.updateLEDs(for: store.pages, activePage: store.selectedPage)
        updateStatusBubble()
    }

    private func deleteGridPad(_ padID: String) {
        guard store.clearGridPadConfiguration(padID) else { return }
        store.selectedPadID = padID
        selectedPageLEDIndex = nil
        synchronizeSelection()
        midi.updateLEDs(for: store.pages, activePage: store.selectedPage)
        updateStatusBubble()
    }

    private func run(_ pad: Pad) {
        let commandFileID = TerminalCommandFileStore.macButtonIdentifier(pageIndex: store.selectedPage, padID: pad.id)
        do { store.statusMessage = try runner.execute(pad.action, commandFileID: commandFileID) }
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
              store.shouldPresentCodexMotion(on: store.currentPage) else { return }
        let presentation = store.codexMotionPresentation(for: activity)
        guard let preset = store.codexMotionPreset(for: activity) else { return }
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

        scheduleCodexMotionStop(using: presentation, activity: activity)
    }

    private func scheduleCodexMotionStop(using presentation: CodexMotionPresentation, activity: CodexActivity) {
        guard let delay = presentation.automaticStopDelay(for: activity) else { return }
        let workItem = DispatchWorkItem { endCodexMotion() }
        codexMotionStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func resumeCodexMotionForCurrentPageIfNeeded() {
        guard !isCodexMotionPlaying,
              CodexMotionReentryPolicy.shouldRestart(for: codexActivity.activity),
              store.shouldPresentCodexMotion(on: store.currentPage) else { return }
        startCodexMotion(for: codexActivity.activity)
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
        synchronizeWeeklyUsageDisplay()
        updateStatusBubble()
        lastLaunchpadOrCodexActivity = Date()
    }

    private func updateStatusBubble() {
        launchpadLEDBubble.update(midi: midi, store: store)
    }

    private func recordLaunchpadOrCodexActivity() {
        lastLaunchpadOrCodexActivity = Date()
        stopIdleScreensaver()
    }

    private var weeklyUsageGridColors: [String]? {
        let settings = store.codexMotionDisplaySettings.weeklyUsageDisplay
        guard settings.isEnabled,
              !isCodexMotionPlaying,
              settings.allowsPresentation(on: store.currentPage.id),
              let weeklyUsage = codex.weeklyUsage else { return nil }
        let remainingCellCount = CodexWeeklyUsageGrid.remainingCellCount(usedPercent: weeklyUsage.usedPercent)
        let activeColor = CodexWeeklyUsageGrid.color(forUsedPercent: weeklyUsage.usedPercent).rawValue
        let activePixels: [Bool]
        switch settings.style {
        case .level:
            activePixels = (0..<64).map {
                CodexWeeklyUsageGrid.isRemainingCellActive(index: $0, remainingCellCount: remainingCellCount)
            }
        case .number:
            activePixels = CodexWeeklyUsageGrid.numericPixels(remainingPercent: 100 - weeklyUsage.usedPercent)
        }
        return activePixels.map { $0 ? activeColor : PadColor.off.rawValue }
    }

    private func synchronizeWeeklyUsageDisplay() {
        guard let colors = weeklyUsageGridColors else {
            midi.setGridOverlay(colors: nil)
            return
        }
        midi.setGridOverlay(colors: colors.compactMap(PadColor.init(rawValue:)))
    }

    private func evaluateIdleScreensaver() {
        // A live Codex task can remain `.running` while no new status event is
        // emitted during file reads or tool execution. Recover the visual
        // motion if it was interrupted by page changes or a transient update.
        resumeCodexMotionForCurrentPageIfNeeded()
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
