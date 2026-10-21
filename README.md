# Malgeul (말글)

말이 글이 된다 — macOS 메뉴바에 상주하는 음성인식 앱.

단축키 한 번으로 녹음 → 전사 → 클립보드 복사 → 자동 붙여넣기. Swift 네이티브로 가볍고 빠릅니다.

## 주요 기능

- **글로벌 단축키** — 어떤 앱에서든 `⌃⌥`(Control+Option)를 눌렀다 떼서 녹음 시작/종료
- **자동 붙여넣기** — 전사 완료 즉시 현재 포커스된 앱에 `⌘V` 시뮬레이션
- **한국어/영어 전환** — `⌥L`로 전사 언어 즉시 전환
- **메뉴바 상주** — Dock에 안 보이고, 메뉴바 아이콘(🎤KR)으로만 동작
- **전사 히스토리** — 최근 10개 전사 결과를 메뉴에서 바로 복사
- **사운드 피드백** — 녹음 시작/종료/완료/오류 시 소리 알림

## 단축키

| 단축키 | 기능 |
|--------|------|
| `⌃⌥` | 녹음 시작/종료 (함께 눌렀다 뗄 때 동작, 다른 키와 조합하면 무시) |
| `⌥L` | 언어 전환 (한국어 ↔ English) |
| `Esc` | 녹음 취소 |

단축키는 메뉴바 > 환경설정에서 변경할 수 있습니다 (`⌥S`, `⌃S` 등 키 조합도 선택 가능). 단축키 입력은 현재 앱으로 전달되지 않습니다.

## 요구 사항

- macOS 14.0+ (Sonoma)
- Apple Silicon 또는 Intel Mac
- [Soniox](https://soniox.com/) API 키 (무료 플랜 사용 가능)

## 빌드

[XcodeGen](https://github.com/yonaskolb/XcodeGen)으로 프로젝트를 관리합니다.

```bash
# XcodeGen 설치 (처음 한 번)
brew install xcodegen

# 프로젝트 생성 & 빌드
xcodegen generate
open Malgeul.xcodeproj
```

Xcode에서 `⌘R`로 빌드 & 실행하면 메뉴바에 🎤 아이콘이 나타납니다.

## 설정

첫 실행 시 `~/.config/voice-recorder/config.json`이 자동 생성됩니다.

```json
{
  "auto_paste": true,
  "lang_hotkey": "alt+l",
  "language": "ko",
  "record_hotkey": "ctrl+alt",
  "soniox_api_key": "YOUR_API_KEY",
  "sound_feedback": true,
  "stt_engine": "soniox"
}
```

`soniox_api_key`에 본인의 API 키를 넣어주세요.

## 권한

첫 실행 시 macOS가 다음 권한을 요청합니다:

- **마이크** — 음성 녹음
- **접근성** (손쉬운 사용) — 글로벌 단축키 + 자동 붙여넣기

시스템 설정 > 개인정보 보호 및 보안에서 Malgeul을 허용해주세요.

## 크레딧

Inspired by [칼퇴왕김과장](https://www.youtube.com/watch?v=qwS0lBADIug)의 맥북 음성인식 영상과 [borinomi/mlx-whisper](https://github.com/borinomi/mlx-whisper).

## 만든 사람

[@itsbluetic](https://www.threads.com/@itsbluetic)

## 라이선스

[MIT](LICENSE)
