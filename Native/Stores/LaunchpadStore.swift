import Foundation
import Observation

@Observable
final class LaunchpadStore {
    private let storageKey = "chatgpt-micro-launchpad.pages"
    private let motionStorageKey = "chatgpt-micro-launchpad.motion-presets"
    private let codexMotionStorageKey = "chatgpt-micro-launchpad.codex-motion-bindings"
    private let codexMotionPresentationStorageKey = "chatgpt-micro-launchpad.codex-motion-presentations"
    private let codexMotionDisplaySettingsStorageKey = "chatgpt-micro-launchpad.codex-motion-display-settings"
    private let sideButtonDefaultsMigrationKey = "chatgpt-micro-launchpad.side-button-defaults-v2"
    private let sideButtonCategoryOrderMigrationKey = "chatgpt-micro-launchpad.side-button-category-order-v3"
    private let sortedSideButtonDefaultsMigrationKey = "chatgpt-micro-launchpad.sorted-side-button-defaults-v4"
    var pages: [LaunchPage]
    var motionPresets: [MotionPreset]
    var codexMotionPresetIDs: [String: UUID]
    var codexMotionPresentations: [String: CodexMotionPresentation]
    var codexMotionDisplaySettings: CodexMotionDisplaySettings
    var selectedPage = 0
    var selectedPadID = "grid_0_0"
    var statusMessage = "패드를 선택해 설정하세요."

    init() {
        let needsSideButtonMigration = !UserDefaults.standard.bool(forKey: sideButtonDefaultsMigrationKey)
        let needsSideButtonCategoryOrdering = !UserDefaults.standard.bool(forKey: sideButtonCategoryOrderMigrationKey)
        let needsSortedSideButtonDefaults = !UserDefaults.standard.bool(forKey: sortedSideButtonDefaultsMigrationKey)
        var loadedPages: [LaunchPage]
        if let data = UserDefaults.standard.data(forKey: storageKey), let savedPages = try? JSONDecoder().decode([LaunchPage].self, from: data), savedPages.count == 8 {
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
        pages = loadedPages
        motionPresets = (try? UserDefaults.standard.data(forKey: motionStorageKey)
            .flatMap { try JSONDecoder().decode([MotionPreset].self, from: $0) }) ?? []
        let savedPresetIDs = (try? UserDefaults.standard.data(forKey: codexMotionStorageKey)
            .flatMap { try JSONDecoder().decode([String: UUID].self, from: $0) }) ?? [:]
        codexMotionPresetIDs = savedPresetIDs
        let loadedPresentations: [String: CodexMotionPresentation]
        if let data = UserDefaults.standard.data(forKey: codexMotionPresentationStorageKey),
           let saved = try? JSONDecoder().decode([String: CodexMotionPresentation].self, from: data) {
            loadedPresentations = saved
        } else {
            loadedPresentations = savedPresetIDs.reduce(into: [:]) { result, entry in
                result[entry.key] = CodexMotionPresentation(presetID: entry.value)
            }
        }
        codexMotionPresentations = loadedPresentations
        let restoredDisplaySettings = CodexMotionDisplaySettings.restored(
            from: UserDefaults.standard.data(forKey: codexMotionDisplaySettingsStorageKey),
            legacyPresentations: loadedPresentations
        )
        codexMotionDisplaySettings = restoredDisplaySettings.settings
        if needsSideButtonMigration || needsSideButtonCategoryOrdering || needsSortedSideButtonDefaults {
            if needsSideButtonMigration {
                UserDefaults.standard.set(true, forKey: sideButtonDefaultsMigrationKey)
            }
            if needsSideButtonCategoryOrdering {
                UserDefaults.standard.set(true, forKey: sideButtonCategoryOrderMigrationKey)
            }
            if needsSortedSideButtonDefaults {
                UserDefaults.standard.set(true, forKey: sortedSideButtonDefaultsMigrationKey)
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
        guard let index = pages[selectedPage].pads.firstIndex(where: { $0.id == pad.id }) else { return }
        pages[selectedPage].pads[index] = pad
        save()
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

    func resetSelectedPad() {
        update(PadDefaults.defaultPad(for: selectedPadID))
    }

    func save() {
        guard let data = try? JSONEncoder().encode(pages) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func saveMotionPresets() {
        guard let data = try? JSONEncoder().encode(motionPresets) else { return }
        UserDefaults.standard.set(data, forKey: motionStorageKey)
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
        saveMotionPresets()
        saveCodexMotionBindings()
        saveCodexMotionPresentations()
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

    func setCodexMotionDisplayScope(_ scope: CodexMotionDisplayScope) {
        codexMotionDisplaySettings.scope = scope
        if scope == .specificPage, codexMotionDisplaySettings.pageID == nil {
            codexMotionDisplaySettings.pageID = pages.first?.id
        }
        saveCodexMotionDisplaySettings()
    }

    func setCodexMotionDisplayPageID(_ pageID: UUID) {
        codexMotionDisplaySettings.pageID = pageID
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

    func shouldPreservePadLEDsDuringCodexMotion(for activity: CodexActivity) -> Bool {
        codexMotionDisplaySettings.shouldPreservePadLEDsDuringMotion(for: activity)
    }

    func shouldPresentCodexMotion(on page: LaunchPage) -> Bool {
        codexMotionDisplaySettings.allowsPresentation(on: page.id)
    }

    private func saveCodexMotionBindings() {
        guard let data = try? JSONEncoder().encode(codexMotionPresetIDs) else { return }
        UserDefaults.standard.set(data, forKey: codexMotionStorageKey)
    }

    private func saveCodexMotionPresentations() {
        guard let data = try? JSONEncoder().encode(codexMotionPresentations) else { return }
        UserDefaults.standard.set(data, forKey: codexMotionPresentationStorageKey)
    }

    private func saveCodexMotionDisplaySettings() {
        guard let data = try? JSONEncoder().encode(codexMotionDisplaySettings) else { return }
        UserDefaults.standard.set(data, forKey: codexMotionDisplaySettingsStorageKey)
    }
}
