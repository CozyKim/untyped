# typeless-like MVP 설계

작성일: 2026-09-07

## 1. 목적

말한 내용을 온디바이스로 전사하고, 온디바이스 LLM으로 다듬어, 현재 커서 위치에
삽입하는 macOS 메뉴바 앱. 네트워크를 타지 않는다.

MVP의 완성 기준은 **핵심 루프 하나**다.

> 핫키를 누른다 → 말하는 동안 화면에 상태와 목소리 레벨이 보인다 → 필러가
> 제거되고 문장부호가 정리된 텍스트가 지금 포커스된 앱의 커서 위치에 들어간다.

이 루프가 손에 익을 만큼 동작하면 MVP는 끝이다. 여기서 얻은 체감으로 다음 범위를
정한다.

## 2. 비목표

의도적으로 제외한다. 필요해지면 그때 넣는다.

- 설정 창 (핫키 변경, 다듬기 강도, 톤 선택)
- 받아쓰기 기록/히스토리
- 오버레이의 실시간 전사 텍스트 (상태와 오디오 레벨은 9절에서 다룬다)
- 앱별 문체 적응
- 한국어 외 언어 전환 UI
- 배포용 패키징 (공증, 자동 업데이트, 샌드박스)

## 3. 검증된 전제

추측이 아니라 이 머신에서 실행해 확인한 사실이다.

| 항목 | 확인값 | 확인 방법 |
| --- | --- | --- |
| macOS | 26.5.2 (Tahoe), arm64 | `sw_vers`, `uname -m` |
| Xcode / Swift | 26.6 / 6.3.3 | `xcodebuild -version`, `swift --version` |
| SpeechTranscriber 한국어 | `ko-KR` 지원, 모델 설치 완료 | `supportedLocales` / `installedLocales` 실행 |
| Foundation Models | `availability == .available` | `SystemLanguageModel.default` 실행 |
| Foundation Models 한국어 | `ko-Kore-KR` 포함 | `supportedLanguages` 실행 |
| Ollama | 설치됨, `qwen3.5:9b` 보유 | `ollama list` |
| 프로젝트 생성 도구 | xcodegen / tuist 모두 없음 | `which` |

API 시그니처는 SDK의 `.swiftinterface`에서 직접 확인했다
(`MacOSX26.5.sdk` 내 `Speech.swiftmodule`, `FoundationModels.swiftmodule`).

### 아직 검증하지 못한 가설

구현 순서를 정하는 근거다. 사실로 취급하지 않는다.

1. 클립보드 백업 + `⌘V` 합성으로 임의의 앱에 텍스트를 넣을 수 있는가, 클립보드를
   언제 복원해야 붙여넣기가 옛 내용을 집어가지 않는가, 그리고 오버레이 패널이
   떠 있어도 원래 앱이 텍스트 포커스를 유지하는가.
2. 오른쪽 `⌥` 단독 키를 `flagsChanged`로 눌림/뗌 모두 안정적으로 받을 수 있는가.
3. 3B 모델이 한국어 구어체를 요약하거나 없던 내용을 지어내지 않고 다듬는가.

## 4. 프로젝트 형태

`.xcodeproj` 대신 SwiftPM 패키지 + 번들 조립 스크립트로 간다.

```
Package.swift              실행 타깃 1개 + 테스트 타깃 1개
Scripts/bundle.sh          실행 파일 + Info.plist → TypelessLike.app 조립, ad-hoc 서명
Resources/Info.plist       LSUIElement, 번들 ID, 마이크 권한 문자열
```

근거:

- 프로젝트 생성 도구가 없어 `.pbxproj`를 손으로 써야 하는데, 그 형식은 diff도
  리뷰도 되지 않는다. 전부 텍스트로 유지하면 변경 추적이 된다.
- 메뉴바 앱에 필요한 Info.plist 항목이 몇 개 안 된다.
- `swift build` / `swift test`로 CLI에서 전부 돌아간다.

최소 배포 타깃은 macOS 26.0, Swift 6 strict concurrency를 켠다.

감수하는 비용: 코드 서명이 수동이다. 재빌드마다 ad-hoc 서명 해시가 바뀌면 손쉬운
사용 권한을 다시 승인해야 할 수 있다. 개발 중 반복되면 고정 서명 신원으로 바꾼다.

## 5. 모듈 구조

```
Sources/TypelessLike/
  App/        MenuBarApp.swift              SwiftUI MenuBarExtra, 상태 아이콘
              OverlayPanel.swift            비활성 NSPanel - 상태 + 레벨 미터
  Core/       DictationState.swift          상태 기계 - 순수, 부수효과 없음
              Coordinator.swift             상태 기계와 실제 컴포넌트 배선
  Input/      HotkeyMonitor.swift           전역 키 이벤트 → TriggerEvent
              AudioCapture.swift            AVAudioEngine → AnalyzerInput + 레벨
              AudioLevel.swift              RMS 계산 - 순수 함수
  Transcribe/ Transcriber.swift             SpeechAnalyzer 래핑 → String
  Refine/     TextRefiner.swift             protocol
              FoundationModelsRefiner.swift
              OllamaRefiner.swift
  Output/     TextInserter.swift            클립보드 백업 → ⌘V 합성 → 복원
Tests/TypelessLikeTests/
              DictationStateTests.swift
              AudioLevelTests.swift
              TextRefinerFallbackTests.swift
```

의존 방향은 한 방향이다.

```
App → Core → { Input, Transcribe, Refine, Output }
```

하위 네 그룹은 서로를 모른다. 강제되는 구체적 규칙:

- `Refine/`은 `Speech`를 import하지 않는다.
- `Transcribe/`는 `FoundationModels`를 import하지 않는다.
- `Output/`은 전사도 다듬기도 모르고, 완성된 문자열만 받는다.

전사 엔진이나 다듬기 백엔드를 갈아끼울 때 서로를 건드리지 않기 위한 경계다.

## 6. 핵심 계약

### TextRefiner

```swift
protocol TextRefiner: Sendable {
    var isAvailable: Bool { get async }
    func refine(_ raw: String) async throws -> String
}
```

입력도 출력도 순수 문자열이다. 오디오, 로케일, 삽입 대상 앱을 모른다. 덕분에
Apple 모델과 Ollama가 같은 계약 아래 들어온다.

구현체가 처음부터 둘 실재하므로 이 추상화는 투기적이지 않다.

- `FoundationModelsRefiner` — `LanguageModelSession(instructions:)` 생성 후
  `respond(to:options:) async throws -> Response<String>` 호출.
  `GenerationOptions(temperature:maximumResponseTokens:)`로 결정성을 높인다.
  가용성은 `SystemLanguageModel.default.isAvailable`로 판단한다.
- `OllamaRefiner` — `http://localhost:11434`에 HTTP 요청. 가용성은 해당 엔드포인트
  응답 여부로 판단한다.

`refine`이 throw하면 Coordinator가 원본 전사 텍스트로 폴백한다.

### 다듬기 지시문

```
받아쓰기 원문을 다듬어라.
내용을 추가하거나 삭제하거나 요약하지 마라.
필러("음", "어", "그")를 제거하고, 말하다 스스로 고친 부분은 최종 의도만 남기고,
문장부호와 띄어쓰기를 정리하라.
원문의 언어를 유지하라.
다듬은 문장만 출력하고 설명을 붙이지 마라.
```

3B 모델의 지배적 실패 모드는 요약과 환각이다. 지시문을 좁게 유지하는 이유다.

출력 길이 검증 같은 방어 로직은 MVP에 넣지 않는다. 그 실패가 실제로 나는지 먼저
관찰하고, 나면 그때 넣는다.

## 7. 상태 기계

부수효과가 없는 순수 함수로 분리한다. 이 프로젝트에서 자동 테스트 가치가 확실한
유일한 지점이다.

```swift
enum DictationState: Equatable {
    case idle
    case holding(since: ContinuousClock.Instant)
    case toggled
    case processing
}

enum TriggerEvent { case keyDown, keyUp }
enum Effect { case startCapture, stopCaptureAndProcess, none }

func reduce(
    _ state: DictationState,
    _ event: TriggerEvent,
    now: ContinuousClock.Instant,
    threshold: Duration
) -> (DictationState, Effect)
```

전이표. `threshold`의 기본값은 250ms다.

| 현재 | 이벤트 | 조건 | 다음 | 효과 |
| --- | --- | --- | --- | --- |
| `idle` | keyDown | | `holding(now)` | `startCapture` |
| `idle` | keyUp | | `idle` | `none` |
| `holding(t0)` | keyUp | `now - t0 < threshold` | `toggled` | `none` |
| `holding(t0)` | keyUp | `now - t0 >= threshold` | `processing` | `stopCaptureAndProcess` |
| `holding(t0)` | keyDown | | `holding(t0)` | `none` |
| `toggled` | keyDown | | `processing` | `stopCaptureAndProcess` |
| `toggled` | keyUp | | `toggled` | `none` |
| `processing` | keyDown | | `processing` | `none` |
| `processing` | keyUp | | `processing` | `none` |

`processing`에서 `idle`로의 복귀는 이벤트가 아니라 Coordinator가 삽입 완료 후
직접 수행한다.

짧게 눌러 `toggled`에 들어간 뒤 다시 누르면 길이와 무관하게 종료된다. 그 종료
keyDown에 뒤따르는 keyUp은 `processing` 상태에서 무시된다.

## 8. 데이터 흐름

```
HotkeyMonitor ──TriggerEvent──▶ Coordinator ──reduce──▶ Effect
                                      │ startCapture
                                      ▼
                     AudioCapture (AVAudioEngine + AVAudioConverter)
                                      │ 레벨(RMS) ─▶ Coordinator ─▶ OverlayPanel
                                      │ AsyncStream<AnalyzerInput>
                                      ▼
                     Transcriber (SpeechAnalyzer + SpeechTranscriber)
                                      │ finalizeAndFinishThroughEndOfInput()
                                      ▼  results 소진 → String
                     TextRefiner.refine(raw) ──throw/타임아웃──▶ raw 그대로
                                      ▼
                     TextInserter (클립보드 백업 → ⌘V → 복원)
                                      ▼
                             Coordinator → idle
```

### 오디오

`SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])`로 목표
포맷을 얻고, `AVAudioConverter`로 마이크 네이티브 포맷을 변환한다. 마이크 포맷을
추측하지 않는다.

변환된 버퍼를 `AnalyzerInput(buffer:)`로 감싸 `AsyncStream`에 흘린다.

### 전사

`SpeechTranscriber(locale: Locale(identifier: "ko-KR"), preset: .transcription)`.

MVP에 실시간 미리보기가 없으므로 `volatileResults`가 필요 없다. 미리보기를 넣을
때 `.progressiveTranscription` 계열로 교체한다.

녹음 종료 시 스트림을 닫고 `finalizeAndFinishThroughEndOfInput()`을 호출한 뒤
`transcriber.results`를 소진하며 텍스트를 이어붙인다.

### 삽입

1. `NSPasteboard.general`의 현재 내용과 `changeCount`를 백업한다.
2. 다듬어진 텍스트를 쓴다.
3. `CGEvent`로 `⌘V`를 합성해 프론트모스트 앱에 보낸다.
4. 지연 후 클립보드를 복원한다.

4번의 지연값은 실측으로 정한다. 너무 짧으면 붙여넣기가 옛 내용을 집어간다.

## 9. 오버레이

녹음 중임을 화면에서 확인할 수 있어야 한다. 메뉴바 아이콘만으로는 시선이 닿지
않는다.

### 표시 내용

상태(`녹음 중` / `다듬는 중`)와 목소리 레벨 미터. **전사 텍스트는 띄우지 않는다.**

"내 목소리가 잡히고 있다"는 확인에는 레벨 미터로 충분하고, 텍스트를 띄우려면
전사를 `.progressiveTranscription`으로 바꾸고 확정되지 않은 중간 결과가 계속
고쳐지는 것을 UI에서 처리해야 한다. 그 비용을 MVP에서 지불하지 않는다.

### 포커스를 빼앗지 않는 것이 핵심 제약

오버레이가 키 윈도우가 되면 원래 앱의 텍스트 포커스가 풀려 8절의 `⌘V` 삽입이
엉뚱한 곳으로 간다. 앱의 핵심 기능이 깨지는 문제다. `NSPanel`을 다음 설정으로
만든다.

| 설정 | 값 | 이유 |
| --- | --- | --- |
| `styleMask` | `[.nonactivatingPanel, .borderless]` | 앱을 활성화시키지 않는다 |
| `canBecomeKey` | `false` (오버라이드) | 키 윈도우가 되지 않는다 |
| `ignoresMouseEvents` | `true` | 클릭이 아래 앱으로 통과한다 |
| `level` | `.floating` | 다른 창 위에 뜬다 |
| `collectionBehavior` | `[.canJoinAllSpaces, .fullScreenAuxiliary]` | 전체화면 앱 위에도 뜬다 |
| `isOpaque` / `backgroundColor` | `false` / `.clear` | 둥근 모서리 배경을 직접 그린다 |

이 조합은 3절 가설 1에 포함되어 있고 삽입 스파이크에서 함께 검증한다. 따로
검증하면 의미가 없다.

### 레벨 계산

`AudioCapture`의 탭에서 이미 받고 있는 버퍼로 RMS를 구한다. 별도 오디오 경로를
만들지 않는다.

```swift
func rms(_ samples: UnsafeBufferPointer<Float>) -> Float
```

포인터를 받는 이유는 오디오 콜백마다 배열을 복사하지 않기 위해서다. 테스트에서는
`[Float]`로부터 만들면 되므로 검증에 지장이 없다.

값은 dB로 변환해 표시 범위로 클램프한다. 별도 스무딩 코드는 넣지 않는다 —
업데이트가 오디오 버퍼 주기로 들어오므로 SwiftUI의 `.animation(.linear)`이
떨림을 흡수한다.

### 상태를 받는 경로

`OverlayPanel`은 `AudioCapture`를 직접 보지 않는다. 5절의 의존 방향을 지키기
위해서다. `Coordinator`가 현재 `DictationState`와 최신 레벨을 관찰 가능한 상태로
노출하고, `OverlayPanel`은 그것만 읽는다.

덕분에 오버레이는 오디오 엔진도 전사도 모른 채 그릴 수 있고, 렌더링 없이
`Coordinator` 상태만으로 동작을 확인할 수 있다.

### 위치와 수명

화면 하단 중앙 고정. 마우스를 따라다니지 않는다.

`idle`에서는 감춘다. `holding` 또는 `toggled`에 들어갈 때 띄우고, 삽입이 끝나
`idle`로 돌아갈 때 감춘다.

## 10. 에러 처리

모든 실패는 "덜 좋은 결과"로 떨어진다. 아무것도 못 하는 상태로 가지 않는다.

| 실패 | 대응 |
| --- | --- |
| Foundation Models 사용 불가 | `isAvailable` 확인 후 Ollama로 폴백 |
| 두 백엔드 모두 불가 | 다듬기를 건너뛰고 원본 전사를 삽입 |
| `refine` throw 또는 5초 타임아웃 | 원본 전사를 삽입 |
| 마이크 권한 없음 | 메뉴바에서 시스템 설정 열기 안내 |
| 손쉬운 사용 권한 없음 | 시작 시 `AXIsProcessTrustedWithOptions`로 확인, 안내 |
| 전사 결과가 빈 문자열 | 아무 동작도 하지 않는다 (빈 붙여넣기 방지) |

원칙: 다듬기 실패가 받아쓰기를 죽이지 않는다. LLM은 품질 향상 레이어이지 필수
경로가 아니다.

## 11. 트리거 키

기본값은 오른쪽 `⌥`(Option) 단독이다.

단독 수식키라 다른 앱의 단축키와 충돌하지 않고, `flagsChanged` 이벤트로 눌림과
뗌을 모두 받을 수 있다. `Fn`은 시스템이 받아쓰기와 이모지 입력에 이미 쓰고 있어
피한다.

이는 아직 검증하지 못한 선택이며 3절의 가설 2번에 해당한다. MVP에서 키는 코드
상수로 두고 변경 UI는 만들지 않는다.

## 12. 테스트 전략

자동화는 가치가 확실한 곳에만 건다.

- `DictationState.reduce` — 7절 전이표를 전수 검증한다. 250ms 경계 양쪽을 모두
  포함한다. `ContinuousClock.Instant`를 인자로 받으므로 시간을 주입해 결정적으로
  테스트된다.
- `AudioLevel.rms` — 무음, 최대 진폭, 빈 버퍼를 검증한다. 순수 함수다.
- `TextRefiner` 폴백 — 항상 throw하는 스텁으로 Coordinator가 원본을 삽입하는지
  검증한다.

오디오 캡처, 전역 키 이벤트, 텍스트 삽입, 오버레이 포커스 동작은 시스템 권한과
실제 하드웨어에 의존해 수동으로 검증한다. 자동화 비용이 얻는 신뢰보다 크다.

## 13. 구현 순서

3절의 미검증 가설을 먼저 없앤다. 1번이 실패하면 설계 전체가 흔들리므로 코드를
쌓기 전에 확인한다.

1. **삽입 + 오버레이 스파이크** — 클립보드 백업/`⌘V` 합성/복원이 실제 앱에서
   동작하는지, 복원 지연은 얼마여야 하는지, 그리고 9절 설정의 `NSPanel`이 떠
   있어도 삽입이 정상인지 확인한다. 결과에 따라 8절 삽입 절차와 9절 패널 설정을
   확정한다.
2. **핫키 스파이크** — 오른쪽 `⌥` 단독의 `flagsChanged` 눌림/뗌 수신을 확인한다.
   실패 시 대체 키를 정한다.
3. `DictationState.reduce` — 테스트 먼저, 그다음 구현.
4. `AudioCapture` + `AudioLevel` + `Transcriber` — 녹음한 한국어가 문자열로
   나오는 데까지. RMS는 테스트 먼저.
5. `TextRefiner` 두 구현체와 폴백 경로. 실제 한국어 구어체 전사를 넣어 6절
   지시문이 요약과 환각을 막는지 확인한다(가설 3). 막지 못하면 방어 로직을
   여기서 추가한다.
6. `Coordinator` 배선 + `MenuBarApp` 상태 아이콘 + `OverlayPanel`.
7. `Scripts/bundle.sh`와 권한 요청 흐름.

1번과 2번의 산출물은 버리는 코드다. 확인이 끝나면 결론만 남기고 폐기한다.
