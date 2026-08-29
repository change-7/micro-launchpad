import AppKit
import SwiftUI

struct SmartphoneSettingsView: View {
    @Bindable var store: LaunchpadStore
    let runner: MacActionRunner
    @Environment(\.dismiss) private var dismiss
    @State private var pageIndex = 0
    @State private var buttonIndex = 0
    @State private var registrationError = ""

    private let symbolChoices = [
        // 아이콘 없음
        "",

        // 실행 및 탐색
        "play.fill", "pause.fill", "stop.fill", "forward.fill", "backward.fill",
        "play.circle.fill", "pause.circle.fill", "stop.circle.fill", "forward.end.fill", "backward.end.fill",
        "arrow.left", "arrow.right", "arrow.up", "arrow.down", "chevron.left", "chevron.right",
        "chevron.up", "chevron.down", "arrow.clockwise", "arrow.counterclockwise", "arrow.uturn.backward",

        // 앱 및 기기
        "terminal", "terminal.fill", "macwindow", "macwindow.on.rectangle", "display", "laptopcomputer",
        "iphone", "ipad", "applelogo", "command", "option", "control", "power", "computermouse",
        "keyboard", "printer", "externaldrive", "server.rack", "cpu", "wrench.and.screwdriver",

        // 파일 및 생산성
        "globe", "globe.americas", "safari", "folder", "folder.fill", "doc", "doc.text", "doc.richtext",
        "doc.plaintext", "newspaper", "archivebox", "tray", "tray.full", "paperclip", "link",
        "bookmark", "bookmark.fill", "tag", "tag.fill", "calendar", "clock", "checklist",
        "list.bullet", "list.number", "pencil", "highlighter", "square.and.pencil", "note.text",

        // 검색, 통신 및 공유
        "magnifyingglass", "scope", "at", "envelope", "envelope.fill", "message", "message.fill",
        "bubble.left", "bubble.left.and.bubble.right", "phone", "phone.fill", "video", "video.fill",
        "person.fill", "person.2.fill", "person.crop.circle", "bell", "bell.fill", "qrcode",
        "square.and.arrow.up", "square.and.arrow.down", "arrow.down.circle", "arrow.up.circle",

        // 미디어
        "camera.viewfinder", "doc.on.clipboard", "music.note", "speaker.wave.2", "moon",
        "camera.fill", "photo", "photo.fill", "photo.on.rectangle", "film", "tv", "play.rectangle.fill",
        "headphones", "mic", "mic.fill", "speaker.slash", "speaker.wave.1", "speaker.wave.3",
        "gamecontroller", "record.circle", "shuffle", "repeat", "rectangle.on.rectangle",

        // 웹, 네트워크 및 클라우드
        "wifi", "wifi.exclamationmark", "antenna.radiowaves.left.and.right", "network", "cloud",
        "cloud.fill", "icloud.and.arrow.up", "icloud.and.arrow.down", "bolt.horizontal.circle", "externaldrive.connected.to.line.below",
        "lock.shield", "key", "key.fill", "lock.open", "lock.fill", "eye", "eye.slash",

        // 시스템 및 상태
        "gearshape", "gear", "slider.horizontal.3", "ellipsis", "ellipsis.circle", "plus", "minus",
        "xmark", "checkmark", "checkmark.circle", "checkmark.circle.fill", "xmark.circle", "xmark.circle.fill",
        "questionmark", "questionmark.circle", "info.circle", "exclamationmark.triangle", "exclamationmark.circle",
        "bolt", "bolt.fill", "wand.and.stars", "sparkles", "flame", "sun.max", "moon.stars", "cloud.sun",
        "house", "house.fill", "heart", "heart.fill", "star", "star.fill", "flag", "flag.fill",
        "pin", "pin.fill", "location", "location.fill", "map", "mappin", "cart", "creditcard",

        // 숫자 및 개발 도구
        "1.circle.fill", "2.circle.fill", "3.circle.fill", "4.circle.fill", "5.circle.fill", "6.circle.fill",
        "7.circle.fill", "8.circle.fill", "9.circle.fill", "10.circle.fill", "number", "percent",
        "chevron.left.forwardslash.chevron.right", "curlybraces", "function", "sum", "hammer", "shippingbox",
        "chart.bar", "chart.line.uptrend.xyaxis", "gauge.with.dots.needle.67percent", "speedometer"
    ]

    private var page: SmartphonePage { store.smartphonePages[pageIndex] }
    private var selectedButton: SmartphoneButton { page.buttons[buttonIndex] }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            HStack(alignment: .top, spacing: 14) {
                pageList
                buttonGrid
                editor
            }
        }
        .padding(22)
        .foregroundStyle(.white)
        .background(Color(red: 0.035, green: 0.035, blue: 0.045))
        .onChange(of: pageIndex) { _, _ in buttonIndex = 0 }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "iphone").foregroundStyle(.orange)
            Text("스마트폰 버튼 설정").font(.system(size: 20, weight: .bold))
            Text("휴대폰 앱으로 전송되는 3페이지 × 16버튼 구성")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Mac 64 GRID와 별도 저장")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
            Button("완료") { dismiss() }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Divider().overlay(.white.opacity(0.16)) }
    }

    private var pageList: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("스마트폰 페이지").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            Text("현재 페이지 이름")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            DarkTextField(text: pageNameBinding, placeholder: "페이지 이름")
            ForEach(Array(store.smartphonePages.enumerated()), id: \.element.id) { index, page in
                Button { pageIndex = index } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PAGE \(String(format: "%02d", index + 1))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(index == pageIndex ? .orange : .secondary)
                        Text(page.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(index == pageIndex ? Color.orange.opacity(0.14) : Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(index == pageIndex ? .orange : .white.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(width: 140, alignment: .leading)
    }

    private var buttonGrid: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(page.name) · 버튼 선택").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(page.buttons.filter { $0.action.kind != .none }.count)/16 동작 지정")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Array(page.buttons.enumerated()), id: \.element.id) { index, button in
                    Button { buttonIndex = index } label: {
                        VStack(spacing: 6) {
                            buttonIcon(for: button, isSelected: index == buttonIndex)
                            Text(button.title.isEmpty ? "빈 버튼" : button.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text(button.action.kind.title)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 78)
                        .padding(7)
                        .background(index == buttonIndex ? Color.orange.opacity(0.15) : Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(index == buttonIndex ? .orange : .white.opacity(0.12), lineWidth: index == buttonIndex ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .frame(minWidth: 350, maxWidth: .infinity, alignment: .leading)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("버튼 편집").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) { store.resetSmartphoneButton(pageIndex: pageIndex, buttonIndex: buttonIndex) } label: {
                    Image(systemName: "trash").frame(width: 28, height: 26)
                }
                .buttonStyle(.plain)
                .help("이 스마트폰 버튼을 기본값으로 되돌립니다.")
            }
            field("버튼 라벨") { DarkTextField(text: buttonTextBinding) }
            field("아이콘 선택") { symbolPicker }
            Divider().overlay(.white.opacity(0.16))
            field("실행 동작") {
                HStack(spacing: 6) {
                    actionButton(.app)
                    actionButton(.shortcut)
                    actionButton(.url)
                }
            }
            actionRegistration
            if selectedButton.action.kind != .none {
                Button("Mac에서 이 동작 실행") { runSelectedAction() }
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .foregroundStyle(.orange)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(13)
        .frame(width: 270, alignment: .leading)
        .background(Color(red: 0.065, green: 0.065, blue: 0.08), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.12)))
    }

    private var symbolPicker: some View {
        let choices = symbolChoices.contains(selectedButton.symbol)
            ? symbolChoices
            : [selectedButton.symbol] + symbolChoices
        return VStack(alignment: .leading, spacing: 7) {
            ScrollView(.vertical) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(choices, id: \.self) { symbol in
                        Button {
                            var button = selectedButton
                            button.symbol = symbol
                            update(button)
                        } label: {
                            Group {
                                if symbol.isEmpty {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(
                                            selectedButton.symbol == symbol ? Color.orange.opacity(0.72) : .white.opacity(0.24),
                                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                                        )
                                        .padding(7)
                                } else {
                                    Image(systemName: symbol)
                                        .font(.system(size: 17, weight: .medium))
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 31)
                            .foregroundStyle(selectedButton.symbol == symbol ? .black : .white.opacity(0.78))
                            .background(
                                selectedButton.symbol == symbol ? Color.orange : Color.black.opacity(0.28),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedButton.symbol == symbol ? .orange : .white.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol.isEmpty ? "아이콘 없음" : symbol)
                        .help(symbol.isEmpty ? "아이콘 없음" : symbol)
                    }
                }
            }
            .frame(maxHeight: 230)
            Text(selectedButton.symbol.isEmpty ? "아이콘 없음" : selectedButton.symbol)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func buttonIcon(for button: SmartphoneButton, isSelected: Bool) -> some View {
        let appBundleIdentifier: String? = switch button.action.kind {
        case .app: button.action.value
        case .shortcut: button.action.targetAppBundleIdentifier
        case .url, .none: nil
        }

        if button.symbol.isEmpty {
            Color.clear
                .frame(width: 24, height: 24)
        } else if let appBundleIdentifier,
           !appBundleIdentifier.isEmpty,
           let appIcon = AppRegistrationService.icon(for: appBundleIdentifier) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 24, height: 24)
                .opacity(isSelected ? 1 : 0.82)
        } else {
            Image(systemName: button.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isSelected ? .orange : .white.opacity(0.72))
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.72))
            content()
        }
    }

    private func actionButton(_ kind: ActionKind) -> some View {
        Button(kind.title) {
            var button = selectedButton
            let previousKind = button.action.kind
            button.action.kind = kind
            if previousKind != kind {
                button.action.value = kind == .url ? "https://chatgpt.com" : ""
                button.action.targetAppBundleIdentifier = ""
            }
            if kind != .shortcut { button.action.targetAppBundleIdentifier = "" }
            update(button)
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .foregroundStyle(selectedButton.action.kind == kind ? .black : .white.opacity(0.72))
        .background(selectedButton.action.kind == kind ? Color.orange : Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 7))
        .buttonStyle(.plain)
    }

    @ViewBuilder private var actionRegistration: some View {
        switch selectedButton.action.kind {
        case .app:
            Button("앱 등록") { registerApplication() }
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .buttonStyle(.plain)
            if !selectedButton.action.value.isEmpty {
                Text(AppRegistrationService.displayName(for: selectedButton.action.value) ?? selectedButton.action.value)
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
        case .shortcut:
            ShortcutComposerView(value: actionValueBinding, targetAppBundleIdentifier: targetAppBinding, launchTargetAppIfNeeded: launchTargetBinding)
        case .url:
            DarkTextField(text: actionValueBinding, placeholder: "https://example.com")
        case .none:
            Text("이 버튼은 휴대폰에서 비활성 상태로 표시됩니다.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        if !registrationError.isEmpty { Text(registrationError).font(.system(size: 10)).foregroundStyle(.red) }
    }

    private var buttonTextBinding: Binding<String> { Binding(get: { selectedButton.title }, set: { var button = selectedButton; button.title = $0; update(button) }) }
    private var pageNameBinding: Binding<String> { Binding(get: { page.name }, set: { store.updateSmartphonePageName($0, at: pageIndex) }) }
    private var actionValueBinding: Binding<String> { Binding(get: { selectedButton.action.value }, set: { var button = selectedButton; button.action.value = $0; update(button) }) }
    private var targetAppBinding: Binding<String> { Binding(get: { selectedButton.action.targetAppBundleIdentifier }, set: { var button = selectedButton; button.action.targetAppBundleIdentifier = $0; update(button) }) }
    private var launchTargetBinding: Binding<Bool> { Binding(get: { selectedButton.action.launchTargetAppIfNeeded }, set: { var button = selectedButton; button.action.launchTargetAppIfNeeded = $0; update(button) }) }

    private func update(_ button: SmartphoneButton) { store.updateSmartphoneButton(button, at: pageIndex) }

    private func registerApplication() {
        registrationError = ""
        AppRegistrationService.chooseApplication { result in
            switch result {
            case .success(let application):
                var button = selectedButton
                button.action.kind = .app
                button.action.value = application.bundleIdentifier
                button.action.targetAppBundleIdentifier = ""
                if button.title.isEmpty { button.title = application.name }
                update(button)
            case .failure(let error): registrationError = error.localizedDescription
            }
        }
    }

    private func runSelectedAction() {
        do { store.statusMessage = try runner.execute(selectedButton.action) }
        catch { store.statusMessage = error.localizedDescription }
    }
}
