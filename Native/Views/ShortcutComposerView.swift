import AppKit
import SwiftUI

struct ShortcutComposerView: View {
    @Binding var value: String
    @Binding var targetAppBundleIdentifier: String
    @Binding var launchTargetAppIfNeeded: Bool
    @State private var recorder = ShortcutRecorder()
    @State private var draft = ""
    @State private var targetAppRegistrationError = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                targetApplicationButton
                shortcutRegistrationButton
            }

            windowActionPicker

            targetApplicationStatus

            HStack {
                if let windowAction = MacWindowAction(rawValue: draft) {
                    MacShortcutGlyphs(action: windowAction, tint: .orange)
                } else {
                    Text(previewLabel)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(draft.isEmpty ? Color.secondary : Color.orange)
                }
                Spacer()
                if recorder.isRecording {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))

            HStack(spacing: 8) {
                Button("삭제") {
                    recorder.stop()
                    draft = ""
                    value = ""
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(.white.opacity(0.82))
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .buttonStyle(.plain)
                .help("현재 등록된 단축키를 지웁니다.")

                Button("단축키 등록 완료") {
                    recorder.stop()
                    value = draft
                }
                .font(.system(size: 12, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(draft.isEmpty ? Color.secondary : Color.black)
                .background(draft.isEmpty ? .white.opacity(0.07) : Color.orange, in: RoundedRectangle(cornerRadius: 8))
                .buttonStyle(.plain)
                .disabled(draft.isEmpty)
                .help("현재 입력된 키 조합을 이 버튼에 저장합니다.")
            }
        }
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in
            guard !recorder.isRecording else { return }
            draft = newValue
        }
        .onDisappear { recorder.stop() }
    }

    private func beginRecording() {
        recorder.begin(
            onPreview: { draft = $0 },
            onCapture: { draft = $0 }
        )
    }

    private var windowActionPicker: some View {
        Menu {
            Section("맥 창 동작") {
                ForEach(MacWindowAction.allCases) { action in
                    Button {
                        recorder.stop()
                        draft = action.rawValue
                        value = action.rawValue
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: action.symbol)
                                .frame(width: 18)
                            Text(action.title)
                            Spacer(minLength: 12)
                            MacShortcutGlyphs(action: action)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(action.title), \(action.shortcutDisplay)")
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: selectedWindowAction?.symbol ?? "macwindow")
                    .foregroundStyle(selectedWindowAction == nil ? Color.secondary : Color.orange)
                if let selectedWindowAction {
                    Text(selectedWindowAction.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    MacShortcutGlyphs(action: selectedWindowAction)
                } else {
                    Text("맥 창 동작 선택")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .help("직접 입력한 단축키 대신 맥 창 배치 동작을 선택합니다.")
        .accessibilityLabel("맥 창 동작 선택")
    }

    private var targetApplicationButton: some View {
        Button(targetAppBundleIdentifier.isEmpty ? "대상 앱 등록" : "대상 앱 변경") {
            registerTargetApplication()
        }
        .font(.system(size: 12, weight: .semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .foregroundStyle(.white)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        .buttonStyle(.plain)
        .help("단축키를 보낼 macOS 앱을 선택합니다. 선택하지 않으면 현재 활성 앱에 보냅니다.")
    }

    private var shortcutRegistrationButton: some View {
        Button(recorder.isRecording ? "키보드 입력 중…" : "단축키 등록") {
            beginRecording()
        }
        .font(.system(size: 12, weight: .semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .foregroundStyle(recorder.isRecording ? Color.black : Color.white)
        .background(recorder.isRecording ? Color.yellow : .white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        .buttonStyle(.plain)
        .help("누른 순서대로 단축키를 기록합니다. 예: ⌘ → ⌃ → ⇧ → 4. Esc는 취소입니다.")
    }

    @ViewBuilder private var targetApplicationStatus: some View {
        if !targetAppBundleIdentifier.isEmpty || !targetAppRegistrationError.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !targetAppBundleIdentifier.isEmpty {
                    HStack(spacing: 7) {
                        if let appIcon = AppRegistrationService.icon(for: targetAppBundleIdentifier) {
                            Image(nsImage: appIcon)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "app.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                        Text(targetApplicationDescription)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .lineLimit(1)
                        Spacer()
                        Button("해제") {
                            targetAppBundleIdentifier = ""
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .help("대상 앱을 해제하고 현재 활성 앱에 단축키를 보냅니다.")
                    }

                    Toggle("앱이 꺼져 있으면 실행 후 단축키 보내기", isOn: $launchTargetAppIfNeeded)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                }

                if !targetAppRegistrationError.isEmpty {
                    Text(targetAppRegistrationError)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var targetApplicationDescription: String {
        return AppRegistrationService.displayName(for: targetAppBundleIdentifier) ?? targetAppBundleIdentifier
    }

    private var selectedWindowAction: MacWindowAction? {
        MacWindowAction(rawValue: value)
    }

    private var previewLabel: String {
        return draft.isEmpty ? "입력 대기" : draft
    }

    private func registerTargetApplication() {
        targetAppRegistrationError = ""
        AppRegistrationService.chooseApplication { result in
            switch result {
            case .success(let application):
                targetAppBundleIdentifier = application.bundleIdentifier
            case .failure(let error):
                targetAppRegistrationError = error.localizedDescription
            }
        }
    }
}

private struct MacShortcutGlyphs: View {
    let action: MacWindowAction
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if action == .fullScreen {
                Text(action.shortcutArrow)
            } else {
                Text("⌃")
                Image(systemName: "globe")
                if action.shortcutUsesShift {
                    Text("⇧")
                }
                Text(action.shortcutArrow)
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(tint)
        .fixedSize()
    }
}
