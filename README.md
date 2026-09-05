# 마이크로 런치패드

Novation Launchpad Mini MK1을 macOS용 매크로패드로 사용하는 네이티브 Swift 앱입니다.

## 빌드·실행

```bash
./script/build_and_run.sh --verify
```

완성 앱은 프로젝트 최상단의 `마이크로 런치패드.app`입니다.

## 로컬 REST API

Mac 앱이 실행 중일 때만 모바일 반응형 웹페이지와 REST API가 열립니다. 서버는
Tailscale 주소가 확인된 경우에만 시작하며, 앱이 종료되면 함께 종료됩니다.

- 웹페이지/API: `http://<Tailscale IP>:43124/` (IPv6는 `http://[<Tailscale IPv6>]:43124/`)
- 인증: 메뉴 막대 상태 메뉴의 `REST API 토큰 복사`로 토큰을 복사한 뒤 웹페이지에 입력
- API 요청: `Authorization: Bearer <token>` 헤더 사용
- 브라우저 mutation 요청(`POST`)은 위 숫자형 Tailscale 주소에서 페이지를 열어야 합니다. MagicDNS 호스트명은 canonical Origin이 아니므로 사용할 수 없습니다.

지원 엔드포인트는 등록된 앱 기능으로 한정됩니다.

```text
GET  /api/apps
POST /api/apps/{id}/launch
POST /api/apps/{id}/quit
```

`GET /api/apps`가 반환하는 `id`는 앱 실행 중에만 유효한 불투명 capability ID입니다.
외부에 bundle ID, 경로, PID를 노출하지 않으며, 미리 등록된 앱 실행/종료만 허용합니다.
터미널 명령이나 임의 URL 실행은 이 REST API로 제공하지 않습니다. 토큰은 macOS
Keychain에 저장되므로 복사한 토큰을 공유 클립보드나 URL에 넣지 마세요.

> 주의: 기존 Android 호환 `CodexRemoteBridge`는 별도 레거시 프로토콜로 포트 `43123`을
> 사용하며, 이 작업에서 변경하지 않았습니다. 해당 브리지는 이전 wire protocol 호환을
> 위해 무인증/기존 원격 동작을 유지하므로, 신규 Tailscale 전용·Bearer 인증 보장은
> REST 포트 `43124`에만 적용됩니다.

## 구성

- `Native/`: SwiftUI 앱, CoreMIDI 연결, 버튼 매핑과 LED 모션
- `script/`: 빌드·앱 번들·아이콘 생성 스크립트
- `assets/`: 앱 아이콘

앱 실행·macOS 단축키 실행에는 손쉬운 사용 권한이 필요할 수 있습니다.
