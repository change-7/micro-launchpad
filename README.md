# 마이크로 런치패드

Novation Launchpad Mini MK1을 macOS용 매크로패드로 사용하는 네이티브 Swift 앱입니다.

## 빌드·실행

```bash
./script/build_and_run.sh --verify
```

완성 앱은 프로젝트 최상단의 `마이크로 런치패드.app`입니다.

## 구성

- `Native/`: SwiftUI 앱, CoreMIDI 연결, 버튼 매핑과 LED 모션
- `script/`: 빌드·앱 번들·아이콘 생성 스크립트
- `assets/`: 앱 아이콘

앱 실행·macOS 단축키 실행에는 손쉬운 사용 권한이 필요할 수 있습니다.
