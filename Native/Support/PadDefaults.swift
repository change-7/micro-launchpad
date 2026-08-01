import Foundation

enum PadDefaults {
    static let pageNames = ["ChatGPT Micro", "Mac 앱", "시스템 단축키", "작업 공간", "유틸리티", "페이지 6", "페이지 7", "페이지 8"]

    struct SideButtonDescriptor: Hashable {
        let index: Int
        let title: String
        let symbol: String
        let defaultAction: PadAction?
        let defaultDescription: String?

        var isCustomOnly: Bool { defaultAction == nil }
    }

    static let sideButtonDescriptors: [SideButtonDescriptor] = [
        SideButtonDescriptor(index: 0, title: "Vol +", symbol: "speaker.wave.2", defaultAction: PadAction(kind: .shortcut, value: "VolumeUp"), defaultDescription: "macOS 볼륨 올리기"),
        SideButtonDescriptor(index: 1, title: "Vol −", symbol: "speaker.wave.1", defaultAction: PadAction(kind: .shortcut, value: "VolumeDown"), defaultDescription: "macOS 볼륨 내리기"),
        SideButtonDescriptor(index: 2, title: "Mute", symbol: "speaker.slash", defaultAction: PadAction(kind: .shortcut, value: "Mute"), defaultDescription: "macOS 음소거 전환"),
        SideButtonDescriptor(index: 3, title: "Play", symbol: "play.fill", defaultAction: PadAction(kind: .shortcut, value: "MediaPlayPause"), defaultDescription: "macOS 미디어 재생·일시정지"),
        SideButtonDescriptor(index: 4, title: "Pause", symbol: "pause.fill", defaultAction: PadAction(kind: .shortcut, value: "MediaPlayPause"), defaultDescription: "macOS 미디어 재생·일시정지"),
        SideButtonDescriptor(index: 5, title: "Stop", symbol: "stop.fill", defaultAction: PadAction(kind: .shortcut, value: "Cmd+."), defaultDescription: "현재 앱의 작업 취소"),
        SideButtonDescriptor(index: 6, title: "Solo", symbol: "headphones", defaultAction: nil, defaultDescription: nil),
        SideButtonDescriptor(index: 7, title: "Rec", symbol: "record.circle", defaultAction: PadAction(kind: .shortcut, value: "Cmd+Shift+5"), defaultDescription: "macOS 화면 녹화·캡처 패널 열기")
    ]

    static func pages() -> [LaunchPage] {
        let pages = pageNames.map { LaunchPage(name: $0, pads: pads()) }
        var result = pages
        configure(&result)
        return result
    }

    private static func pads() -> [Pad] {
        let grid = (0..<64).map { index in Pad(id: "grid_\(index / 8)_\(index % 8)") }
        let side = (0..<8).map(sidePad)
        return grid + side
    }

    static func normalized(_ page: LaunchPage) -> LaunchPage {
        var page = page
        page.pageIdleColor = supportedColor(page.pageIdleColor)
        page.pageActiveColor = supportedColor(page.pageActiveColor)
        page.pads = page.pads.map { pad in
            var normalized = pad
            if normalized.symbol == "circle", normalized.title.isEmpty, normalized.action.kind == .none {
                normalized.symbol = ""
            }
            normalized.idleColor = supportedColor(normalized.idleColor)
            normalized.activeColor = supportedColor(normalized.activeColor)
            return normalized
        }
        for index in 0..<8 {
            guard let sideIndex = page.pads.firstIndex(where: { $0.id == "side_\(index)" }), page.pads[sideIndex].title.isEmpty else { continue }
            page.pads[sideIndex].title = sideTitles[index]
            page.pads[sideIndex].symbol = sideSymbols[index]
        }
        let existingIDs = Set(page.pads.map(\.id))
        for index in 0..<8 where !existingIDs.contains("side_\(index)") {
            page.pads.append(sidePad(index))
        }
        return page
    }

    static let sideSymbols = sideButtonDescriptors.map(\.symbol)
    static let sideTitles = sideButtonDescriptors.map(\.title)

    static func sideButtonDescriptor(for padID: String) -> SideButtonDescriptor? {
        guard padID.hasPrefix("side_"), let index = Int(padID.dropFirst(5)) else { return nil }
        return sideButtonDescriptors.first { $0.index == index }
    }

    static func defaultPad(for id: String) -> Pad {
        guard let descriptor = sideButtonDescriptor(for: id) else { return Pad(id: id) }
        return sidePad(descriptor.index)
    }

    static func applyingDefaultSideActions(to pages: [LaunchPage]) -> [LaunchPage] {
        pages.map { page in
            var page = page
            for descriptor in sideButtonDescriptors {
                guard let defaultAction = descriptor.defaultAction,
                      let padIndex = page.pads.firstIndex(where: { $0.id == "side_\(descriptor.index)" }),
                      page.pads[padIndex].action.kind == .none else { continue }
                page.pads[padIndex].action = defaultAction
                page.pads[padIndex].title = descriptor.title
                page.pads[padIndex].symbol = descriptor.symbol
            }
            return page
        }
    }

    static func applyingSideButtonCategoryOrder(to pages: [LaunchPage]) -> [LaunchPage] {
        let oldDefaults: [(title: String, symbol: String, action: PadAction)] = [
            ("Vol +", "speaker.wave.2", PadAction(kind: .shortcut, value: "VolumeUp")),
            ("Vol −", "speaker.wave.1", PadAction(kind: .shortcut, value: "VolumeDown")),
            ("Snd A", "paperplane", PadAction()),
            ("Snd B", "paperplane", PadAction()),
            ("Stop", "stop.fill", PadAction(kind: .shortcut, value: "Cmd+.")),
            ("Mute", "speaker.slash", PadAction(kind: .shortcut, value: "Mute")),
            ("Solo", "headphones", PadAction()),
            ("Rec", "record.circle", PadAction(kind: .shortcut, value: "Cmd+Shift+5"))
        ]

        return pages.map { page in
            var page = page
            for index in sideButtonDescriptors.indices {
                guard let padIndex = page.pads.firstIndex(where: { $0.id == "side_\(index)" }) else { continue }
                let pad = page.pads[padIndex]
                let old = oldDefaults[index]
                guard pad.title == old.title, pad.symbol == old.symbol, pad.action == old.action else { continue }

                var sorted = sidePad(index)
                sorted.idleColor = pad.idleColor
                sorted.activeColor = pad.activeColor
                page.pads[padIndex] = sorted
            }
            return page
        }
    }

    static func applyingSortedSideButtonDefaults(to pages: [LaunchPage]) -> [LaunchPage] {
        pages.map { page in
            var page = page
            for index in sideButtonDescriptors.indices {
                guard let padIndex = page.pads.firstIndex(where: { $0.id == "side_\(index)" }) else { continue }
                let existing = page.pads[padIndex]
                var sorted = sidePad(index)
                sorted.idleColor = existing.idleColor
                sorted.activeColor = existing.activeColor
                page.pads[padIndex] = sorted
            }
            return page
        }
    }

    private static func sidePad(_ index: Int) -> Pad {
        let descriptor = sideButtonDescriptors[index]
        return Pad(
            id: "side_\(index)",
            title: descriptor.title,
            symbol: descriptor.symbol,
            idleColor: "off",
            activeColor: "green",
            action: descriptor.defaultAction ?? PadAction()
        )
    }

    private static func configure(_ pages: inout [LaunchPage]) {
        set(&pages[0], 0, "ChatGPT", "sparkles", "green", .app, "com.openai.chat")
        set(&pages[0], 1, "새 대화", "plus.bubble", "orange", .shortcut, "Cmd+N")
        set(&pages[0], 2, "ChatGPT 웹", "globe", "brightGreen", .url, "https://chatgpt.com")
        set(&pages[0], 8, "음성 입력", "mic", "orange", .app, "com.openai.chat")
        set(&pages[0], 9, "새 메모", "note.text", "yellow", .app, "com.apple.Notes")

        set(&pages[1], 0, "Safari", "safari", "green", .app, "com.apple.Safari")
        set(&pages[1], 1, "Chrome", "globe", "green", .app, "com.google.Chrome")
        set(&pages[1], 2, "Finder", "folder", "orange", .app, "com.apple.finder")
        set(&pages[1], 3, "캘린더", "calendar", "red", .app, "com.apple.iCal")

        set(&pages[2], 0, "Spotlight", "magnifyingglass", "green", .shortcut, "Cmd+Space")
        set(&pages[2], 1, "영역 캡처", "camera.viewfinder", "orange", .shortcut, "Cmd+Shift+4")
        set(&pages[2], 2, "화면 잠금", "lock", "red", .shortcut, "Ctrl+Cmd+Q")
    }

    private static func set(_ page: inout LaunchPage, _ index: Int, _ title: String, _ symbol: String, _ color: String, _ kind: ActionKind, _ value: String) {
        page.pads[index] = Pad(id: page.pads[index].id, title: title, symbol: symbol, idleColor: color, activeColor: "green", action: PadAction(kind: kind, value: value))
    }

    private static func supportedColor(_ color: String) -> String {
        switch color {
        case "slate", "lime": "off"
        case "blue": "brightGreen"
        case "purple": "darkAmber"
        default: PadColor(rawValue: color) == nil ? "off" : color
        }
    }
}
