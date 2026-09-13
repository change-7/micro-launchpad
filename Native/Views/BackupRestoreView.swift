import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Bindable var store: LaunchpadStore
    @Environment(\.dismiss) private var dismiss
    @State private var statusMessage = ""
    @State private var errorMessage = ""
    @State private var pendingRestoreURL: URL?
    @State private var showingRestoreConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("설정·버튼 백업/복구", systemImage: "externaldrive")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("완료") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Text("Mac 64버튼, 스마트폰 버튼, Codex 모션과 표시 설정을 하나의 JSON 파일로 저장합니다.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                actionCard(
                    title: "백업 저장",
                    detail: "현재 설정을 JSON 파일로 저장",
                    symbol: "arrow.down.doc",
                    action: exportBackup
                )
                actionCard(
                    title: "백업 복구",
                    detail: "저장한 JSON으로 설정 교체",
                    symbol: "arrow.up.doc",
                    action: chooseBackupForRestore
                )
            }

            Text("백업 파일에는 API 토큰이나 연결 비밀값을 포함하지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !statusMessage.isEmpty {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            if !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(22)
        .frame(width: 620, height: 300, alignment: .topLeading)
        .alert("현재 설정을 백업으로 교체할까요?", isPresented: $showingRestoreConfirmation) {
            Button("복구", role: .destructive) { restoreBackup() }
            Button("취소", role: .cancel) { pendingRestoreURL = nil }
        } message: {
            Text("현재 Mac 버튼, 스마트폰 버튼, Codex 모션 설정이 백업 파일의 내용으로 바뀝니다.")
        }
    }

    private func actionCard(
        title: String,
        detail: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.orange)
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private func exportBackup() {
        clearMessages()
        do {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "micro-launchpad-backup.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try store.makeBackupData().write(to: url, options: .atomic)
            statusMessage = "백업을 저장했습니다."
        } catch {
            errorMessage = "백업 저장 실패: \(error.localizedDescription)"
        }
    }

    private func chooseBackupForRestore() {
        clearMessages()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingRestoreURL = url
        showingRestoreConfirmation = true
    }

    private func restoreBackup() {
        guard let url = pendingRestoreURL else { return }
        pendingRestoreURL = nil
        do {
            try store.restoreBackup(from: Data(contentsOf: url))
            statusMessage = "백업을 복구했습니다."
        } catch {
            errorMessage = "백업 복구 실패: \(error.localizedDescription)"
        }
    }

    private func clearMessages() {
        statusMessage = ""
        errorMessage = ""
    }
}
