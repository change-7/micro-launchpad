import AppKit
import SwiftUI

struct LocalAPISettingsView: View {
    @State private var tokenCopyMessage = ""

    var body: some View {
        Form {
            Section {
                Label {
                    Text("앱이 실행 중일 때만 REST API와 모바일 웹페이지가 열립니다.")
                } icon: {
                    Image(systemName: "network")
                        .foregroundStyle(.blue)
                }
                Text("서버는 유효한 Tailscale 주소가 확인된 경우에만 시작되며, 앱이 종료되면 함께 종료됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("REST API")
            }

            Section("접속") {
                LabeledContent("주소") {
                    Text("http://<Tailscale IP>:43124/")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                Text("IPv6 주소는 http://[<Tailscale IPv6>]:43124/ 형식으로 입력하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Bearer 토큰")
                        Text("토큰은 macOS Keychain에 저장되고 웹페이지에는 메모리로만 전달됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("토큰 복사") { copyToken() }
                }

                if !tokenCopyMessage.isEmpty {
                    Text(tokenCopyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("사용 순서") {
                instruction(number: "1", text: "Tailscale에 연결된 기기에서 위 주소를 엽니다.")
                instruction(number: "2", text: "상태 메뉴의 ‘REST API 토큰 복사’ 또는 이 창의 ‘토큰 복사’를 누릅니다.")
                instruction(number: "3", text: "모바일 웹페이지에 토큰을 입력하고 Connect를 누릅니다.")
                instruction(number: "4", text: "앱 목록을 새로 조회한 뒤 Launch 또는 Quit을 누릅니다.")
                Text("POST 요청은 숫자형 Tailscale 주소에서 페이지를 연 경우에만 허용됩니다. API 호출 시에는 Authorization: Bearer <token> 헤더를 사용하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("지원 엔드포인트") {
                endpoint(method: "GET", path: "/api/apps", description: "등록된 앱과 실행 상태를 조회합니다.")
                endpoint(method: "POST", path: "/api/apps/{id}/launch", description: "목록에서 받은 id의 앱을 실행합니다.")
                endpoint(method: "POST", path: "/api/apps/{id}/quit", description: "목록에서 받은 id의 앱을 정상 종료합니다.")
                Text("{id}에는 /api/apps 응답의 불투명 ID를 그대로 사용하세요. bundle ID, 경로, PID를 직접 입력할 수 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("허용 범위") {
                Text("REST API는 스마트폰 버튼 설정에 미리 등록된 앱의 실행과 종료만 허용합니다. 임의의 터미널 명령, 셸, URL 실행은 제공하지 않습니다.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("기존 Android 호환 브리지(포트 43123)는 별도 레거시 프로토콜이며, 이 REST API의 Tailscale·Bearer 인증 보장에는 포함되지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 650)
        .scenePadding()
    }

    private func instruction(number: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .frame(width: 20, alignment: .leading)
                .foregroundStyle(.blue)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func endpoint(method: String, path: String, description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(method)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .frame(width: 44, alignment: .leading)
                .foregroundStyle(method == "GET" ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func copyToken() {
        guard let token = LocalAPITokenStore.loadExistingToken() else {
            tokenCopyMessage = "토큰을 읽을 수 없습니다. 앱을 다시 실행해 보세요."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        tokenCopyMessage = "토큰을 클립보드에 복사했습니다."
    }
}
