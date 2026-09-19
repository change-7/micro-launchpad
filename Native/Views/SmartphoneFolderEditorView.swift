import AppKit
import SwiftUI

struct SmartphoneFolderEditorSlot: Identifiable, Hashable {
    let id: String
    let isParent: Bool
    let shortcut: SmartphoneFolderShortcut?
}

func smartphoneFolderEditorSlots(for folder: SmartphoneButton) -> [SmartphoneFolderEditorSlot] {
    var slots = [
        SmartphoneFolderEditorSlot(
            id: "\(folder.id)_parent",
            isParent: true,
            shortcut: nil
        )
    ]
    slots += folder.folderShortcuts.map {
        SmartphoneFolderEditorSlot(id: $0.id, isParent: false, shortcut: $0)
    }
    while slots.count < 16 {
        slots.append(
            SmartphoneFolderEditorSlot(
                id: "\(folder.id)_empty_\(slots.count)",
                isParent: false,
                shortcut: nil
            )
        )
    }
    return slots
}

struct SmartphoneFolderEditorView: View {
    @Bindable var store: LaunchpadStore
    let pageIndex: Int
    let folderButtonID: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedShortcutID: String?
    @State private var registrationError = ""

    private var folderButton: SmartphoneButton? {
        store.smartphonePages[safe: pageIndex]?.buttons.first { $0.id == folderButtonID }
    }

    private var selectedShortcut: SmartphoneFolderShortcut? {
        folderButton?.folderShortcuts.first { $0.id == selectedShortcutID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let folderButton {
                header(folderButton)
                HStack(alignment: .top, spacing: 14) {
                    folderGrid(folderButton)
                    shortcutEditor(folderButton)
                }
            } else {
                Text("폴더 버튼을 찾을 수 없습니다.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .foregroundStyle(.white)
        .background(Color(red: 0.035, green: 0.035, blue: 0.045))
        .frame(width: 900, height: 640)
    }

    private func header(_ folderButton: SmartphoneButton) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "iphone").foregroundStyle(.orange)
                Text("스마트폰 버튼 설정")
                    .font(.system(size: 20, weight: .bold))
                Text("· \(folderButton.title.isEmpty ? "앱 폴더" : folderButton.title)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("폴더 내부 4×4 버튼 구성")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label("상위 폴더", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                Button {
                    addShortcut()
                } label: {
                    Label("버튼 추가", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .disabled(folderButton.folderShortcuts.count >= 15)
                .opacity(folderButton.folderShortcuts.count >= 15 ? 0.45 : 1)
            }
            HStack(spacing: 8) {
                TextField("폴더 이름", text: folderTitleBinding)
                    .textFieldStyle(.roundedBorder)
                TextField("SF Symbol", text: folderSymbolBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Button("앱 변경") { registerFolderApplication() }
                    .buttonStyle(.bordered)
                if !folderButton.action.value.isEmpty {
                    Text(AppRegistrationService.displayName(for: folderButton.action.value) ?? folderButton.action.value)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if !registrationError.isEmpty {
                Text(registrationError)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Divider().overlay(.white.opacity(0.16)) }
    }

    private func folderGrid(_ folderButton: SmartphoneButton) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("폴더 버튼")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(folderButton.folderShortcuts.count)/15 등록")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.vertical) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(smartphoneFolderEditorSlots(for: folderButton)) { slot in
                        folderSlot(slot)
                    }
                }
            }
            .frame(maxHeight: 410)
        }
        .frame(minWidth: 580, maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
    }

    @ViewBuilder
    private func folderSlot(_ slot: SmartphoneFolderEditorSlot) -> some View {
        if slot.isParent {
            Button { dismiss() } label: {
                VStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                    Text("상위 폴더")
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(maxWidth: .infinity, minHeight: 78)
                .foregroundStyle(.orange)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.orange, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        } else if let shortcut = slot.shortcut {
            Button { selectedShortcutID = shortcut.id } label: {
                VStack(spacing: 6) {
                    Image(systemName: shortcut.symbol.isEmpty ? "command" : shortcut.symbol)
                        .font(.system(size: 20, weight: .medium))
                    Text(shortcut.title.isEmpty ? "이름 없음" : shortcut.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Text(shortcut.action.kind.title)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 78)
                .foregroundStyle(selectedShortcutID == shortcut.id ? .orange : .white)
                .background(selectedShortcutID == shortcut.id ? Color.orange.opacity(0.14) : Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(selectedShortcutID == shortcut.id ? .orange : .white.opacity(0.12), lineWidth: selectedShortcutID == shortcut.id ? 1.5 : 1))
            }
            .buttonStyle(.plain)
        } else {
            Button { addShortcut() } label: {
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                    Text("버튼 추가")
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(maxWidth: .infinity, minHeight: 78)
                .foregroundStyle(.white.opacity(0.46))
                .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled((folderButton?.folderShortcuts.count ?? 15) >= 15)
        }
    }

    private func shortcutEditor(_ folderButton: SmartphoneButton) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("버튼 편집")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if selectedShortcut != nil {
                    Button(role: .destructive) {
                        removeSelectedShortcut()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }
            if selectedShortcut != nil {
                TextField("버튼 라벨", text: shortcutTitleBinding)
                    .textFieldStyle(.roundedBorder)
                TextField("SF Symbol", text: shortcutSymbolBinding)
                    .textFieldStyle(.roundedBorder)
                ShortcutComposerView(
                    value: shortcutValueBinding,
                    targetAppBundleIdentifier: shortcutTargetBinding,
                    launchTargetAppIfNeeded: shortcutLaunchBinding
                )
            } else {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.orange)
                Text("4×4 버튼에서 편집할 버튼을 선택하세요.")
                    .font(.system(size: 13, weight: .medium))
                Text("빈 칸은 ‘버튼 추가’로 등록할 수 있습니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(13)
        .frame(width: 285, alignment: .leading)
        .background(Color(red: 0.065, green: 0.065, blue: 0.08), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.12)))
    }

    private var folderTitleBinding: Binding<String> {
        Binding(
            get: { folderButton?.title ?? "" },
            set: { newValue in updateFolderButton { $0.title = newValue } }
        )
    }

    private var folderSymbolBinding: Binding<String> {
        Binding(
            get: { folderButton?.symbol ?? "" },
            set: { newValue in updateFolderButton { $0.symbol = newValue } }
        )
    }

    private var shortcutTitleBinding: Binding<String> {
        Binding(
            get: { selectedShortcut?.title ?? "" },
            set: { newValue in updateSelectedShortcut { $0.title = newValue } }
        )
    }

    private var shortcutSymbolBinding: Binding<String> {
        Binding(
            get: { selectedShortcut?.symbol ?? "command" },
            set: { newValue in updateSelectedShortcut { $0.symbol = newValue } }
        )
    }

    private var shortcutValueBinding: Binding<String> {
        Binding(
            get: { selectedShortcut?.action.value ?? "" },
            set: { newValue in updateSelectedShortcut { $0.action.value = newValue } }
        )
    }

    private var shortcutTargetBinding: Binding<String> {
        Binding(
            get: { selectedShortcut?.action.targetAppBundleIdentifier ?? "" },
            set: { newValue in updateSelectedShortcut { $0.action.targetAppBundleIdentifier = newValue } }
        )
    }

    private var shortcutLaunchBinding: Binding<Bool> {
        Binding(
            get: { selectedShortcut?.action.launchTargetAppIfNeeded ?? true },
            set: { newValue in updateSelectedShortcut { $0.action.launchTargetAppIfNeeded = newValue } }
        )
    }

    private func updateFolderButton(_ change: (inout SmartphoneButton) -> Void) {
        guard var button = folderButton else { return }
        change(&button)
        store.updateSmartphoneButton(button, at: pageIndex)
    }

    private func updateSelectedShortcut(_ change: (inout SmartphoneFolderShortcut) -> Void) {
        guard let selectedShortcutID,
              var button = folderButton,
              let index = button.folderShortcuts.firstIndex(where: { $0.id == selectedShortcutID }) else { return }
        change(&button.folderShortcuts[index])
        store.updateSmartphoneButton(button, at: pageIndex)
    }

    private func addShortcut() {
        guard var button = folderButton else { return }
        guard button.folderShortcuts.count < 15 else { return }
        let shortcut = SmartphoneFolderShortcut(
            id: "\(button.id)_folder_\(UUID().uuidString)",
            title: "단축키 \(button.folderShortcuts.count + 1)",
            symbol: "command",
            action: PadAction(kind: .shortcut, targetAppBundleIdentifier: button.action.value)
        )
        button.folderShortcuts.append(shortcut)
        store.updateSmartphoneButton(button, at: pageIndex)
        selectedShortcutID = shortcut.id
    }

    private func removeSelectedShortcut() {
        guard let selectedShortcutID else { return }
        updateFolderButton { button in
            button.folderShortcuts.removeAll { $0.id == selectedShortcutID }
        }
        self.selectedShortcutID = nil
    }

    private func registerFolderApplication() {
        registrationError = ""
        AppRegistrationService.chooseApplication { result in
            switch result {
            case .success(let application):
                updateFolderButton { button in
                    button.action.value = application.bundleIdentifier
                    button.folderShortcuts = button.folderShortcuts.map { shortcut in
                        var updated = shortcut
                        updated.action.targetAppBundleIdentifier = application.bundleIdentifier
                        return updated
                    }
                }
            case .failure(let error):
                registrationError = error.localizedDescription
            }
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
