<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-10-20 | Updated: 2026-10-20 -->

# Sources

## Purpose
Malgeul 앱의 모든 Swift 소스와 번들 메타데이터. 단일 앱 타깃(`Malgeul`)으로 컴파일된다.

## Key Files
| File | Description |
|------|-------------|
| `MalgeulApp.swift` | `@main` SwiftUI `App` 진입점, `AppDelegate` 연결 |
| `AppDelegate.swift` | 실행 시 `StatusBarController` 생성 |
| `StatusBarController.swift` | 메뉴바 아이콘·메뉴 구성, 녹음 토글/취소, 전사→클립보드→`⌘V` 시뮬레이션(`simulatePaste`), 히스토리(최근 10개), 알림 — 앱의 오케스트레이터 |
| `HotkeyManager.swift` | `CGEvent.tapCreate` 기반 글로벌 단축키 (실패 시 listen-only tap 폴백), `"alt+s"` 형식 문자열 파싱, 접근성 권한 체크 |
| `AudioRecorder.swift` | `AVAudioEngine` 입력 탭 → 16kHz mono Int16 PCM으로 변환해 메모리에 누적 |
| `SonioxService.swift` | Soniox WebSocket: config 전송 → 32KB 청크 오디오 전송 → 빈 문자열로 종료 → final 토큰 수집 |
| `ConfigManager.swift` | `AppConfig`(Codable, snake_case 키) 로드/저장, `~/.config/voice-recorder/config.json` |
| `SoundManager.swift` | 시스템 사운드(Tink/Pop/Glass/Funk/Basso) 피드백 |
| `Info.plist` | `LSUIElement=true`(Dock 숨김), 마이크·AppleEvents 사용 설명 |
| `Malgeul.entitlements` | 현재 비어 있음 (샌드박스 미사용 — CGEvent tap·붙여넣기에 필요) |

## For AI Agents

### Working In This Directory
- 새 파일을 추가하면 `project.yml`의 `sources: - Sources`로 자동 포함되지만 `xcodegen generate` 재실행이 필요.
- 오디오 포맷(16kHz/mono/s16le)은 `AudioRecorder`와 `SonioxService` config가 반드시 일치해야 함.
- `AppConfig` 필드 추가 시 `CodingKeys`(snake_case)와 기본값 처리(`load()`)를 함께 갱신 — 기존 사용자 config.json 하위호환 유지.
- 샌드박스 entitlements를 켜면 글로벌 단축키·자동 붙여넣기가 동작하지 않음.
- UI/메뉴 조작은 메인 스레드에서 (`transcribeAndPaste`는 async).

### Testing Requirements
- 단위 테스트 없음. 변경 후 빌드 + 수동 시나리오(녹음/취소/언어 전환/자동 붙여넣기 on·off/히스토리 복사) 확인.

### Common Patterns
- `final class` + 단일 책임, `StatusBarController`가 각 매니저를 소유·조율.
- 에러는 `LocalizedError` enum(`RecorderError` 등)으로 한국어 메시지 제공.

## Dependencies

### Internal
- `StatusBarController` → `ConfigManager`, `HotkeyManager`, `AudioRecorder`, `SonioxService`, `SoundManager`

### External
- AppKit, SwiftUI, AVFoundation, CoreGraphics, UserNotifications, Foundation(URLSessionWebSocketTask)

<!-- MANUAL: -->
