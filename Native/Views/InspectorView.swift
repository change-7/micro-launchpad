import SwiftUI

struct InspectorView: View {
    @Binding var pad: Pad
    let pages: [LaunchPage]
    let selectedPageLEDIndex: Int?
    let onSelectPageLED: (Int?) -> Void
    let onUpdatePageColor: (Int, String, Bool) -> Void
    let onUpdatePageName: (Int, String) -> Void
    let onReset: () -> Void
    let onRun: () -> Void
    @State private var registrationError = ""
    @State private var appRegistrationRequestID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedPageLEDIndex == nil ? "SELECTED PAD" : "SELECTED TOP BUTTON")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.yellow)
                Text(inspectorTitle).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                if selectedPageLEDIndex == nil {
                    Button(role: .destructive, action: onReset) { Image(systemName: "trash").frame(width: 30, height: 30).background(Color.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 6)) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 11)
            .overlay(alignment: .bottom) { Divider().overlay(Color.white.opacity(0.18)) }

            if let pageIndex = selectedPageLEDIndex, pages.indices.contains(pageIndex) {
                fieldSection("P 버튼 이름") {
                    DarkTextField(text: Binding(
                        get: { pages[pageIndex].name },
                        set: { onUpdatePageName(pageIndex, $0) }
                    ))
                }
                sectionDivider
                fieldSection("런치패드 LED 색상") {
                    Button("현재 패드 LED 색상으로 돌아가기") {
                        onSelectPageLED(nil)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    HStack(alignment: .top, spacing: 16) {
                        pagePalette(title: "P\(pageIndex + 1) 대기 색상", selection: pages[pageIndex].pageIdleColor, selected: false, index: pageIndex)
                        pagePalette(title: "P\(pageIndex + 1) 선택된 페이지 색상", selection: pages[pageIndex].pageActiveColor, selected: true, index: pageIndex)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    fieldSection("버튼 라벨") {
                        DarkTextField(text: $pad.title)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    fieldSection("아이콘") {
                        LaunchpadIconPicker(selection: $pad.symbol, isSideButton: pad.id.hasPrefix("side_"))
                    }
                    .frame(width: 128, alignment: .leading)
                }

                sectionDivider
                if let descriptor = PadDefaults.sideButtonDescriptor(for: pad.id) {
                    sideButtonRoleSection(descriptor)
                    sectionDivider
                }
                fieldSection("할당할 동작") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                        actionButton(.app)
                        actionButton(.shortcut)
                        actionButton(.terminalCommand)
                        actionButton(.url)
                    }
                    if pad.action.kind != .none {
                        actionRegistration
                        Button("이 동작 실행", action: onRun)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(.orange)
                            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            .buttonStyle(.plain)
                    }
                }

                sectionDivider
                fieldSection("런치패드 LED 색상") {
                    HStack(alignment: .top, spacing: 16) {
                        palette(title: "대기 색상", selection: $pad.idleColor)
                        palette(title: "눌렀을 때 색상", selection: $pad.activeColor)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .foregroundStyle(Color(red: 0.88, green: 0.88, blue: 0.91))
        .background(Color(red: 0.065, green: 0.065, blue: 0.08), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.11)))
        .onChange(of: pad.id) { _, _ in
            appRegistrationRequestID = UUID()
        }
    }

    private var locationTitle: String {
        if pad.id.hasPrefix("side_") { return "우측 버튼 [\(pad.id.dropFirst(5))]" }
        return "메인 그리드 [\(pad.id.replacingOccurrences(of: "grid_", with: ""))]"
    }

    private var inspectorTitle: String {
        guard let pageIndex = selectedPageLEDIndex else { return locationTitle }
        return "상단 P\(pageIndex + 1) 버튼"
    }

    @ViewBuilder private func fieldSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.76))
            content()
        }
    }

    private var sectionDivider: some View { Divider().overlay(Color.white.opacity(0.18)).padding(.vertical, 1) }

    private func sideButtonRoleSection(_ descriptor: PadDefaults.SideButtonDescriptor) -> some View {
        let usesDefault = descriptor.defaultAction == pad.action
        return VStack(alignment: .leading, spacing: 7) {
            if let description = descriptor.defaultDescription, usesDefault {
                Label("기본 macOS 기능", systemImage: "macwindow")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.green)
                Text(description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                Text("아래에서 앱·단축키·웹 동작으로 바꾸면 사용자 지정 버튼이 됩니다.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Button("사용자 지정 기능으로 변경") {
                    pad.action = PadAction()
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
                .buttonStyle(.plain)
                .help("기본 macOS 기능을 해제합니다. 아래에서 앱 실행, 단축키, 웹 동작을 새로 지정할 수 있습니다.")
            } else {
                Label("사용자 지정 버튼", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
                Text(descriptor.isCustomOnly ? "이 표기는 앱마다 의미가 달라 원하는 동작을 직접 정할 수 있습니다." : "기본 기능 대신 직접 지정한 동작을 사용 중입니다.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if let defaultAction = descriptor.defaultAction, !usesDefault {
                    Button("기본 macOS 기능 복원") {
                        pad.action = defaultAction
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background((usesDefault ? Color.green : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke((usesDefault ? Color.green : Color.orange).opacity(0.26)))
    }

    private func actionButton(_ kind: ActionKind) -> some View {
        Button {
            let changedKind = pad.action.kind != kind
            if changedKind {
                appRegistrationRequestID = UUID()
            }
            pad.action.kind = kind
            if changedKind || pad.action.value.isEmpty { pad.action.value = defaultValue(for: kind) }
        } label: {
            Text(kind.title).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(pad.action.kind == kind ? Color.black : .white.opacity(0.72))
                .background(pad.action.kind == kind ? Color.orange : Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(pad.action.kind == kind ? Color.orange : Color.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var actionRegistration: some View {
        switch pad.action.kind {
        case .app:
            VStack(alignment: .leading, spacing: 8) {
                Button("앱 등록") { registerApplication() }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(.plain)
                registrationValue(
                    title: pad.action.value.isEmpty ? "등록된 앱 없음" : (AppRegistrationService.displayName(for: pad.action.value) ?? "등록된 앱"),
                    detail: pad.action.value
                )
            }
        case .shortcut:
            ShortcutComposerView(
                value: $pad.action.value,
                targetAppBundleIdentifier: $pad.action.targetAppBundleIdentifier,
                launchTargetAppIfNeeded: $pad.action.launchTargetAppIfNeeded
            )
        case .terminalCommand:
            DarkTextField(text: $pad.action.value, placeholder: "예: open -a Safari")
        case .url:
            DarkTextField(text: $pad.action.value, placeholder: "https://example.com")
        case .none:
            EmptyView()
        }
    }

    private func registrationValue(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            if !detail.isEmpty { Text(detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1) }
            if !registrationError.isEmpty { Text(registrationError).font(.system(size: 10)).foregroundStyle(.red).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
    }

    private func registerApplication() {
        registrationError = ""
        let targetPadID = pad.id
        let requestID = UUID()
        appRegistrationRequestID = requestID
        AppRegistrationService.chooseApplication { result in
            guard appRegistrationRequestID == requestID, pad.id == targetPadID, pad.action.kind == .app else { return }
            switch result {
            case .success(let application):
                pad.action.value = application.bundleIdentifier
                if pad.title.isEmpty { pad.title = application.name }
            case .failure(let error):
                registrationError = error.localizedDescription
            }
        }
    }

    private func palette(title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(31), spacing: 8), count: 4), spacing: 8) {
                ForEach(PadColor.launchpadPalette) { color in
                    Button { selection.wrappedValue = color.rawValue } label: {
                        RoundedRectangle(cornerRadius: 4).fill(color.color).frame(width: 31, height: 31)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(selection.wrappedValue == color.rawValue ? Color.white : .white.opacity(0.32), lineWidth: selection.wrappedValue == color.rawValue ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(9)
            .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.16)))
        }
    }

    private func pagePalette(title: String, selection: String, selected: Bool, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(31), spacing: 8), count: 4), spacing: 8) {
                ForEach(PadColor.launchpadPalette) { color in
                    Button { onUpdatePageColor(index, color.rawValue, selected) } label: {
                        RoundedRectangle(cornerRadius: 4).fill(color.color).frame(width: 31, height: 31)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(selection == color.rawValue ? Color.white : .white.opacity(0.32), lineWidth: selection == color.rawValue ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(9)
            .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.16)))
        }
    }

    private func defaultValue(for kind: ActionKind) -> String {
        switch kind {
        case .app, .shortcut, .terminalCommand: ""
        case .url: "https://chatgpt.com"
        case .none: ""
        }
    }
}

private struct LaunchpadIconPicker: View {
    @Binding var selection: String
    let isSideButton: Bool
    @State private var isShowingPicker = false

    private let icons = [
        "sparkles", "plus.bubble", "message", "mic", "paperplane", "globe",
        "safari", "folder", "note.text", "calendar", "magnifyingglass", "camera.viewfinder",
        "lock", "play.fill", "pause.fill", "stop.fill", "record.circle", "speaker.wave.2", "speaker.wave.1",
        "speaker.slash", "headphones", "slider.horizontal.3", "gearshape", "terminal", "bolt.fill",
        "app.fill", "doc", "doc.text", "doc.on.doc", "photo", "video", "film", "camera",
        "tray.full", "archivebox", "externaldrive", "icloud", "link", "bookmark", "house",
        "building.2", "person", "person.2", "person.crop.circle", "envelope", "phone", "bell",
        "clock", "timer", "checkmark", "xmark", "exclamationmark.triangle", "questionmark.circle",
        "info.circle", "arrow.triangle.2.circlepath", "arrow.clockwise", "arrow.up.right.square",
        "square.and.arrow.up", "scissors", "pencil", "paintbrush", "wand.and.stars", "puzzlepiece",
        "command", "keyboard", "computermouse", "display", "laptopcomputer", "desktopcomputer",
        "cpu", "memorychip", "network", "wifi", "antenna.radiowaves.left.and.right", "battery.100",
        "power", "lightbulb", "moon", "sun.max", "flame", "heart.fill", "star.fill", "flag.fill",
        "cart.fill", "creditcard", "map", "location.fill", "car.fill", "airplane", "leaf.fill"
    ]

    private struct IconCategory: Identifiable {
        let title: String
        let icons: [String]
        var id: String { title }
    }

    private var iconCategories: [IconCategory] {
        guard isSideButton else { return [IconCategory(title: "아이콘", icons: icons)] }

        let volume = ["speaker.wave.2", "speaker.wave.1", "speaker.slash"]
        let media = ["play.fill", "pause.fill", "stop.fill", "record.circle", "headphones", "video", "film", "camera"]
        let macControls = ["command", "keyboard", "computermouse", "display", "desktopcomputer", "gearshape", "power", "moon", "sun.max"]
        let grouped = Set(volume + media + macControls)
        let remaining = icons.filter { !grouped.contains($0) }
        return [
            IconCategory(title: "볼륨", icons: volume),
            IconCategory(title: "미디어", icons: media),
            IconCategory(title: "macOS 제어", icons: macControls),
            IconCategory(title: "기타", icons: remaining)
        ]
    }

    var body: some View {
        Button {
            isShowingPicker.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selection.isEmpty ? "square.dashed" : selection)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 25, height: 25)
                    .foregroundStyle(selection.isEmpty ? Color.secondary : Color.orange)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                Text(selection.isEmpty ? "아이콘 없음" : iconTitle(for: selection))
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 38)
            .background(Color(red: 0.01, green: 0.02, blue: 0.05), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.22)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("아이콘 선택").font(.system(size: 13, weight: .bold))
                    Spacer()
                    Button("없음") {
                        selection = ""
                        isShowingPicker = false
                    }
                    .buttonStyle(.bordered)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        ForEach(iconCategories) { category in
                            if isSideButton {
                                Text(category.title)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.orange)
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(42), spacing: 8), count: 6), spacing: 8) {
                                ForEach(category.icons, id: \.self) { icon in
                                    iconButton(icon)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .padding(14)
            .frame(width: 322)
            .background(Color(red: 0.065, green: 0.065, blue: 0.08))
        }
    }

    private func iconButton(_ icon: String) -> some View {
        Button {
            selection = icon
            isShowingPicker = false
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 42, height: 38)
                .foregroundStyle(selection == icon ? Color.black : .white)
                .background(selection == icon ? Color.orange : Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection == icon ? .orange : .white.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .help(iconTitle(for: icon))
    }

    private func iconTitle(for icon: String) -> String {
        switch icon {
        case "sparkles": "반짝임"
        case "plus.bubble": "새 대화"
        case "message": "메시지"
        case "mic": "마이크"
        case "paperplane": "전송"
        case "globe": "웹"
        case "safari": "Safari"
        case "folder": "폴더"
        case "note.text": "메모"
        case "calendar": "캘린더"
        case "magnifyingglass": "검색"
        case "camera.viewfinder": "캡처"
        case "lock": "잠금"
        case "play.fill": "재생"
        case "pause.fill": "일시 정지"
        case "stop.fill": "중지"
        case "record.circle": "녹화"
        case "speaker.wave.2": "볼륨"
        case "speaker.wave.1": "볼륨 내리기"
        case "speaker.slash": "음소거"
        case "headphones": "헤드폰"
        case "slider.horizontal.3": "조절"
        case "gearshape": "설정"
        case "terminal": "터미널"
        case "bolt.fill": "빠른 실행"
        default: icon
        }
    }
}

struct DarkTextField: View {
    @Binding var text: String
    var placeholder = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(Color(red: 0.01, green: 0.02, blue: 0.05), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.22)))
    }
}
