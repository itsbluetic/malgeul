<!-- Generated: 2026-10-20 | Updated: 2026-10-20 -->

# malgeul (말글)

## Purpose
macOS 메뉴바 상주 음성인식 앱. 글로벌 단축키(`⌃⌥`)로 녹음하는 동안 Soniox 실시간 STT(Speech-to-Text, 음성→텍스트) WebSocket으로 스트리밍 전사 → 클립보드 복사 → `⌘V` 시뮬레이션으로 자동 붙여넣기. Swift 네이티브(SwiftUI `App` + AppKit `NSStatusItem`), 외부 의존성 없음.
Python 전신 프로젝트 MySpeak(github.com/itsbluetic/myspeak)의 Swift 재작성판.

## Key Files
| File | Description |
|------|-------------|
| `project.yml` | XcodeGen 스펙 — 타깃·번들 ID(`com.anmen.malgeul`)·macOS 14.0 배포 타깃의 원본 |
| `Malgeul.xcodeproj/` | `xcodegen generate` 산출물 (직접 수정 대신 `project.yml` 수정 후 재생성) |
| `README.md` | 사용자용 기능·단축키·빌드·설정·권한 안내 |
| `LICENSE` | MIT |
| `scripts/install.sh` | Release 빌드 → Apple Development 인증서 재서명 → `/Applications` 교체 → 실행 (접근성 권한 유지) |
| `docs/devlog.md` | 심링크 → Obsidian `P261021_malgeul 음성인식앱/devlog.md` |
| `docs/next-actions.md` | 심링크 → Obsidian `P261021_malgeul 음성인식앱/next-actions.md` |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `Sources/` | 앱 전체 Swift 소스·Info.plist·entitlements (see `Sources/AGENTS.md`) |

## For AI Agents

### Working In This Directory
- 파일 추가/삭제·빌드 설정 변경은 `project.yml`에서 하고 `xcodegen generate`로 `.xcodeproj` 재생성.
- 런타임 설정 파일: `~/.config/voice-recorder/config.json` (첫 실행 시 자동 생성, `soniox_api_key` 포함 — 커밋·로그 출력 금지).
- `.omc/`, `.claude/`는 gitignore 대상.

### Testing Requirements
- 테스트 타깃 없음. 검증은 빌드 + 수동 실행:
  - `xcodebuild -project Malgeul.xcodeproj -scheme Malgeul -configuration Debug build`
  - 설치·실행: `./scripts/install.sh` (전사 지연은 로그의 `transcribe ready mode=... elapsed=...ms`로 확인)
  - 실행 후 메뉴바 아이콘 확인 → `⌃⌥` 녹음/전사/붙여넣기, `⌥L` 언어 전환, `Esc` 취소.
- 마이크·접근성(손쉬운 사용) 권한이 필요. ad-hoc 서명으로 재빌드하면 권한이 풀리므로 `scripts/install.sh`(고정 인증서 서명) 사용.

### Common Patterns
- 각 기능은 `final class` 단일 책임 매니저(Config/Hotkey/Audio/Soniox/Sound)로 분리, `StatusBarController`가 조율.
- 한국어 UI 문자열, `CFBundleDevelopmentRegion = ko`.

## Dependencies

### External
- Soniox real-time STT — `wss://stt-rt.soniox.com/transcribe-websocket`, 모델 `stt-rt-v5`
- Apple 프레임워크: AppKit, SwiftUI, AVFoundation, CoreGraphics(CGEvent tap), UserNotifications
- 빌드 도구: XcodeGen ≥ 2.35, Xcode 15+

<!-- MANUAL: -->
