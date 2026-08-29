import Foundation
import Observation

@Observable
final class LaunchpadStore {
    private let preferences = UserDefaults(suiteName: "com.pdg.chatgpt-micro-launchpad.native") ?? .standard
    private let storageKey = "chatgpt-micro-launchpad.pages"
    private let motionStorageKey = "chatgpt-micro-launchpad.motion-presets"
    private let codexMotionStorageKey = "chatgpt-micro-launchpad.codex-motion-bindings"
    private let codexMotionPresentationStorageKey = "chatgpt-micro-launchpad.codex-motion-presentations"
    private let codexMotionDisplaySettingsStorageKey = "chatgpt-micro-launchpad.codex-motion-display-settings"
    private let sideButtonDefaultsMigrationKey = "chatgpt-micro-launchpad.side-button-defaults-v2"
    private let sideButtonCategoryOrderMigrationKey = "chatgpt-micro-launchpad.side-button-category-order-v3"
    private let sortedSideButtonDefaultsMigrationKey = "chatgpt-micro-launchpad.sorted-side-button-defaults-v4"
    var pages: [LaunchPage]
    var smartphonePages: [SmartphonePage]
    var motionPresets: [MotionPreset]
    var codexMotionPresetIDs: [String: UUID]
    var codexMotionPresentations: [String: CodexMotionPresentation]
    var codexMotionDisplaySettings: CodexMotionDisplaySettings
    var selectedPage = 0
    var selectedPadID = "grid_0_0"
    var statusMessage = "패드를 선택해 설정하세요."

    init() {
        let needsSideButtonMigration = !preferences.bool(forKey: sideButtonDefaultsMigrationKey)
        let needsSideButtonCategoryOrdering = !preferences.bool(forKey: sideButtonCategoryOrderMigrationKey)
        let needsSortedSideButtonDefaults = !preferences.bool(forKey: sortedSideButtonDefaultsMigrationKey)
        var loadedPages: [LaunchPage]
        if let data = preferences.data(forKey: storageKey), let savedPages = try? JSONDecoder().decode([LaunchPage].self, from: data), savedPages.count == 8 {
            loadedPages = savedPages.map(PadDefaults.normalized)
        } else {
            loadedPages = PadDefaults.pages()
        }
        if needsSideButtonMigration {
            loadedPages = PadDefaults.applyingDefaultSideActions(to: loadedPages)
        }
        if needsSideButtonCategoryOrdering {
            loadedPages = PadDefaults.applyingSideButtonCategoryOrder(to: loadedPages)
        }
        if needsSortedSideButtonDefaults {
            loadedPages = PadDefaults.applyingSortedSideButtonDefaults(to: loadedPages)
        }
        let commonSideButtonPages = PadDefaults.applyingCommonSideButtons(to: loadedPages)
        let didSynchronizeCommonSideButtons = commonSideButtonPages != loadedPages
        loadedPages = commonSideButtonPages
        pages = loadedPages
        smartphonePages = SmartphoneDefaults.persistedPages(from: preferences)
        motionPresets = (try? preferences.data(forKey: motionStorageKey)
            .flatMap { try JSONDecoder().decode([MotionPreset].self, from: $0) }) ?? []
        let savedPresetIDs = (try? preferences.data(forKey: codexMotionStorageKey)
            .flatMap { try JSONDecoder().decode([String: UUID].self, from: $0) }) ?? [:]
        codexMotionPresetIDs = savedPresetIDs
        let loadedPresentations: [String: CodexMotionPresentation]
        if let data = preferences.data(forKey: codexMotionPresentationStorageKey),
           let saved = try? JSONDecoder().decode([String: CodexMotionPresentation].self, from: data) {
            loadedPresentations = saved
        } else {
            loadedPresentations = savedPresetIDs.reduce(into: [:]) { result, entry in
                result[entry.key] = CodexMotionPresentation(presetID: entry.value)
            }
        }
        codexMotionPresentations = loadedPresentations
        let restoredDisplaySettings = CodexMotionDisplaySettings.restored(
            from: preferences.data(forKey: codexMotionDisplaySettingsStorageKey),
            legacyPresentations: loadedPresentations
        )
        codexMotionDisplaySettings = restoredDisplaySettings.settings
        if needsSideButtonMigration
            || needsSideButtonCategoryOrdering
            || needsSortedSideButtonDefaults
            || didSynchronizeCommonSideButtons {
            if needsSideButtonMigration {
                preferences.set(true, forKey: sideButtonDefaultsMigrationKey)
            }
            if needsSideButtonCategoryOrdering {
                preferences.set(true, forKey: sideButtonCategoryOrderMigrationKey)
            }
            if needsSortedSideButtonDefaults {
                preferences.set(true, forKey: sortedSideButtonDefaultsMigrationKey)
            }
            save()
        }
        if restoredDisplaySettings.didMigrateLegacyPreservation {
            saveCodexMotionDisplaySettings()
        }
    }

    var currentPage: LaunchPage { pages[selectedPage] }
    var selectedPad: Pad? { currentPage.pads.first { $0.id == selectedPadID } }
    func selectPage(_ index: Int) {
        selectedPage = index
        selectedPadID = "grid_0_0"
    }

    func update(_ pad: Pad) {
        if pad.id.hasPrefix("side_") {
            pages = PadDefaults.updatingCommonSideButton(pad, in: pages)
            save()
            return
        }
        guard let index = pages[selectedPage].pads.firstIndex(where: { $0.id == pad.id }) else { return }
        pages[selectedPage].pads[index] = pad
        save()
    }

    func updateSmartphoneButton(_ button: SmartphoneButton, at pageIndex: Int) {
        guard smartphonePages.indices.contains(pageIndex),
              let buttonIndex = smartphonePages[pageIndex].buttons.firstIndex(where: { $0.id == button.id }) else { return }
        smartphonePages[pageIndex].buttons[buttonIndex] = button
        saveSmartphonePages()
    }

    func updateSmartphonePageName(_ name: String, at pageIndex: Int) {
        guard smartphonePages.indices.contains(pageIndex) else { return }
        smartphonePages[pageIndex].name = name
        saveSmartphonePages()
    }

    func resetSmartphoneButton(pageIndex: Int, buttonIndex: Int) {
        guard smartphonePages.indices.contains(pageIndex),
              smartphonePages[pageIndex].buttons.indices.contains(buttonIndex) else { return }
        smartphonePages[pageIndex].buttons[buttonIndex] = SmartphoneDefaults.defaultButton(
            pageIndex: pageIndex,
            buttonIndex: buttonIndex
        )
        saveSmartphonePages()
    }

    @discardableResult
    func swapGridPadConfigurations(from sourceID: String, to destinationID: String) -> Bool {
        guard pages.indices.contains(selectedPage),
              pages[selectedPage].swapGridPadConfigurations(from: sourceID, to: destinationID) else {
            return false
        }

        if selectedPadID == sourceID {
            selectedPadID = destinationID
        } else if selectedPadID == destinationID {
            selectedPadID = sourceID
        }
        statusMessage = "버튼 위치를 변경했습니다."
        save()
        return true
    }

    @discardableResult
    func clearGridPadConfiguration(_ padID: String) -> Bool {
        guard pages.indices.contains(selectedPage),
              pages[selectedPage].clearGridPadConfiguration(padID) else { return false }
        statusMessage = "버튼 설정을 삭제했습니다."
        save()
        return true
    }

    func updatePageColor(_ color: String, selected: Bool, at index: Int) {
        guard pages.indices.contains(index) else { return }
        if selected {
            pages[index].pageActiveColor = PadColor(rawValue: color)?.rawValue ?? "off"
        } else {
            pages[index].pageIdleColor = PadColor(rawValue: color)?.rawValue ?? "off"
        }
        save()
    }

    func updatePageName(_ name: String, at index: Int) {
        guard pages.indices.contains(index) else { return }
        pages[index].name = name
        save()
    }

    func resetSelectedPad() {
        update(PadDefaults.defaultPad(for: selectedPadID))
    }

    func save() {
        guard let data = try? JSONEncoder().encode(pages) else { return }
        preferences.set(data, forKey: storageKey)
    }

    private func saveSmartphonePages() {
        SmartphoneDefaults.persist(smartphonePages, to: preferences)
    }

    func saveMotionPresets() {
        guard let data = try? JSONEncoder().encode(motionPresets) else { return }
        preferences.set(data, forKey: motionStorageKey)
    }

    func addMotionPreset(_ preset: MotionPreset) {
        motionPresets.removeAll { $0.name.localizedCaseInsensitiveCompare(preset.name) == .orderedSame }
        motionPresets.insert(preset, at: 0)
        saveMotionPresets()
    }

    func removeMotionPreset(_ preset: MotionPreset) {
        motionPresets.removeAll { $0.id == preset.id }
        codexMotionPresetIDs = codexMotionPresetIDs.filter { $0.value != preset.id }
        codexMotionPresentations = codexMotionPresentations.mapValues { presentation in
            var updated = presentation
            if updated.presetID == preset.id { updated.presetID = nil }
            return updated
        }
        if codexMotionDisplaySettings.idleScreensaver.presetID == preset.id {
            codexMotionDisplaySettings.idleScreensaver.presetID = nil
            saveCodexMotionDisplaySettings()
        }
        saveMotionPresets()
        saveCodexMotionBindings()
        saveCodexMotionPresentations()
    }

    @discardableResult
    func renameMotionPreset(id: UUID, to name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = motionPresets.firstIndex(where: { $0.id == id }) else { return false }
        motionPresets[index].name = trimmedName
        saveMotionPresets()
        return true
    }

    func codexMotionPresetID(for activity: CodexActivity) -> UUID? {
        codexMotionPresentations[activity.rawValue]?.presetID ?? codexMotionPresetIDs[activity.rawValue]
    }

    func codexMotionPreset(for activity: CodexActivity) -> MotionPreset? {
        guard let id = codexMotionPresetID(for: activity) else { return nil }
        return motionPresets.first { $0.id == id }
    }

    func setCodexMotionPresetID(_ id: UUID?, for activity: CodexActivity) {
        var presentation = codexMotionPresentation(for: activity)
        presentation.presetID = id
        codexMotionPresentations[activity.rawValue] = presentation
        codexMotionPresetIDs[activity.rawValue] = id
        if id == nil { codexMotionPresetIDs.removeValue(forKey: activity.rawValue) }
        saveCodexMotionBindings()
        saveCodexMotionPresentations()
    }

    func codexMotionPresentation(for activity: CodexActivity) -> CodexMotionPresentation {
        codexMotionPresentations[activity.rawValue] ?? CodexMotionPresentation(presetID: codexMotionPresetIDs[activity.rawValue])
    }

    func setCodexMotionPresentation(_ presentation: CodexMotionPresentation, for activity: CodexActivity) {
        codexMotionPresentations[activity.rawValue] = presentation
        if let id = presentation.presetID { codexMotionPresetIDs[activity.rawValue] = id }
        else { codexMotionPresetIDs.removeValue(forKey: activity.rawValue) }
        saveCodexMotionBindings()
        saveCodexMotionPresentations()
    }

    func setCodexMotionDisplayScope(_: CodexMotionDisplayScope) {
        codexMotionDisplaySettings.scope = .specificPage
        saveCodexMotionDisplaySettings()
    }

    func setCodexMotionDisplayPageID(_ pageID: UUID) {
        codexMotionDisplaySettings.pageID = pageID
        codexMotionDisplaySettings.scope = .specificPage
        saveCodexMotionDisplaySettings()
    }

    func setCodexMotionPreservesPadLEDsDuringMotion(_ preservesPadLEDs: Bool) {
        codexMotionDisplaySettings.preservesPadLEDsDuringMotion = preservesPadLEDs
        saveCodexMotionDisplaySettings()
    }

    func setLaunchpadLEDBubbleVisible(_ isVisible: Bool) {
        codexMotionDisplaySettings.showsLaunchpadLEDBubble = isVisible
        saveCodexMotionDisplaySettings()
    }

    func setLaunchpadLEDBubbleSize(_ size: LaunchpadLEDBubbleSize) {
        codexMotionDisplaySettings.launchpadLEDBubbleSize = size
        saveCodexMotionDisplaySettings()
    }

    func setLaunchpadLEDBubbleOrigin(_ origin: CGPoint) {
        codexMotionDisplaySettings.launchpadLEDBubbleOriginX = origin.x
        codexMotionDisplaySettings.launchpadLEDBubbleOriginY = origin.y
        saveCodexMotionDisplaySettings()
    }

    func setIdleScreensaverEnabled(_ isEnabled: Bool) {
        codexMotionDisplaySettings.idleScreensaver.isEnabled = isEnabled
        saveCodexMotionDisplaySettings()
    }

    func setIdleScreensaverInputScope(_ scope: LaunchpadIdleInputScope) {
        codexMotionDisplaySettings.idleScreensaver.inputScope = scope
        saveCodexMotionDisplaySettings()
    }

    func setIdleScreensaverDelaySeconds(_ seconds: Int) {
        codexMotionDisplaySettings.idleScreensaver.delaySeconds = min(
            max(seconds, LaunchpadIdleScreensaverSettings.minimumDelaySeconds),
            LaunchpadIdleScreensaverSettings.maximumDelaySeconds
        )
        saveCodexMotionDisplaySettings()
    }

    func setIdleScreensaverDurationSeconds(_ seconds: Int) {
        codexMotionDisplaySettings.idleScreensaver.durationSeconds = min(
            max(seconds, LaunchpadIdleScreensaverSettings.minimumDurationSeconds),
            LaunchpadIdleScreensaverSettings.maximumDurationSeconds
        )
        saveCodexMotionDisplaySettings()
    }

    func setIdleScreensaverPresetID(_ presetID: UUID?) {
        codexMotionDisplaySettings.idleScreensaver.presetID = presetID
        saveCodexMotionDisplaySettings()
    }

    func setWeeklyUsageDisplayEnabled(_ isEnabled: Bool) {
        codexMotionDisplaySettings.weeklyUsageDisplay.isEnabled = isEnabled
        saveCodexMotionDisplaySettings()
    }

    func setWeeklyUsageDisplayScope(_: CodexMotionDisplayScope) {
        codexMotionDisplaySettings.weeklyUsageDisplay.scope = .specificPage
        saveCodexMotionDisplaySettings()
    }

    func setWeeklyUsageDisplayPageID(_ pageID: UUID) {
        codexMotionDisplaySettings.weeklyUsageDisplay.pageID = pageID
        codexMotionDisplaySettings.weeklyUsageDisplay.scope = .specificPage
        saveCodexMotionDisplaySettings()
    }

    func setWeeklyUsageDisplayStyle(_ style: CodexWeeklyUsageDisplayStyle) {
        codexMotionDisplaySettings.weeklyUsageDisplay.style = style
        saveCodexMotionDisplaySettings()
    }

    var idleScreensaverPreset: MotionPreset? {
        guard let presetID = codexMotionDisplaySettings.idleScreensaver.presetID else { return nil }
        return motionPresets.first { $0.id == presetID }
    }

    func shouldPreservePadLEDsDuringCodexMotion(for activity: CodexActivity) -> Bool {
        codexMotionDisplaySettings.shouldPreservePadLEDsDuringMotion(for: activity)
    }

    func shouldPresentCodexMotion(on page: LaunchPage) -> Bool {
        codexMotionDisplaySettings.allowsPresentation(on: page.id)
    }

    private func saveCodexMotionBindings() {
        guard let data = try? JSONEncoder().encode(codexMotionPresetIDs) else { return }
        preferences.set(data, forKey: codexMotionStorageKey)
    }

    private func saveCodexMotionPresentations() {
        guard let data = try? JSONEncoder().encode(codexMotionPresentations) else { return }
        preferences.set(data, forKey: codexMotionPresentationStorageKey)
    }

    private func saveCodexMotionDisplaySettings() {
        guard let data = try? JSONEncoder().encode(codexMotionDisplaySettings) else { return }
        preferences.set(data, forKey: codexMotionDisplaySettingsStorageKey)
    }
}
