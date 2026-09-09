# typeless-like MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 핫키를 누르고 말하면, 필러와 말 더듬음이 제거되고 스스로 고친 말은 최종 의도만 남은 텍스트가 지금 포커스된 앱의 커서 위치에 삽입되는 macOS 메뉴바 앱을 만든다.

**Architecture:** 오디오를 `SpeechAnalyzer`로 스트리밍 전사하고, 그 텍스트를 OpenAI 호환 로컬 LLM 서버에 보내 다듬은 뒤, 클립보드와 `⌘V` 합성으로 프론트모스트 앱에 넣는다. 상태 기계는 부수효과 없는 순수 함수로 분리하고, 나머지 컴포넌트는 `Coordinator`가 배선한다.

**Tech Stack:** Swift 6.3 / SwiftPM(외부 패키지 없음) / SwiftUI `MenuBarExtra` / AppKit `NSPanel` / `Speech`(SpeechAnalyzer, SpeechTranscriber) / AVFAudio / Swift Testing

**Spec:** `docs/superpowers/specs/2026-09-07-typeless-like-mvp-design.md`

## Global Constraints

모든 태스크의 요구사항에 암묵적으로 포함된다.

- 최소 배포 타깃 `macOS 26.0`. `swift-tools-version: 6.2`, `platforms: [.macOS(.v26)]`, `swiftLanguageMode(.v6)`.
- 외부 SwiftPM 패키지를 추가하지 않는다. 테스트는 툴체인 내장 Swift Testing(`import Testing`)을 쓴다.
- 의존 방향은 `App → Core → { Input, Transcribe, Refine, Output }` 한 방향이다. `Refine/`은 `Speech`를 import하지 않고, `Transcribe/`는 HTTP도 프롬프트도 모르며, `Output/`은 완성된 문자열만 받는다.
- 다듬기 요청은 `temperature: 0.0`이고, 시스템 프롬프트 끝에 매 요청 고유한 nonce를 붙인다. 붙이지 않으면 서버 캐시가 이전 응답을 돌려주어 말하지 않은 문장이 삽입된다.
- 모든 실패는 원본 전사 삽입으로 떨어진다. 다듬기 실패가 받아쓰기를 죽이지 않는다.
- 커밋 메시지에 생성 도구 서명을 넣지 않는다.
- 기본 다듬기 백엔드: `http://127.0.0.1:8081/v1`, 모델 `gemma-4-e2b-it-8bit`.

---

## File Structure

```
Package.swift                                   실행 타깃 1 + 테스트 타깃 1
Resources/Info.plist                            LSUIElement, 번들 ID, 마이크 권한 문자열
Scripts/bundle.sh                               실행 파일 + Info.plist → .app 조립, ad-hoc 서명
Sources/TypelessLike/
  App/        MenuBarApp.swift                  @main, MenuBarExtra, 상태 아이콘
              OverlayPanel.swift                비활성 NSPanel + 레벨 미터 뷰
              PermissionStatus.swift            마이크·손쉬운 사용 권한 점검과 안내
  Core/       DictationState.swift              상태 기계 - 순수 함수
              Coordinator.swift                 상태 기계와 컴포넌트 배선, 관찰 가능 상태
  Input/      HotkeyMonitor.swift               오른쪽 ⌥ flagsChanged → TriggerEvent
              AudioCapture.swift                AVAudioEngine → AnalyzerInput 스트림 + 레벨
              AudioLevel.swift                  RMS - 순수 함수
  Transcribe/ Transcriber.swift                 SpeechAnalyzer 래핑 → String
  Refine/     TextRefiner.swift                 protocol + 선택/폴백 정책
              RefinementPrompt.swift            규칙 4개 + few-shot 8쌍 + 용어 사전 + nonce
              OpenAICompatibleRefiner.swift     /v1/chat/completions 클라이언트
  Output/     TextInserter.swift                클립보드 백업 → ⌘V → 복원
Tests/TypelessLikeTests/
              DictationStateTests.swift
              AudioLevelTests.swift
              RefinementPromptTests.swift
              TextRefinerFallbackTests.swift
```

Task 2와 3이 만드는 `Spikes/` 산출물은 Task 13에서 삭제한다.

---

### Task 1: 패키지 스캐폴드와 .app 번들 조립

**Files:**
- Create: `Package.swift`
- Create: `Sources/TypelessLike/App/MenuBarApp.swift`
- Create: `Resources/Info.plist`
- Create: `Scripts/bundle.sh`

**Interfaces:**
- Consumes: 없음
- Produces: `swift build`가 통과하는 패키지, `./Scripts/bundle.sh`가 만드는 `build/TypelessLike.app`. 이후 모든 태스크가 이 빌드 경로를 쓴다.

- [ ] **Step 1: `Package.swift` 작성**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TypelessLike",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "TypelessLike",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TypelessLikeTests",
            dependencies: ["TypelessLike"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
```

- [ ] **Step 2: 최소 메뉴바 앱 작성**

`Sources/TypelessLike/App/MenuBarApp.swift`:

```swift
import SwiftUI

@main
struct MenuBarApp: App {
    var body: some Scene {
        MenuBarExtra("TypelessLike", systemImage: "mic") {
            Button("종료") { NSApplication.shared.terminate(nil) }
        }
    }
}
```

- [ ] **Step 3: 빌드 확인**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: `Resources/Info.plist` 작성**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>TypelessLike</string>
  <key>CFBundleIdentifier</key><string>com.jaehyun.typelesslike</string>
  <key>CFBundleName</key><string>TypelessLike</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>말한 내용을 받아쓰기 위해 마이크를 사용합니다.</string>
</dict></plist>
```

`LSUIElement`가 있어야 Dock 아이콘 없이 메뉴바에만 뜬다.

- [ ] **Step 5: `Scripts/bundle.sh` 작성**

```bash
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}/.."
CONF="${1:-debug}"
swift build -c "$CONF" --package-path "$ROOT"
BIN="$(swift build -c "$CONF" --package-path "$ROOT" --show-bin-path)/TypelessLike"
APP="$ROOT/build/TypelessLike.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/TypelessLike"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "$APP"
```

`codesign --force --sign -`는 ad-hoc 서명이다. 재빌드마다 해시가 바뀌어 손쉬운 사용 권한을 다시 승인해야 할 수 있다. 반복이 성가시면 고정 서명 신원으로 바꾼다.

- [ ] **Step 6: 번들 조립과 실행 확인**

Run: `chmod +x Scripts/bundle.sh && ./Scripts/bundle.sh && open build/TypelessLike.app`
Expected: 메뉴바 오른쪽에 마이크 아이콘이 나타나고 Dock에는 뜨지 않는다. 클릭하면 "종료" 항목이 보인다.

- [ ] **Step 7: `.gitignore`에 빌드 산출물 추가**

`.gitignore`에 `build/` 한 줄을 추가한다. `.build/`는 이미 있다.

- [ ] **Step 8: 커밋**

```bash
git add Package.swift Sources Resources Scripts .gitignore
git commit -m "feat: SwiftPM 패키지와 .app 번들 조립 스크립트 추가"
```

---

### Task 2: 삽입 + 오버레이 스파이크 (버리는 코드)

spec 3절 가설 1을 없앤다. 이것이 실패하면 설계 전체가 흔들리므로 코드를 쌓기 전에 확인한다.

**Files:**
- Create: `Spikes/InsertionSpike.swift` (Task 13에서 삭제)

**Interfaces:**
- Consumes: Task 1의 빌드·번들 경로
- Produces: 코드가 아니라 **두 개의 확정값**. (a) 클립보드 복원 지연 밀리초, (b) 삽입을 깨뜨리지 않는 `NSPanel` 설정. Task 10과 11이 이 값을 쓴다.

- [ ] **Step 1: 스파이크 작성**

`Spikes/InsertionSpike.swift`. 별도 실행 파일로 만들지 말고, Task 1의 `MenuBarApp`에 임시 메뉴 항목을 붙여 실행한다. 메뉴를 클릭한 뒤 대상 앱으로 전환할 시간이 필요하므로 3초 지연을 둔다.

```swift
import AppKit

final class SpikePanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

enum InsertionSpike {
    static func makePanel() -> SpikePanel {
        let panel = SpikePanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 56),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        let label = NSTextField(labelWithString: "오버레이 표시 중")
        label.frame = NSRect(x: 16, y: 16, width: 190, height: 24)
        panel.contentView?.addSubview(label)
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 110, y: f.minY + 120))
        }
        return panel
    }

    /// 클립보드를 백업하고 text를 붙여넣은 뒤 restoreDelayMs 후에 복원한다.
    static func insert(_ text: String, restoreDelayMs: Int) {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        let vKeyV: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKeyV, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKeyV, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(restoreDelayMs)) {
            pb.clearContents()
            if let saved { pb.setString(saved, forType: .string) }
        }
    }

    static func run(restoreDelayMs: Int) {
        let panel = makePanel()
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            insert("삽입 테스트 \(restoreDelayMs)ms", restoreDelayMs: restoreDelayMs)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { panel.orderOut(nil) }
        }
    }
}
```

`MenuBarExtra`에 임시로 항목 셋을 추가한다.

```swift
Button("스파이크 50ms") { InsertionSpike.run(restoreDelayMs: 50) }
Button("스파이크 150ms") { InsertionSpike.run(restoreDelayMs: 150) }
Button("스파이크 400ms") { InsertionSpike.run(restoreDelayMs: 400) }
```

- [ ] **Step 2: 손쉬운 사용 권한 부여**

Run: `./Scripts/bundle.sh && open build/TypelessLike.app`
`CGEvent.post`는 손쉬운 사용 권한을 요구한다. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 `TypelessLike.app`을 허용한다.

- [ ] **Step 3: 세 앱에서 각 지연값을 시험**

TextEdit, 브라우저 주소창, Slack 또는 메모 앱에서 각각 한다. 메뉴를 누르고 3초 안에 대상 앱의 텍스트 필드를 클릭해 커서를 둔다.

각 조합에서 기록한다.
- 텍스트가 커서 위치에 들어갔는가
- 옛 클립보드 내용이 대신 들어간 적이 있는가 (지연이 짧으면 발생)
- 붙여넣기 후 클립보드가 원래 내용으로 돌아왔는가
- 오버레이가 떠 있는데도 삽입이 정상이었는가

- [ ] **Step 4: 확정값을 spec에 기록**

세 앱 모두에서 실패하지 않은 가장 작은 지연값을 고른다. spec 8절 "삽입" 4번의 지연값과 9절 패널 설정 표를 그 결과로 확정하고, 어떤 앱에서 시험했는지 적는다.

오버레이가 삽입을 깨뜨렸다면 여기서 멈추고 보고한다. `canBecomeKey`를 `false`로 두었는데도 포커스를 빼앗긴다면 설계를 다시 잡아야 한다.

- [ ] **Step 5: 커밋**

```bash
git add docs Spikes Sources
git commit -m "spike: 클립보드 삽입과 비활성 패널 동시 동작 확인"
```

---

### Task 3: 핫키 스파이크 (버리는 코드)

spec 3절 가설 2를 없앤다.

**Files:**
- Create: `Spikes/HotkeySpike.swift` (Task 13에서 삭제)

**Interfaces:**
- Consumes: Task 1의 번들, Task 2에서 부여한 손쉬운 사용 권한
- Produces: 확정된 트리거 키와 그 keyCode. Task 12가 쓴다.

- [ ] **Step 1: 스파이크 작성**

`Spikes/HotkeySpike.swift`:

```swift
import AppKit

enum HotkeySpike {
    /// 오른쪽 Option 키의 가상 키코드
    static let rightOption: UInt16 = 61

    private static var monitor: Any?
    private static var isDown = false

    static func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            guard event.keyCode == rightOption else { return }
            let down = event.modifierFlags.contains(.option)
            guard down != isDown else { return }
            isDown = down
            NSLog("[HotkeySpike] 오른쪽 Option %@", down ? "눌림" : "뗌")
        }
        NSLog("[HotkeySpike] 감시 시작")
    }
}
```

`flagsChanged`는 수식키의 눌림과 뗌을 모두 보낸다. 눌림·뗌을 가르는 근거는 `modifierFlags`에 `.option`이 남아 있는지다. 같은 상태가 연달아 오는 것을 막으려고 `isDown`으로 걸러낸다.

`MenuBarApp`의 `init`에서 `HotkeySpike.start()`를 호출한다.

- [ ] **Step 2: 실행하고 로그 확인**

Run: `./Scripts/bundle.sh && open build/TypelessLike.app`
그다음 다른 터미널에서 `log stream --predicate 'eventMessage CONTAINS "[HotkeySpike]"'`를 켜 두고 오른쪽 ⌥를 짧게, 길게 여러 번 누른다.

Expected: 누를 때마다 "눌림", 뗄 때마다 "뗌"이 짝을 이뤄 나온다.

- [ ] **Step 3: 충돌 확인**

오른쪽 ⌥를 누른 채 텍스트 필드에 타이핑해 본다. macOS에서 ⌥는 특수문자 입력에 쓰이므로, 감시만 하고 이벤트를 소비하지 않는 `addGlobalMonitorForEvents`가 타이핑을 방해하지 않는지 확인한다.

- [ ] **Step 4: 결과에 따라 키를 확정**

눌림/뗌이 안정적으로 잡히고 타이핑을 방해하지 않으면 오른쪽 ⌥로 확정한다. 실패하면 대체 후보(⌃⌥Space 같은 조합 키)를 정하고 spec 11절을 고친다.

- [ ] **Step 5: 커밋**

```bash
git add docs Spikes Sources
git commit -m "spike: 오른쪽 Option 단독 키의 눌림·뗌 수신 확인"
```

---

### Task 4: DictationState 상태 기계

부수효과가 없는 순수 함수다. 이 프로젝트에서 자동 테스트 가치가 확실한 지점이다.

**Files:**
- Create: `Sources/TypelessLike/Core/DictationState.swift`
- Test: `Tests/TypelessLikeTests/DictationStateTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `enum DictationState: Equatable { case idle, holding(since: ContinuousClock.Instant), toggled, processing }`
  - `enum TriggerEvent { case keyDown, keyUp }`
  - `enum Effect: Equatable { case startCapture, stopCaptureAndProcess, none }`
  - `func reduce(_ state: DictationState, _ event: TriggerEvent, now: ContinuousClock.Instant, threshold: Duration) -> (DictationState, Effect)`
  - `enum DictationTuning { static let holdThreshold: Duration = .milliseconds(250) }`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/TypelessLikeTests/DictationStateTests.swift`. spec 7절 전이표 9행을 전수 검증하고 250ms 경계 양쪽을 모두 포함한다.

```swift
import Testing
import Foundation
@testable import TypelessLike

private let t0 = ContinuousClock.now
private let th = Duration.milliseconds(250)

@Test func idleKeyDownStartsHolding() {
    let (s, e) = reduce(.idle, .keyDown, now: t0, threshold: th)
    #expect(s == .holding(since: t0))
    #expect(e == .startCapture)
}

@Test func idleKeyUpIsIgnored() {
    let (s, e) = reduce(.idle, .keyUp, now: t0, threshold: th)
    #expect(s == .idle)
    #expect(e == .none)
}

@Test func shortPressEntersToggled() {
    let now = t0.advanced(by: .milliseconds(249))
    let (s, e) = reduce(.holding(since: t0), .keyUp, now: now, threshold: th)
    #expect(s == .toggled)
    #expect(e == .none)
}

@Test func longPressStopsImmediately() {
    let now = t0.advanced(by: .milliseconds(250))
    let (s, e) = reduce(.holding(since: t0), .keyUp, now: now, threshold: th)
    #expect(s == .processing)
    #expect(e == .stopCaptureAndProcess)
}

@Test func holdingIgnoresRepeatedKeyDown() {
    let (s, e) = reduce(.holding(since: t0), .keyDown, now: t0.advanced(by: .seconds(1)), threshold: th)
    #expect(s == .holding(since: t0))
    #expect(e == .none)
}

@Test func toggledKeyDownStops() {
    let (s, e) = reduce(.toggled, .keyDown, now: t0, threshold: th)
    #expect(s == .processing)
    #expect(e == .stopCaptureAndProcess)
}

@Test func toggledIgnoresKeyUp() {
    let (s, e) = reduce(.toggled, .keyUp, now: t0, threshold: th)
    #expect(s == .toggled)
    #expect(e == .none)
}

@Test(arguments: [TriggerEvent.keyDown, TriggerEvent.keyUp])
func processingIgnoresEverything(event: TriggerEvent) {
    let (s, e) = reduce(.processing, event, now: t0, threshold: th)
    #expect(s == .processing)
    #expect(e == .none)
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `swift test`
Expected: 컴파일 실패. `cannot find 'reduce' in scope`, `cannot find type 'DictationState' in scope`.

- [ ] **Step 3: 최소 구현 작성**

`Sources/TypelessLike/Core/DictationState.swift`:

```swift
import Foundation

enum DictationState: Equatable, Sendable {
    case idle
    case holding(since: ContinuousClock.Instant)
    case toggled
    case processing
}

enum TriggerEvent: Sendable {
    case keyDown
    case keyUp
}

enum Effect: Equatable, Sendable {
    case startCapture
    case stopCaptureAndProcess
    case none
}

enum DictationTuning {
    /// 이 시간보다 짧게 눌렀다 떼면 토글 녹음으로 들어간다.
    static let holdThreshold: Duration = .milliseconds(250)
}

func reduce(
    _ state: DictationState,
    _ event: TriggerEvent,
    now: ContinuousClock.Instant,
    threshold: Duration
) -> (DictationState, Effect) {
    switch (state, event) {
    case (.idle, .keyDown):
        return (.holding(since: now), .startCapture)
    case (.idle, .keyUp):
        return (.idle, .none)
    case (.holding(let start), .keyUp):
        if now - start < threshold {
            return (.toggled, .none)
        }
        return (.processing, .stopCaptureAndProcess)
    case (.holding(let start), .keyDown):
        return (.holding(since: start), .none)
    case (.toggled, .keyDown):
        return (.processing, .stopCaptureAndProcess)
    case (.toggled, .keyUp):
        return (.toggled, .none)
    case (.processing, _):
        return (.processing, .none)
    }
}
```

`processing`에서 `idle`로의 복귀는 이벤트가 아니라 `Coordinator`가 삽입 완료 후 직접 수행한다(Task 13).

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter DictationStateTests`
Expected: 9개 테스트 전부 통과.

- [ ] **Step 5: 커밋**

```bash
git add Sources/TypelessLike/Core/DictationState.swift Tests/TypelessLikeTests/DictationStateTests.swift
git commit -m "feat: 받아쓰기 상태 기계 추가

짧게 눌러 토글, 길게 눌러 push-to-talk를 250ms 경계로 가른다.
부수효과가 없는 순수 함수라 시간을 주입해 전이표를 전수 검증한다."
```

---

### Task 5: AudioLevel RMS 계산

**Files:**
- Create: `Sources/TypelessLike/Input/AudioLevel.swift`
- Test: `Tests/TypelessLikeTests/AudioLevelTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `func rms(_ samples: UnsafeBufferPointer<Float>) -> Float`
  - `func meterLevel(_ rms: Float) -> Float` — 0…1로 정규화된 표시용 값
  - Task 6이 `rms`를, Task 11이 `meterLevel`을 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/TypelessLikeTests/AudioLevelTests.swift`:

```swift
import Testing
@testable import TypelessLike

@Test func rmsOfEmptyBufferIsZero() {
    let samples: [Float] = []
    #expect(samples.withUnsafeBufferPointer { rms($0) } == 0)
}

@Test func rmsOfSilenceIsZero() {
    let samples = [Float](repeating: 0, count: 512)
    #expect(samples.withUnsafeBufferPointer { rms($0) } == 0)
}

@Test func rmsOfFullScaleIsOne() {
    let samples = [Float](repeating: 1, count: 512)
    let value = samples.withUnsafeBufferPointer { rms($0) }
    #expect(abs(value - 1) < 0.0001)
}

@Test func rmsIgnoresSign() {
    let a: [Float] = [0.5, 0.5, 0.5, 0.5]
    let b: [Float] = [-0.5, 0.5, -0.5, 0.5]
    let ra = a.withUnsafeBufferPointer { rms($0) }
    let rb = b.withUnsafeBufferPointer { rms($0) }
    #expect(abs(ra - rb) < 0.0001)
}

@Test func meterLevelIsClampedToUnitRange() {
    #expect(meterLevel(0) == 0)
    #expect(meterLevel(10) == 1)
    let mid = meterLevel(0.1)
    #expect(mid > 0 && mid < 1)
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `swift test --filter AudioLevelTests`
Expected: 컴파일 실패. `cannot find 'rms' in scope`.

- [ ] **Step 3: 구현 작성**

`Sources/TypelessLike/Input/AudioLevel.swift`:

```swift
import Foundation

/// 오디오 콜백마다 배열을 복사하지 않으려고 포인터를 받는다.
/// 테스트에서는 [Float]로부터 만들면 되므로 검증에 지장이 없다.
func rms(_ samples: UnsafeBufferPointer<Float>) -> Float {
    guard !samples.isEmpty else { return 0 }
    var sum: Float = 0
    for s in samples { sum += s * s }
    return (sum / Float(samples.count)).squareRoot()
}

/// RMS를 dB로 바꿔 표시 범위(-60dB ~ 0dB)로 클램프한 0…1 값.
/// 선형 RMS를 그대로 그리면 말소리 구간이 막대 아래쪽에 몰려 안 보인다.
func meterLevel(_ value: Float) -> Float {
    guard value > 0 else { return 0 }
    let db = 20 * log10(value)
    let floorDB: Float = -60
    return max(0, min(1, (db - floorDB) / -floorDB))
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter AudioLevelTests`
Expected: 5개 테스트 전부 통과.

- [ ] **Step 5: 커밋**

```bash
git add Sources/TypelessLike/Input/AudioLevel.swift Tests/TypelessLikeTests/AudioLevelTests.swift
git commit -m "feat: 오디오 레벨 RMS 계산 추가"
```

---

### Task 6: AudioCapture

**Files:**
- Create: `Sources/TypelessLike/Input/AudioCapture.swift`

**Interfaces:**
- Consumes: `rms(_:)` (Task 5)
- Produces:
  - `actor AudioCapture`
  - `init(targetFormat: AVAudioFormat, onLevel: @Sendable @escaping (Float) -> Void)`
  - `func start() throws -> AsyncStream<AnalyzerInput>`
  - `func stop()`
  - `var recordedDuration: Duration { get }` — Task 13이 타임아웃 계산에 쓴다.

- [ ] **Step 1: 구현 작성**

`Sources/TypelessLike/Input/AudioCapture.swift`:

```swift
import AVFAudio
import Foundation
import Speech

/// 마이크를 열어 전사기가 요구하는 포맷으로 변환한 버퍼를 흘린다.
/// 목표 포맷은 호출자가 정한다. 마이크 네이티브 포맷을 추측하지 않는다.
actor AudioCapture {
    private let engine = AVAudioEngine()
    private let targetFormat: AVAudioFormat
    private let onLevel: @Sendable (Float) -> Void
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var startedAt: ContinuousClock.Instant?
    private var stoppedAt: ContinuousClock.Instant?

    init(targetFormat: AVAudioFormat, onLevel: @escaping @Sendable (Float) -> Void) {
        self.targetFormat = targetFormat
        self.onLevel = onLevel
    }

    var recordedDuration: Duration {
        guard let startedAt else { return .zero }
        return (stoppedAt ?? ContinuousClock.now) - startedAt
    }

    func start() throws -> AsyncStream<AnalyzerInput> {
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        continuation = cont

        let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: source, to: targetFormat) else {
            throw AudioCaptureError.converterUnavailable
        }
        let ratio = targetFormat.sampleRate / source.sampleRate
        let level = onLevel

        input.installTap(onBus: 0, bufferSize: 4096, format: source) { buffer, _ in
            if let channel = buffer.floatChannelData?[0] {
                let value = rms(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                level(value)
            }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return }
            var consumed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, out.frameLength > 0 else { return }
            cont.yield(AnalyzerInput(buffer: out))
        }

        engine.prepare()
        try engine.start()
        startedAt = ContinuousClock.now
        stoppedAt = nil
        return stream
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        stoppedAt = ContinuousClock.now
        continuation?.finish()
        continuation = nil
    }
}

enum AudioCaptureError: Error {
    case converterUnavailable
}
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build`
Expected: `Build complete!`

자동 테스트는 붙이지 않는다. 마이크 하드웨어와 권한에 의존해 자동화 비용이 얻는 신뢰보다 크다(spec 12절). 실제 검증은 Task 7에서 전사와 함께 한다.

- [ ] **Step 3: 커밋**

```bash
git add Sources/TypelessLike/Input/AudioCapture.swift
git commit -m "feat: 마이크 캡처와 포맷 변환 추가

목표 포맷은 호출자가 정한다. 전사기가 알려준 포맷으로 변환하므로
마이크 네이티브 포맷을 추측하지 않는다."
```

---

### Task 7: Transcriber

**Files:**
- Create: `Sources/TypelessLike/Transcribe/Transcriber.swift`

**Interfaces:**
- Consumes: `AudioCapture`가 만드는 `AsyncStream<AnalyzerInput>` (Task 6)
- Produces:
  - `actor Transcriber`
  - `static func targetAudioFormat() async throws -> AVAudioFormat` — Task 6과 13이 `AudioCapture` 생성에 쓴다.
  - `func begin(inputSequence: AsyncStream<AnalyzerInput>) async throws`
  - `func finish() async throws -> String`

- [ ] **Step 1: 구현 작성**

`Sources/TypelessLike/Transcribe/Transcriber.swift`:

```swift
import AVFAudio
import Foundation
import Speech

/// SpeechAnalyzer와 SpeechTranscriber를 감싸 오디오 스트림을 문자열로 만든다.
/// HTTP도 프롬프트도 모른다.
actor Transcriber {
    private let locale: Locale
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var collector: Task<String, Error>?

    init(locale: Locale = Locale(identifier: "ko-KR")) {
        self.locale = locale
    }

    /// 전사기가 요구하는 오디오 포맷. AudioCapture가 여기에 맞춰 변환한다.
    static func targetAudioFormat(locale: Locale = Locale(identifier: "ko-KR")) async throws -> AVAudioFormat {
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw TranscriberError.noCompatibleAudioFormat
        }
        return format
    }

    func begin(inputSequence: AsyncStream<AnalyzerInput>) async throws {
        // MVP에 실시간 미리보기가 없으므로 volatileResults가 필요 없다.
        // 미리보기를 넣을 때 .progressiveTranscription 계열로 교체한다.
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        let engine = SpeechAnalyzer(modules: [module])
        transcriber = module
        analyzer = engine

        collector = Task {
            var text = ""
            for try await result in module.results {
                text += String(result.text.characters)
            }
            return text
        }
        try await engine.start(inputSequence: inputSequence)
    }

    /// 입력 스트림이 닫힌 뒤 호출한다. 남은 결과를 마무리하고 전체 텍스트를 돌려준다.
    func finish() async throws -> String {
        guard let analyzer, let collector else { return "" }
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = try await collector.value
        self.analyzer = nil
        self.transcriber = nil
        self.collector = nil
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TranscriberError: Error {
    case noCompatibleAudioFormat
}
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: 수동 검증 도구를 임시로 붙인다**

`MenuBarApp`에 임시 메뉴 항목 "전사 15초"를 추가한다. 누르면 `AudioCapture`와 `Transcriber`를 이어 15초 녹음하고 결과를 `NSLog`로 찍는다.

```swift
Button("전사 15초") {
    Task {
        let format = try await Transcriber.targetAudioFormat()
        let capture = AudioCapture(targetFormat: format) { level in
            // 레벨은 Task 11에서 오버레이에 연결한다. 지금은 확인용으로만 찍는다.
            if level > 0.05 { NSLog("[level] %.3f", level) }
        }
        let transcriber = Transcriber()
        let stream = try await capture.start()
        try await transcriber.begin(inputSequence: stream)
        try await Task.sleep(for: .seconds(15))
        await capture.stop()
        let text = try await transcriber.finish()
        NSLog("[전사] %@", text)
    }
}
```

- [ ] **Step 4: 실제로 말해 확인**

Run: `./Scripts/bundle.sh && open build/TypelessLike.app`
메뉴에서 "전사 15초"를 누르고 한국어로 말한다. 마이크 권한 승인을 한 번 묻는다.

`log stream --predicate 'eventMessage CONTAINS "[전사]"'`로 결과를 본다.

Expected: 말한 내용이 한국어 문자열로 찍힌다. 빈 문자열이면 마이크가 잡히지 않은 것이므로 `[level]` 로그가 나오는지부터 확인한다.

- [ ] **Step 5: 커밋**

```bash
git add Sources/TypelessLike/Transcribe/Transcriber.swift Sources/TypelessLike/App/MenuBarApp.swift
git commit -m "feat: SpeechAnalyzer 전사 추가

전사는 말하는 동안 스트리밍으로 진행되므로 녹음이 끝난 시점에는
사실상 완료돼 있다. 체감 지연은 이후 다듬기 시간이 전부다."
```

---

### Task 8: RefinementPrompt

spec 6절에 프롬프트가 확정돼 있다. 새로 탐색하지 않고 그대로 옮긴다.

**Files:**
- Create: `Sources/TypelessLike/Refine/RefinementPrompt.swift`
- Test: `Tests/TypelessLikeTests/RefinementPromptTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `struct ChatMessage: Codable, Sendable { let role: String; let content: String }`
  - `enum RefinementPrompt { static func messages(for raw: String) -> [ChatMessage] }`
  - Task 9가 `messages(for:)`를 호출해 요청 본문을 만든다.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/TypelessLikeTests/RefinementPromptTests.swift`:

```swift
import Testing
@testable import TypelessLike

@Test func systemPromptCarriesFourRulesAndGlossary() {
    let messages = RefinementPrompt.messages(for: "테스트")
    let system = messages.first
    #expect(system?.role == "system")
    let text = system?.content ?? ""
    for marker in ["1.", "2.", "3.", "4."] {
        #expect(text.contains(marker))
    }
    #expect(!text.contains("5."))  // 규칙을 넷보다 늘리면 성능이 떨어진다
    #expect(text.contains("langchain"))
    #expect(text.contains("typeless"))
    #expect(text.contains("사전에 없는 말은 손대지 않는다"))
}

@Test func eightFewShotPairsPrecedeTheInput() {
    let messages = RefinementPrompt.messages(for: "원문")
    // system 1 + (user, assistant) * 8 + user 1 = 18
    #expect(messages.count == 18)
    #expect(messages.last?.role == "user")
    #expect(messages.last?.content == "원문")
    let shots = messages.dropFirst().dropLast()
    #expect(shots.count == 16)
    for (index, message) in shots.enumerated() {
        #expect(message.role == (index % 2 == 0 ? "user" : "assistant"))
    }
}

@Test func nonceDiffersOnEveryCall() {
    let a = RefinementPrompt.messages(for: "같은 입력").first?.content ?? ""
    let b = RefinementPrompt.messages(for: "같은 입력").first?.content ?? ""
    #expect(a != b)
}
```

세 번째 테스트가 회귀 가드다. nonce가 고정되면 서버 프롬프트 캐시가 이전 응답을 돌려주어 말하지 않은 문장이 삽입된다(spec 3절).

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `swift test --filter RefinementPromptTests`
Expected: 컴파일 실패. `cannot find 'RefinementPrompt' in scope`.

- [ ] **Step 3: 구현 작성**

`Sources/TypelessLike/Refine/RefinementPrompt.swift`:

```swift
import Foundation

struct ChatMessage: Codable, Sendable {
    let role: String
    let content: String
}

enum RefinementPrompt {
    /// 음차된 용어를 되돌릴 후보 집합. 음차와 영문의 대응을 주지 않는다.
    /// 대응을 병기한 판은 점수가 같으면서 길이만 늘어 희석을 키운다.
    /// 항목을 늘릴 때는 회귀 스위트로 확인한다.
    static let glossary = """
    PR, approve, review, merge, main, branch, commit, rebase, push, pull, revert, \
    deploy, staging, production, rollback, endpoint, timeout, retry, logic, log, debug, error, \
    authentication, authorization, token, refactoring, dependency, injection, container, restart, \
    cache, migration, schema, queue, worker, latency, throughput, build, release, hotfix, \
    agent, subagent, orchestrator, prompt, context, embedding, langchain, typeless, diagram, \
    TTS, STT, LLM, API, SDK, CLI, UI, repo, config
    """

    /// 규칙은 넷을 넘기지 않는다. 같은 내용을 여섯으로 나눠 쓴 판이
    /// 회귀 스위트에서 더 낮은 점수를 냈다. 규칙이 많아지면 각각의 영향력이 희석된다.
    private static func rules(nonce: String) -> String {
        """
        받아쓰기 원문을 다듬는다.
        1. 정정 표시어('아니', '아니다', '그게 아니라')가 나오면 표시어와 그 앞의 말을 전부 지우고 \
        뒤의 말만 남긴다. 앞뒤 주제가 달라도 마찬가지다. 문장이 길고 절이 여러 개여도 똑같이 적용한다.
        2. 군말(어, 음, 그, 그 뭐지)과 더듬어 반복한 말을 지운다.
        3. 아래 사전의 단어가 음차돼 있으면 영문으로 되돌린다. 사전에 없는 말은 손대지 않는다.
          사전: \(glossary)
        4. 문장부호와 띄어쓰기를 정리한다. 그 외의 내용은 바꾸지 않는다.
        다듬은 문장만 출력한다. [\(nonce)]
        """
    }

    private static let fewShots: [(String, String)] = [
        // 1. 짧은 문장의 정정
        ("어 내일 아침에 자료를 보내드릴게요 아니 오늘 저녁에 자료를 보내드릴게요",
         "오늘 저녁에 자료를 보내드릴게요."),
        // 2. 필러만 있는 경우
        ("그 뭐지 그 회의실을 음 3층으로 잡아줘",
         "회의실을 3층으로 잡아줘."),
        // 3. 문장 일부만 정정되고 나머지는 보존
        ("보고서는 김 대리가 쓰고 발표는 이 과장이 하기로 했는데 아니 발표도 김 대리가 합니다",
         "보고서는 김 대리가 쓰고 발표도 김 대리가 합니다."),
        // 4. 음차된 개발 용어를 영문으로
        ("제플로이는 스테이징에 먼저 하고 프로덕션은 그 다음에 하고 로그도 체크해주세요",
         "deploy는 staging에 먼저 하고 production은 그 다음에 하고 log도 확인해주세요."),
        // 5. 영어 용어가 없는 순수 한국어 - 손대지 않는다
        ("이번 분기 목표는 신규 사용자 확보하고 이탈률을 낮추는 겁니다",
         "이번 분기 목표는 신규 사용자 확보하고 이탈률을 낮추는 겁니다."),
        // 6. 주제가 전환되는 정정 - 앞 절을 통째로 버린다
        ("엑셀로 정리하려고 했는데 아 아니다 그게 아니라 대시보드로 보여주고 싶어",
         "대시보드로 보여주고 싶어."),
        // 7. 주제 전환 정정과 용어 복원이 겹치는 경우
        ("배포 자동화를 먼저 하려고 했거든 아 아니다 그게 아니라 테스트 커버리지부터 올리는 게 급해",
         "test coverage부터 올리는 게 급해."),
        // 8. 음절을 더듬어 반복한 경우
        ("그 다 다이얼 다 다이어그램으로 그려줘 그려줘",
         "다이어그램으로 그려줘."),
    ]

    static func messages(for raw: String) -> [ChatMessage] {
        var messages = [ChatMessage(role: "system", content: rules(nonce: UUID().uuidString.prefix(8).lowercased()))]
        for (input, output) in fewShots {
            messages.append(ChatMessage(role: "user", content: input))
            messages.append(ChatMessage(role: "assistant", content: output))
        }
        messages.append(ChatMessage(role: "user", content: raw))
        return messages
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter RefinementPromptTests`
Expected: 3개 테스트 전부 통과.

- [ ] **Step 5: 커밋**

```bash
git add Sources/TypelessLike/Refine/RefinementPrompt.swift Tests/TypelessLikeTests/RefinementPromptTests.swift
git commit -m "feat: 다듬기 프롬프트 추가

규칙 4개와 few-shot 8쌍, 용어 사전으로 구성한다. 시스템 프롬프트 끝의
nonce는 서버 프롬프트 캐시가 이전 응답을 돌려주는 것을 막는다.
nonce가 고정되면 말하지 않은 문장이 삽입되므로 회귀 테스트를 건다."
```

---

### Task 9: TextRefiner와 OpenAICompatibleRefiner

**Files:**
- Create: `Sources/TypelessLike/Refine/TextRefiner.swift`
- Create: `Sources/TypelessLike/Refine/OpenAICompatibleRefiner.swift`
- Test: `Tests/TypelessLikeTests/TextRefinerFallbackTests.swift`

**Interfaces:**
- Consumes: `RefinementPrompt.messages(for:)`, `ChatMessage` (Task 8)
- Produces:
  - `protocol TextRefiner: Sendable { var isAvailable: Bool { get async }; func refine(_ raw: String) async throws -> String }`
  - `func refineOrFallback(_ raw: String, using refiner: (any TextRefiner)?, timeout: Duration) async -> String`
  - `func refineTimeout(for recorded: Duration) -> Duration`
  - `struct OpenAICompatibleRefiner: TextRefiner`
  - Task 13이 `refineOrFallback`과 `refineTimeout`을 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/TypelessLikeTests/TextRefinerFallbackTests.swift`:

```swift
import Testing
import Foundation
@testable import TypelessLike

private struct ThrowingRefiner: TextRefiner {
    var isAvailable: Bool { get async { true } }
    func refine(_ raw: String) async throws -> String {
        throw URLError(.cannotConnectToHost)
    }
}

private struct SlowRefiner: TextRefiner {
    var isAvailable: Bool { get async { true } }
    func refine(_ raw: String) async throws -> String {
        try await Task.sleep(for: .seconds(10))
        return "늦게 온 결과"
    }
}

private struct EchoRefiner: TextRefiner {
    var isAvailable: Bool { get async { true } }
    func refine(_ raw: String) async throws -> String { "다듬음: " + raw }
}

@Test func throwingRefinerFallsBackToRawText() async {
    let out = await refineOrFallback("원본 전사", using: ThrowingRefiner(), timeout: .seconds(5))
    #expect(out == "원본 전사")
}

@Test func timeoutFallsBackToRawText() async {
    let out = await refineOrFallback("원본 전사", using: SlowRefiner(), timeout: .milliseconds(200))
    #expect(out == "원본 전사")
}

@Test func missingRefinerFallsBackToRawText() async {
    let out = await refineOrFallback("원본 전사", using: nil, timeout: .seconds(5))
    #expect(out == "원본 전사")
}

@Test func workingRefinerResultIsUsed() async {
    let out = await refineOrFallback("원본 전사", using: EchoRefiner(), timeout: .seconds(5))
    #expect(out == "다듬음: 원본 전사")
}

@Test func timeoutGrowsWithRecordingLength() {
    // 4초 + 길이 * 0.4
    #expect(refineTimeout(for: .seconds(5)) == .seconds(6))
    #expect(refineTimeout(for: .seconds(30)) == .seconds(16))
}
```

지연은 발화 길이에 비례하지 않는다. 17.2초 발화가 7.60초 걸린 반면 30.6초 발화는 5.42초에 끝났다. 계수는 실측 최댓값에 1.4배 여유를 둔 값이다(spec 10절).

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `swift test --filter TextRefinerFallbackTests`
Expected: 컴파일 실패. `cannot find 'refineOrFallback' in scope`.

- [ ] **Step 3: 프로토콜과 폴백 정책 작성**

`Sources/TypelessLike/Refine/TextRefiner.swift`:

```swift
import Foundation

/// 입력도 출력도 순수 문자열이다. 오디오, 로케일, 삽입 대상 앱을 모른다.
protocol TextRefiner: Sendable {
    var isAvailable: Bool { get async }
    func refine(_ raw: String) async throws -> String
}

/// 녹음 길이에 비례하는 타임아웃. 고정값을 쓰면 긴 발화가 항상 폴백된다.
func refineTimeout(for recorded: Duration) -> Duration {
    .seconds(4) + recorded * 0.4
}

/// 다듬기가 실패하거나 늦으면 원본 전사를 그대로 돌려준다.
/// 다듬기는 품질 향상 레이어이지 필수 경로가 아니다.
func refineOrFallback(
    _ raw: String,
    using refiner: (any TextRefiner)?,
    timeout: Duration
) async -> String {
    guard let refiner else { return raw }
    return await withTaskGroup(of: String?.self) { group in
        group.addTask {
            try? await refiner.refine(raw)
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        guard let first, !first.isEmpty else { return raw }
        return first
    }
}
```

- [ ] **Step 4: HTTP 클라이언트 작성**

`Sources/TypelessLike/Refine/OpenAICompatibleRefiner.swift`:

```swift
import Foundation

/// oMLX, Ollama, LM Studio가 모두 같은 형식을 쓴다.
/// 구현체를 늘리지 않고 baseURL과 model만 바꿔 백엔드를 갈아끼운다.
struct OpenAICompatibleRefiner: TextRefiner {
    let baseURL: URL
    let model: String
    let apiKey: String?

    private struct Request: Encodable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let max_tokens: Int
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    var isAvailable: Bool {
        get async {
            var request = URLRequest(url: baseURL.appendingPathComponent("models"))
            request.timeoutInterval = 2
            if let apiKey {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        }
    }

    func refine(_ raw: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        // temperature 0으로 고정한다. 같은 말에 같은 결과가 나와야 한다.
        request.httpBody = try JSONEncoder().encode(
            Request(model: model, messages: RefinementPrompt.messages(for: raw),
                    temperature: 0, max_tokens: 900)
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RefinerError.badStatus
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw RefinerError.emptyResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum RefinerError: Error {
    case badStatus
    case emptyResponse
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test --filter TextRefinerFallbackTests`
Expected: 5개 테스트 전부 통과.

- [ ] **Step 6: 실제 서버로 확인**

oMLX가 `127.0.0.1:8081`에서 떠 있는 상태에서, `MenuBarApp`의 임시 "전사 15초" 항목에 다듬기를 이어 붙여 결과를 `NSLog`로 찍는다. API 키는 `~/.omlx/settings.json`의 `auth.api_key`에 있다.

Expected: 필러가 제거되고 정정이 반영된 문장이 찍힌다. 서버를 끄면 원본 전사가 그대로 찍힌다.

- [ ] **Step 7: 커밋**

```bash
git add Sources/TypelessLike/Refine Tests/TypelessLikeTests/TextRefinerFallbackTests.swift
git commit -m "feat: OpenAI 호환 다듬기 백엔드와 폴백 정책 추가

구현체는 하나다. oMLX, Ollama, LM Studio가 같은 형식을 쓰므로
baseURL과 model만 바꿔 갈아끼운다.

타임아웃은 녹음 길이에 비례시킨다. 지연이 길이에 비례하지 않고
정정 횟수가 지배하므로 고정값은 긴 발화를 항상 폴백시킨다."
```

---

### Task 10: TextInserter

Task 2에서 확정한 지연값을 쓴다.

**Files:**
- Create: `Sources/TypelessLike/Output/TextInserter.swift`
- Delete: `Spikes/InsertionSpike.swift`의 삽입 부분 (Task 13에서 일괄 삭제)

**Interfaces:**
- Consumes: Task 2가 확정한 클립보드 복원 지연값
- Produces:
  - `enum TextInserter { static func insert(_ text: String) async }`
  - `static var hasAccessibilityPermission: Bool { get }`
  - `static func requestAccessibilityPermission()`
  - Task 13이 셋 다 쓴다.

- [ ] **Step 1: 구현 작성**

`Sources/TypelessLike/Output/TextInserter.swift`. `restoreDelay`는 Task 2에서 실측한 값으로 채운다. 아래는 자리표시가 아니라 시작값이며, Task 2가 다른 값을 내놓으면 그 값으로 바꾼다.

```swift
import AppKit
import ApplicationServices

/// 완성된 문자열만 받는다. 전사도 다듬기도 모른다.
enum TextInserter {
    /// 붙여넣기가 클립보드를 읽기 전에 복원하면 옛 내용이 들어간다.
    /// 여러 앱에서 실측해 실패하지 않은 가장 작은 값이다.
    static let restoreDelay: Duration = .milliseconds(150)

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func insert(_ text: String) async {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postCommandV()

        try? await Task.sleep(for: restoreDelay)
        pasteboard.clearContents()
        if let saved {
            pasteboard.setString(saved, forType: .string)
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyV: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyV, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: 커밋**

```bash
git add Sources/TypelessLike/Output/TextInserter.swift
git commit -m "feat: 클립보드 경유 텍스트 삽입 추가

클립보드를 백업하고 ⌘V를 합성한 뒤 복원한다. 복원 지연은
여러 앱에서 실측한 값이다. 너무 짧으면 붙여넣기가 옛 내용을 집어간다."
```

---

### Task 11: OverlayPanel

Task 2에서 확정한 패널 설정을 쓴다.

**Files:**
- Create: `Sources/TypelessLike/App/OverlayPanel.swift`

**Interfaces:**
- Consumes: `meterLevel(_:)` (Task 5), Task 2가 확정한 패널 설정
- Produces:
  - `@MainActor final class OverlayController`
  - `func show(status: OverlayStatus)`, `func update(level: Float)`, `func hide()`
  - `enum OverlayStatus: String { case recording = "녹음 중", refining = "다듬는 중" }`
  - Task 13이 `Coordinator`에서 호출한다.

- [ ] **Step 1: 구현 작성**

`Sources/TypelessLike/App/OverlayPanel.swift`:

```swift
import AppKit
import SwiftUI

enum OverlayStatus: String, Sendable {
    case recording = "녹음 중"
    case refining = "다듬는 중"
}

/// 키 윈도우가 되면 원래 앱의 텍스트 포커스가 풀려 ⌘V 삽입이 엉뚱한 곳으로 간다.
/// canBecomeKey를 false로 두는 것이 이 클래스의 존재 이유다.
private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private let model = OverlayModel()

    func show(status: OverlayStatus) {
        model.status = status
        if panel == nil { panel = makePanel() }
        positionAtBottomCenter()
        panel?.orderFrontRegardless()
    }

    func update(level: Float) {
        model.level = meterLevel(level)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 64),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        return panel
    }

    private func positionAtBottomCenter() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - 120, y: frame.minY + 120))
    }
}

@Observable
final class OverlayModel {
    var status: OverlayStatus = .recording
    var level: Float = 0
}

private struct OverlayView: View {
    @Bindable var model: OverlayModel

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(model.status == .recording ? Color.red : Color.orange)
                .frame(width: 10, height: 10)
            Text(model.status.rawValue)
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
            LevelMeter(level: model.level)
                .frame(width: 90, height: 12)
        }
        .padding(.horizontal, 16)
        .frame(width: 240, height: 64)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(.tint)
                    .frame(width: geometry.size.width * CGFloat(level))
            }
        }
        // 버퍼 주기로 값이 들어오므로 별도 스무딩 코드 없이 여기서 떨림을 흡수한다.
        .animation(.linear(duration: 0.1), value: level)
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: 커밋**

```bash
git add Sources/TypelessLike/App/OverlayPanel.swift
git commit -m "feat: 상태와 레벨 미터 오버레이 추가

키 윈도우가 되지 않는 NSPanel이다. 키 윈도우가 되면 원래 앱의
텍스트 포커스가 풀려 붙여넣기가 엉뚱한 곳으로 간다."
```

---

### Task 12: HotkeyMonitor

Task 3에서 확정한 키를 쓴다.

**Files:**
- Create: `Sources/TypelessLike/Input/HotkeyMonitor.swift`

**Interfaces:**
- Consumes: `TriggerEvent` (Task 4), Task 3이 확정한 키코드
- Produces:
  - `@MainActor final class HotkeyMonitor`
  - `init(onEvent: @escaping @MainActor (TriggerEvent) -> Void)`
  - `func start()`, `func stop()`

- [ ] **Step 1: 구현 작성**

`Sources/TypelessLike/Input/HotkeyMonitor.swift`:

```swift
import AppKit

/// 오른쪽 Option 단독. 단독 수식키라 다른 앱의 단축키와 충돌하지 않고
/// flagsChanged로 눌림과 뗌을 모두 받을 수 있다.
/// Fn은 시스템이 받아쓰기와 이모지 입력에 이미 쓰고 있어 피한다.
@MainActor
final class HotkeyMonitor {
    private static let rightOptionKeyCode: UInt16 = 61

    private let onEvent: @MainActor (TriggerEvent) -> Void
    private var monitor: Any?
    private var isDown = false

    init(onEvent: @escaping @MainActor (TriggerEvent) -> Void) {
        self.onEvent = onEvent
    }

    func start() {
        guard monitor == nil else { return }
        // 전역 모니터를 앱 런치가 끝나기 전에 설치하면 MenuBarExtra 상태 아이템이
        // 실제 마우스 클릭을 받지 못한다. 접근성 경로로는 열리므로 증상이 앱 정상처럼
        // 보이지만 사용자는 아이콘을 눌러도 아무 반응을 얻지 못한다.
        DispatchQueue.main.async {
            self.installMonitor()
        }
    }

    private func installMonitor() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, event.keyCode == Self.rightOptionKeyCode else { return }
            let down = event.modifierFlags.contains(.option)
            // flagsChanged는 같은 상태를 연달아 보낼 수 있다.
            guard down != self.isDown else { return }
            self.isDown = down
            MainActor.assumeIsolated {
                self.onEvent(down ? .keyDown : .keyUp)
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isDown = false
    }
}
```

`addLocalMonitorForEvents`로 바꾸지 않는다. 로컬 모니터는 이 앱에 전달된 이벤트만
보는데, 다른 앱이 전면일 때 수식키를 관찰하는 것이 이 클래스의 존재 이유다.

- [ ] **Step 2: 빌드 확인**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: 마우스 클릭이 살아 있는지 확인**

전역 모니터 설치 시점이 잘못되면 메뉴바 아이콘이 마우스 클릭을 받지 못한다.
접근성 경로로는 열리므로 이 확인은 실제 포인터 이벤트로 해야 한다.

`osascript`의 `click at`은 접근성 액션으로 처리되어 두 경로를 구분하지 못한다.
`/tmp`에 `CGEvent` 마우스 다운/업을 아이콘 좌표에 게시하는 작은 프로그램을 만들어
확인한다. 좌표는 다음으로 얻는다.

```bash
osascript -e 'tell application "System Events" to tell process "TypelessLike" to get {position, size} of menu bar item 1 of menu bar 2'
```

Expected: 실제 클릭으로 메뉴가 열린다.

- [ ] **Step 4: 커밋**

```bash
git add Sources/TypelessLike/Input/HotkeyMonitor.swift
git commit -m "feat: 오른쪽 Option 전역 핫키 감시 추가"
```

---

### Task 13: Coordinator 배선과 마무리

**Files:**
- Create: `Sources/TypelessLike/Core/Coordinator.swift`
- Create: `Sources/TypelessLike/App/PermissionStatus.swift`
- Modify: `Sources/TypelessLike/App/MenuBarApp.swift` (임시 메뉴 항목 제거, 실제 배선)
- Delete: `Spikes/InsertionSpike.swift`, `Spikes/HotkeySpike.swift`

**Interfaces:**
- Consumes: 앞선 모든 태스크의 산출물
- Produces: 동작하는 앱

- [ ] **Step 1: Coordinator 작성**

`Sources/TypelessLike/Core/Coordinator.swift`:

```swift
import AVFAudio
import Foundation
import Observation

/// 상태 기계와 실제 컴포넌트를 잇는 유일한 지점.
/// 하위 모듈들은 서로를 모른다.
@MainActor
@Observable
final class Coordinator {
    private(set) var state: DictationState = .idle
    private(set) var level: Float = 0

    private let overlay = OverlayController()
    private let refiner: (any TextRefiner)?
    private var hotkey: HotkeyMonitor?
    private var capture: AudioCapture?
    private var transcriber: Transcriber?

    init(refiner: (any TextRefiner)?) {
        self.refiner = refiner
    }

    func start() {
        let monitor = HotkeyMonitor { [weak self] event in
            self?.handle(event)
        }
        monitor.start()
        hotkey = monitor
    }

    private func handle(_ event: TriggerEvent) {
        let (next, effect) = reduce(state, event, now: .now, threshold: DictationTuning.holdThreshold)
        state = next
        switch effect {
        case .startCapture:
            overlay.show(status: .recording)
            Task { await beginCapture() }
        case .stopCaptureAndProcess:
            overlay.show(status: .refining)
            Task { await finishAndInsert() }
        case .none:
            break
        }
    }

    private func beginCapture() async {
        do {
            let format = try await Transcriber.targetAudioFormat()
            let newTranscriber = Transcriber()
            let newCapture = AudioCapture(targetFormat: format) { [weak self] value in
                Task { @MainActor in
                    self?.level = value
                    self?.overlay.update(level: value)
                }
            }
            let stream = try await newCapture.start()
            try await newTranscriber.begin(inputSequence: stream)
            capture = newCapture
            transcriber = newTranscriber
        } catch {
            NSLog("[Coordinator] 녹음 시작 실패: %@", String(describing: error))
            reset()
        }
    }

    private func finishAndInsert() async {
        guard let capture, let transcriber else { reset(); return }
        let recorded = await capture.recordedDuration
        await capture.stop()

        let raw = (try? await transcriber.finish()) ?? ""
        // 빈 문자열이면 아무 동작도 하지 않는다. 빈 붙여넣기를 막는다.
        guard !raw.isEmpty else { reset(); return }

        let text = await refineOrFallback(raw, using: refiner, timeout: refineTimeout(for: recorded))
        await TextInserter.insert(text)
        reset()
    }

    private func reset() {
        capture = nil
        transcriber = nil
        level = 0
        overlay.hide()
        state = .idle
    }
}
```

- [ ] **Step 2: 권한 상태 점검기 작성**

`Sources/TypelessLike/App/PermissionStatus.swift`. spec 10절이 요구하는 두 권한 안내다.
권한이 없으면 앱이 조용히 아무것도 못 하는 상태가 되므로 메뉴에서 바로 보이게 한다.

```swift
import AVFoundation
import AppKit

enum PermissionStatus {
    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var accessibilityGranted: Bool {
        TextInserter.hasAccessibilityPermission
    }

    static func requestMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// 한 번 거부한 뒤에는 시스템 다이얼로그가 다시 뜨지 않으므로 설정 창을 연다.
    static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 3: MenuBarApp을 실제 배선으로 교체**

`Sources/TypelessLike/App/MenuBarApp.swift`. 임시 스파이크 메뉴 항목을 모두 지운다.

```swift
import SwiftUI
import AppKit

@main
struct MenuBarApp: App {
    @State private var coordinator = Coordinator(
        refiner: OpenAICompatibleRefiner(
            baseURL: URL(string: "http://127.0.0.1:8081/v1")!,
            model: "gemma-4-e2b-it-8bit",
            apiKey: ProcessInfo.processInfo.environment["TYPELESS_API_KEY"]
        )
    )

    var body: some Scene {
        MenuBarExtra {
            if !PermissionStatus.microphoneGranted {
                Button("마이크 권한 허용하기…") {
                    Task {
                        await PermissionStatus.requestMicrophone()
                        if !PermissionStatus.microphoneGranted {
                            PermissionStatus.openMicrophoneSettings()
                        }
                    }
                }
            }
            if !PermissionStatus.accessibilityGranted {
                Button("손쉬운 사용 권한 허용하기…") {
                    TextInserter.requestAccessibilityPermission()
                    PermissionStatus.openAccessibilitySettings()
                }
            }
            if !PermissionStatus.microphoneGranted || !PermissionStatus.accessibilityGranted {
                Divider()
            }
            Text(statusLabel)
            Divider()
            Button("종료") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: iconName)
        }
        .onChange(of: coordinator.state) { _, _ in }
        .commands { }
    }

    private var iconName: String {
        switch coordinator.state {
        case .idle: "mic"
        case .holding, .toggled: "mic.fill"
        case .processing: "waveform"
        }
    }

    private var statusLabel: String {
        switch coordinator.state {
        case .idle: "대기 중 — 오른쪽 Option을 누르세요"
        case .holding, .toggled: "녹음 중"
        case .processing: "다듬는 중"
        }
    }

    init() {
        let coordinator = coordinator
        Task { @MainActor in coordinator.start() }
    }
}
```

- [ ] **Step 4: 스파이크 삭제**

```bash
rm -rf Spikes
```

Task 2와 3의 산출물은 버리는 코드다. 확인 결과는 이미 spec에 기록돼 있다.

- [ ] **Step 5: 전체 테스트와 빌드**

Run: `swift test && ./Scripts/bundle.sh`
Expected: 테스트 22개 전부 통과, `.app` 조립 완료.

- [ ] **Step 6: 실제 앱으로 육성 확인**

Run: `open build/TypelessLike.app`

oMLX가 떠 있는 상태에서 TextEdit을 열고 커서를 둔다. 오른쪽 ⌥를 누른 채 말하고 뗀다.

확인할 것.
- 오버레이가 뜨고 목소리에 따라 레벨 막대가 움직인다
- 손을 떼면 "다듬는 중"으로 바뀐다
- 다듬어진 문장이 TextEdit 커서 위치에 들어간다
- 클립보드가 원래 내용으로 돌아와 있다
- 짧게 톡 누르면 녹음이 계속되고, 다시 누르면 종료된다

한영을 섞어 말해 용어가 영문으로 복원되는지 본다. 예: "이 PR은 approve하고 main 브랜치에 merge할게요."

정정도 확인한다. 예: "목요일에 배포하려고 했는데 아니 금요일로 바꿨어요."

- [ ] **Step 7: 서버를 끄고 폴백 확인**

oMLX를 종료한 뒤 같은 동작을 한다.
Expected: 다듬기 없이 원본 전사가 그대로 삽입된다. 앱이 멈추거나 아무것도 삽입하지 않는 일은 없어야 한다.

- [ ] **Step 8: 커밋**

```bash
git add -A
git commit -m "feat: Coordinator 배선으로 핵심 루프 완성

핫키로 녹음을 시작해 전사하고 다듬어 커서 위치에 삽입하기까지
이어 붙였다. 다듬기 서버가 없으면 원본 전사를 삽입한다.

스파이크 산출물은 결론을 spec에 남기고 삭제했다."
```

---

## 완료 기준

spec 1절의 완성 기준이다.

> 핫키를 누른다 → 말하는 동안 화면에 상태와 목소리 레벨이 보인다 → 필러와 말 더듬음이 제거되고 스스로 고친 말은 최종 의도만 남은 텍스트가, 지금 포커스된 앱의 커서 위치에 들어간다.

Task 13 Step 5가 이것을 확인한다. 여기까지가 MVP다. spec 2절의 비목표(설정 창, 히스토리, 실시간 전사 오버레이, 문체 적응, 배포 패키징)는 손대지 않는다.
