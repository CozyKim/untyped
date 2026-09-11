# 설정 창 설계

작성일: 2026-09-11

MVP 설계(`2026-09-07-typeless-like-mvp-design.md`) 2절에서 비목표로 뒀던 설정 창을
넣는다. 11절의 "키는 코드 상수로 둔다"는 이 문서로 대체된다.

## 1. 목적

사용자가 파일을 직접 열지 않고 다음을 바꿀 수 있어야 한다.

- 다듬기 서버 주소, 모델명, API 키
- 트리거 단축키 (단독 수식키 중 선택)
- 짧게 눌렀다 떼면 토글 녹음으로 들어가는 동작의 사용 여부

바꾼 값은 저장 즉시 적용된다. 앱 재시작은 필요 없다.

## 2. 비목표

- 임의 키 조합(⌘⇧D 등) 단축키. 단독 수식키만 지원한다 — 현재의 `flagsChanged`
  구조와 hold/toggle 의미를 그대로 쓰기 위해서다.
- Fn, Caps Lock. Fn은 시스템이 받아쓰기·이모지에 쓰고, Caps Lock은 토글식이라
  hold 동작이 성립하지 않는다.
- API 키의 Keychain 저장. 기존 `config.json`(0600)을 그대로 쓴다.
- 필드 변경 즉시 자동 저장. 저장 버튼을 둔다 — API 키 한 글자마다 파일을 쓰거나
  Picker를 바꾸는 순간 핫키 모니터가 교체되는 일이 없어야 한다.
- 다듬기 강도·톤 등 프롬프트 설정.

## 3. 접근 방식

세 가지를 놓고 골랐다.

- **A. 명시적 저장 + 런타임 즉시 적용** — 채택. 설정 창은 `config.json`의 편집기다.
  저장 버튼이 파일을 쓰고 `Coordinator.apply(_:)`가 refiner와 핫키 모니터를 교체한다.
- B. 파일만 쓰고 재시작 요구 — 변경이 가장 적지만 UX가 나쁘고 결국 A로 가게 된다.
- C. Observable 설정 객체 + 자동 저장 — macOS 관례에 가깝지만 2절의 이유로 배제.

## 4. 모듈 구조

```
Sources/TypelessLike/
  App/    MenuBarApp.swift        Settings 씬 추가, "설정…" 메뉴 항목. static refiner 제거
          SettingsView.swift      신규. Form + 초안 편집 + 저장
  Core/   AppConfig.swift         RefinerConfig를 대체. 다섯 필드 + load/save
          Coordinator.swift       init(config:), apply(_:). refiner가 let → var
  Input/  HotkeyKey.swift         신규. 수식키 8개 enum + 순수 판정 함수
          HotkeyMonitor.swift     init(key:onEvent:). 상수 대신 HotkeyKey
Tests/TypelessLikeTests/
          AppConfigTests.swift    신규
          HotkeyKeyTests.swift    신규
          DictationStateTests.swift  threshold .zero 케이스 추가
```

`RefinerConfig`는 핫키까지 담게 되어 이름이 맞지 않으므로 `AppConfig`로 바꾸고
`Refine/`에서 `Core/`로 옮긴다. Coordinator가 소비하는 타입이기 때문이다. "다른 앱의
설정 파일은 절대 읽지 않는다"는 원칙은 그대로다.

Refiner 생성은 `MenuBarApp`의 static에서 `Coordinator`로 옮긴다. Coordinator는 이미
AudioCapture·Transcriber·HotkeyMonitor·TextInserter를 구체 타입으로 아는 유일한
배선 지점이라 `OpenAICompatibleRefiner`를 아는 것도 같은 역할이다. 현재의
`init(refiner:)` 주입은 테스트에서 쓰이지 않는다 — 폴백 테스트는 `refineOrFallback`을
직접 부른다.

## 5. 설정 파일

경로는 그대로 `~/Library/Application Support/TypelessLike/config.json`.

```json
{
  "api_key": "",
  "base_url": "http://127.0.0.1:8081/v1",
  "hotkey": "right_option",
  "model": "gemma-4-e2b-it-8bit",
  "toggle_enabled": true
}
```

`hotkey` 값: `left_option`, `right_option`, `left_command`, `right_command`,
`left_control`, `right_control`, `left_shift`, `right_shift`.

### 호환

- `hotkey`·`toggle_enabled`가 없는 기존 파일은 각각 `right_option`·`true`로 읽는다.
- `hotkey`가 모르는 문자열이면 `right_option`으로 읽고 나머지 필드는 보존한다.
  이 필드 하나 때문에 API 키까지 기본값으로 대체되면 안 된다.
- 그 밖의 JSON 오류·읽기 실패는 기존과 같이 기본값으로 동작한다.

### 쓰기

기존 `writeDefaultFile`의 `createFile(atPath:contents:attributes: [0600])` 경로를
`save(_:to:)`로 일반화해 기본 파일 생성과 사용자 저장이 같은 코드를 쓴다.
`Data.write(to:options: .atomic)`은 임시 파일 뒤 rename이라 권한이 umask로 바뀔 수
있으므로 쓰지 않는다. 디렉터리는 없으면 0700으로 만든다.

테스트를 위해 `load(from:)`와 `save(_:to:)`가 URL을 받고, 기본 인자로 실제 경로를 쓴다.

## 6. HotkeyKey

```swift
enum HotkeyKey: String, Codable, CaseIterable {
    case rightOption = "right_option", leftOption = "left_option"
    case rightCommand = "right_command", leftCommand = "left_command"
    case rightControl = "right_control", leftControl = "left_control"
    case rightShift = "right_shift", leftShift = "left_shift"

    var keyCode: UInt16      // Carbon kVK_*
    var deviceMask: UInt     // IOLLEvent.h NX_DEVICE*KEYMASK
    var displayName: String  // "오른쪽 ⌥ Option"

    /// 이 키의 flagsChanged 이벤트면 눌림 여부, 다른 키면 nil.
    func transition(keyCode: UInt16, modifierFlags: UInt) -> Bool?
}
```

| case | keyCode | deviceMask |
|---|---|---|
| leftCommand | 0x37 | 0x0008 |
| rightCommand | 0x36 | 0x0010 |
| leftShift | 0x38 | 0x0002 |
| rightShift | 0x3C | 0x0004 |
| leftOption | 0x3A | 0x0020 |
| rightOption | 0x3D | 0x0040 |
| leftControl | 0x3B | 0x0001 |
| rightControl | 0x3E | 0x2000 |

값은 SDK의 `HIToolbox/Events.h`와 `IOKit/hidsystem/IOLLEvent.h`에서 확인했다.
`modifierFlags.contains(.option)`은 왼쪽 Option이 눌려도 true라 장치 마스크로 검사하는
기존 이유가 여덟 키 모두에 적용된다.

`allCases` 순서는 오른쪽 키 먼저다. 왼쪽 ⌘·⇧처럼 일상 조합키에 쓰이는 키를 고르면
그 조합키(⌘C 등)를 누를 때마다 녹음이 시작되는 구조라, Picker 아래에 한 줄 안내를 둔다.
막지는 않는다 — 어떤 키를 쓰는지는 사용자가 안다.

`HotkeyMonitor`는 `init(key: HotkeyKey, onEvent:)`로 바뀌고 `handleFlagsChanged`는
`key.transition(...)`을 부른다. 런치 타이밍·로컬/전역 모니터·중복 이벤트 처리는 그대로.

## 7. 런타임 적용

`Coordinator`:

```swift
private(set) var config: AppConfig
private var refiner: any TextRefiner
private var availabilityPoll: Task<Void, Never>?

init(config: AppConfig)
func apply(_ config: AppConfig)
```

`apply(_:)`는 순서대로:

1. `self.config = config`. Observable이라 설정 창이 초안의 출발점으로 읽는다.
2. `refiner = OpenAICompatibleRefiner(baseURL:model:apiKey:)` 재생성.
3. 핫키가 **바뀐 경우에만** 기존 모니터 `stop()` → 새 키로 생성 → `start()`.
   안 바뀌었으면 그대로 둔다. 진행 중인 hold를 끊지 않기 위해서다.
4. 연결 확인 폴링 Task를 취소하고 새로 시작한다. 메뉴의 "연결할 수 없음" 표시가
   최대 10초가 아니라 곧바로 새 서버를 반영한다. 폴링 루프는 `while !Task.isCancelled`.

토글 설정은 `handle()`에서 `threshold`로 표현한다.

```swift
let threshold: Duration = config.toggleEnabled ? DictationTuning.holdThreshold : .zero
```

`reduce`는 바뀌지 않는다. threshold가 0이면 `now - start < 0`이 성립하지 않아 keyUp은
항상 `.processing`으로 간다 — push-to-talk. 아주 짧게 눌러 전사가 비면 기존 빈 문자열
가드가 idle로 돌려보낸다.

녹음 중에 적용해도 상태 기계는 영향이 없다. 새 모니터는 `isDown = false`로 시작하고,
토글 녹음 중이었다면 새 키를 한 번 누르면 평소처럼 종료된다.

## 8. 설정 창

### 열기

`MenuBarApp`에 `Settings { SettingsView(coordinator: coordinator) }` 씬을 추가한다.
메뉴의 "설정…" 항목은 `@Environment(\.openSettings)`를 읽는 작은 뷰로 만들고, 클릭 시
`NSApp.activate()` 뒤에 `openSettings()`를 부른다. `LSUIElement` 앱은 활성화 없이 창을
열면 다른 앱 뒤에 가려질 수 있다.

이 동작은 `Scripts/bundle.sh`로 실제 실행해 확인한다. 창이 앞에 오지 않으면
`OverlayPanel`처럼 `NSWindow`를 직접 만드는 방식으로 바꾼다. `SettingsView`는 어느
쪽에서든 그대로 쓰인다.

### 내용

`Form` 하나, 두 섹션.

```
[다듬기 서버]
  서버 주소   [ http://127.0.0.1:8081/v1        ]
  모델        [ gemma-4-e2b-it-8bit             ]
  API 키      [ ••••••••                        ]   SecureField

[받아쓰기]
  단축키      [ 오른쪽 ⌥ Option            ▾ ]
              다른 앱의 단축키에 자주 쓰이는 키(왼쪽 ⌘ 등)를 고르면
              그 조합키를 누를 때마다 녹음이 시작됩니다.
  ☑ 짧게 눌렀다 떼면 토글 녹음
              끄면 키를 누르는 동안만 녹음합니다.

  (오류 문구)                        [설정 파일 보기…] [저장]
```

### 초안과 저장

`@State private var draft: AppConfig`, `@State private var baseURLText: String`.
창이 나타날 때 `coordinator.config`에서 복사한다. 서버 주소는 `URL` 타입이라 편집 중에는
문자열로 들고 저장 시점에 파싱한다.

저장 버튼:

1. `baseURLText` → `URL`. scheme이나 host가 없으면 오류 문구를 띄우고 중단.
2. `try AppConfig.save(draft)`. 실패하면 오류 문구. 메모리 설정은 그대로.
3. 성공하면 `coordinator.apply(draft)`, 오류 문구 지움.

### 기존 메뉴 정리

- "연결할 수 없음" 아래의 "설정 파일 보기…"는 "설정…"으로 바꾼다. 파일 보기는 설정 창
  안으로 옮긴다.
- 대기 중 상태 문구 "오른쪽 Option을 누르세요"는 `config.hotkey.displayName`을 쓴다.

## 9. 에러 처리

| 상황 | 동작 |
|---|---|
| 서버 주소가 URL이 아님 | "서버 주소가 올바르지 않습니다" 표시, 저장 안 함 |
| 파일 쓰기 실패 | 오류 문구 표시, 메모리 설정 미변경. 로그에는 error만 남기고 설정값은 남기지 않음 |
| 파일 읽기 실패 / JSON 깨짐 | 기존과 동일 — 기본값으로 동작 |
| `hotkey`가 모르는 문자열 | `right_option`으로 읽음. 나머지 필드 보존 |
| 저장 시 다듬기 서버 미연결 | 저장은 성공. 메뉴 상태가 폴링 재시작으로 곧 반영 |

모델명·API 키는 자유 문자열이라 검증하지 않는다. 빈 키는 "헤더를 보내지 않음"이라는
기존 의미 그대로다.

## 10. 테스트

자동화:

- `AppConfig`
  - 인코딩→디코딩 왕복이 동일한 값.
  - `hotkey`·`toggle_enabled`가 없는 기존 형식 JSON → `right_option`, `true`, 다른 필드 보존.
  - `hotkey: "banana"` → `right_option`, 다른 필드 보존.
  - 임시 디렉터리에 `save(_:to:)` 후 `load(from:)` 왕복. 파일 권한이 0600.
- `HotkeyKey.transition(keyCode:modifierFlags:)`
  - 8개 키 각각 눌림/뗌 판정.
  - 다른 키의 keyCode면 `nil`.
  - 오른쪽 ⌥ keyCode에 왼쪽 ⌥ 비트만 켜져 있으면 "뗌". 왼쪽 Option 오판 회귀 방지.
- `reduce` — `threshold: .zero`이면 249ms 탭도 `.processing`.

수동 (`Scripts/bundle.sh`):

- 메뉴 "설정…" → 창이 앞에 뜨는지.
- 단축키를 오른쪽 ⌘로 바꿔 저장 → 즉시 오른쪽 ⌘로 녹음되고 오른쪽 ⌥은 반응 없음.
- 토글 해제 → 짧게 눌렀다 떼면 녹음이 이어지지 않음.
- 서버 주소를 틀린 포트로 저장 → 메뉴에 "연결할 수 없음"이 곧 표시. 되돌리면 사라짐.
- 앱 재시작 후 설정 창이 저장한 값을 보여주는지.
- 기존 `config.json`(세 필드)으로 시작해도 API 키가 유지되는지.
