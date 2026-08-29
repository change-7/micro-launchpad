import Foundation

enum SmartphoneDefaults {
    static let pageCount = 3
    static let buttonCount = 16
    static let storageKey = "chatgpt-micro-launchpad.smartphone-pages"

    private static var sharedStorageURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("Micro Launchpad", isDirectory: true)
            .appendingPathComponent("smartphone-pages.json")
    }

    static func pages() -> [SmartphonePage] {
        let actions: [(String, String, PadAction)] = [
            ("Run", "play.fill", PadAction(kind: .shortcut, value: "cmd+r")),
            ("Pause", "pause.fill", PadAction(kind: .shortcut, value: "space")),
            ("Stop", "stop.fill", PadAction(kind: .shortcut, value: "escape")),
            ("Terminal", "terminal", PadAction(kind: .app, value: "com.apple.Terminal")),
            ("Browser", "globe", PadAction(kind: .url, value: "https://www.apple.com")),
            ("Files", "folder", PadAction(kind: .app, value: "com.apple.finder")),
            ("Search", "magnifyingglass", PadAction(kind: .shortcut, value: "cmd+space")),
            ("Capture", "camera.viewfinder", PadAction(kind: .shortcut, value: "cmd+shift+4")),
            ("Clipboard", "doc.on.clipboard", PadAction(kind: .shortcut, value: "cmd+v")),
            ("Music", "music.note", PadAction(kind: .app, value: "com.apple.Music")),
            ("Volume", "speaker.wave.2", PadAction(kind: .shortcut, value: "volumeup")),
            ("Focus", "moon", PadAction(kind: .url, value: "x-apple.systempreferences:com.apple.Focus")),
            ("Settings", "gearshape", PadAction(kind: .app, value: "com.apple.systempreferences")),
            ("More", "ellipsis", PadAction()),
            ("Run", "play.fill", PadAction(kind: .shortcut, value: "cmd+r")),
            ("Stop", "stop.fill", PadAction(kind: .shortcut, value: "escape"))
        ]

        let pageActions: [[Int]] = [
            Array(0..<16),
            [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 3, 5, 6, 10, 12],
            [0, 1, 2, 3, 6, 7, 4, 5, 8, 9, 10, 11, 12, 13, 0, 2]
        ]

        return pageActions.enumerated().map { pageIndex, indexes in
            SmartphonePage(
                id: pageID(pageIndex),
                name: String(format: "PAGE %02d", pageIndex + 1),
                buttons: indexes.enumerated().map { buttonIndex, actionIndex in
                    let action = actions[actionIndex]
                    return SmartphoneButton(
                        id: buttonID(pageIndex, buttonIndex),
                        title: action.0,
                        symbol: action.1,
                        action: action.2
                    )
                }
            )
        }
    }

    static func pageID(_ index: Int) -> String { "smartphone_page_\(index)" }
    static func buttonID(_ pageIndex: Int, _ buttonIndex: Int) -> String {
        "smartphone_page_\(pageIndex)_button_\(buttonIndex)"
    }

    static func normalized(_ page: SmartphonePage, at pageIndex: Int) -> SmartphonePage {
        let defaults = pages()[pageIndex]
        var normalized = page
        normalized.buttons = (0..<buttonCount).map { buttonIndex in
            guard let button = page.buttons.first(where: { $0.id == buttonID(pageIndex, buttonIndex) }) else {
                return defaults.buttons[buttonIndex]
            }
            var repaired = button
            repaired.action = repaired.action.repairedForPersistence
            return repaired
        }
        return normalized
    }

    static func defaultButton(pageIndex: Int, buttonIndex: Int) -> SmartphoneButton {
        pages()[pageIndex].buttons[buttonIndex]
    }

    static func persistedPages() -> [SmartphonePage] {
        if let data = try? Data(contentsOf: sharedStorageURL),
           let savedPages = try? JSONDecoder().decode([SmartphonePage].self, from: data),
           savedPages.count == pageCount {
            return savedPages.enumerated().map { normalized($0.element, at: $0.offset) }
        }
        let preferences = UserDefaults(suiteName: "com.pdg.chatgpt-micro-launchpad.native") ?? .standard
        return persistedPages(from: preferences)
    }

    static func persistedPages(from preferences: UserDefaults) -> [SmartphonePage] {
        // The bridge-only helper runs in a separate process from the settings UI.
        // Refresh the shared suite before reading changes written by that process.
        preferences.synchronize()
        guard let data = preferences.data(forKey: storageKey),
              let savedPages = try? JSONDecoder().decode([SmartphonePage].self, from: data),
              savedPages.count == pageCount else {
            return pages()
        }
        return savedPages.enumerated().map { normalized($0.element, at: $0.offset) }
    }

    static func persist(_ pages: [SmartphonePage], to preferences: UserDefaults) {
        guard let data = try? JSONEncoder().encode(pages) else { return }
        preferences.set(data, forKey: storageKey)
        preferences.synchronize()
        let directory = sharedStorageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: sharedStorageURL, options: .atomic)
    }
}
