import Testing
import Foundation
@testable import Untyped

private let t0 = ContinuousClock.now
private let th = Duration.milliseconds(250)

@Test func idleKeyDownStartsHolding() {
    let (s, e) = reduce(.idle, .keyDown, from: .frontmost, now: t0, threshold: th)
    #expect(s == .holding(since: t0, destination: .frontmost))
    #expect(e == .startCapture)
}

@Test func idleKeyUpIsIgnored() {
    let (s, e) = reduce(.idle, .keyUp, from: .frontmost, now: t0, threshold: th)
    #expect(s == .idle)
    #expect(e == .none)
}

@Test func shortPressEntersToggled() {
    let now = t0.advanced(by: .milliseconds(249))
    let (s, e) = reduce(
        .holding(since: t0, destination: .frontmost), .keyUp, from: .frontmost, now: now, threshold: th
    )
    #expect(s == .toggled(destination: .frontmost))
    #expect(e == .none)
}

@Test func longPressStopsImmediately() {
    let now = t0.advanced(by: .milliseconds(250))
    let (s, e) = reduce(
        .holding(since: t0, destination: .frontmost), .keyUp, from: .frontmost, now: now, threshold: th
    )
    #expect(s == .processing)
    #expect(e == .stopCaptureAndProcess(.frontmost))
}

@Test func holdingIgnoresRepeatedKeyDown() {
    let (s, e) = reduce(
        .holding(since: t0, destination: .frontmost), .keyDown, from: .frontmost,
        now: t0.advanced(by: .seconds(1)), threshold: th
    )
    #expect(s == .holding(since: t0, destination: .frontmost))
    #expect(e == .none)
}

@Test func toggledKeyDownStops() {
    let (s, e) = reduce(.toggled(destination: .frontmost), .keyDown, from: .frontmost, now: t0, threshold: th)
    #expect(s == .processing)
    #expect(e == .stopCaptureAndProcess(.frontmost))
}

@Test func toggledIgnoresKeyUp() {
    let (s, e) = reduce(.toggled(destination: .frontmost), .keyUp, from: .frontmost, now: t0, threshold: th)
    #expect(s == .toggled(destination: .frontmost))
    #expect(e == .none)
}

@Test(arguments: [TriggerEvent.keyDown, TriggerEvent.keyUp], [InsertDestination.frontmost, .targetApp])
func processingIgnoresEverything(event: TriggerEvent, destination: InsertDestination) {
    let (s, e) = reduce(.processing, event, from: destination, now: t0, threshold: th)
    #expect(s == .processing)
    #expect(e == .none)
}

@Test func zeroThresholdNeverToggles() {
    // 토글 녹음을 끈 설정은 threshold 0으로 표현된다. 249ms 탭도 즉시 처리로 넘어간다.
    let now = t0.advanced(by: .milliseconds(249))
    let (s, e) = reduce(
        .holding(since: t0, destination: .frontmost), .keyUp, from: .frontmost, now: now, threshold: .zero
    )
    #expect(s == .processing)
    #expect(e == .stopCaptureAndProcess(.frontmost))
}

// 앱으로 보내기 키. 녹음을 시작한 키만 그 녹음을 끝낸다.

@Test func targetAppKeyDownStartsHoldingForTargetApp() {
    let (s, e) = reduce(.idle, .keyDown, from: .targetApp, now: t0, threshold: th)
    #expect(s == .holding(since: t0, destination: .targetApp))
    #expect(e == .startCapture)
}

@Test func targetAppLongPressProcessesForTargetApp() {
    let now = t0.advanced(by: .milliseconds(300))
    let (s, e) = reduce(
        .holding(since: t0, destination: .targetApp), .keyUp, from: .targetApp, now: now, threshold: th
    )
    #expect(s == .processing)
    #expect(e == .stopCaptureAndProcess(.targetApp))
}

@Test func targetAppShortPressKeepsDestinationInToggled() {
    let now = t0.advanced(by: .milliseconds(100))
    let (s, e) = reduce(
        .holding(since: t0, destination: .targetApp), .keyUp, from: .targetApp, now: now, threshold: th
    )
    #expect(s == .toggled(destination: .targetApp))
    #expect(e == .none)
}

@Test func otherKeyReleaseDoesNotEndHold() {
    // 기본 키로 녹음 중에 앱으로 보내기 키를 눌렀다 떼도 녹음은 계속된다.
    let now = t0.advanced(by: .seconds(1))
    let (s, e) = reduce(
        .holding(since: t0, destination: .frontmost), .keyUp, from: .targetApp, now: now, threshold: th
    )
    #expect(s == .holding(since: t0, destination: .frontmost))
    #expect(e == .none)
}

@Test func otherKeyPressDoesNotStopToggled() {
    let (s, e) = reduce(.toggled(destination: .targetApp), .keyDown, from: .frontmost, now: t0, threshold: th)
    #expect(s == .toggled(destination: .targetApp))
    #expect(e == .none)
}

@Test func toggledStopsOnlyByStartingKey() {
    let (s, e) = reduce(.toggled(destination: .targetApp), .keyDown, from: .targetApp, now: t0, threshold: th)
    #expect(s == .processing)
    #expect(e == .stopCaptureAndProcess(.targetApp))
}

// 음소거는 마이크 준비(포맷 조회·마이크 시작·분석기 시작, 150ms 이상)가 끝난 뒤에 건다.
// 짧게 눌렀다 떼면 준비가 끝나기 전에 키가 올라와 있으므로, 그 시점의 상태가 "아직 듣는 중"
// 인지로 음소거를 걸지 말지 정한다.

@Test func shortPressInPushToTalkIsNotListeningWhenSetupFinishes() {
    // 토글이 꺼진 설정에서 80ms 눌렀다 뗐다. 준비가 끝났을 때 processing이므로 음소거하면
    // 안 된다 — 걸면 뗀 뒤에 소리가 끊겼다 돌아온다.
    let (down, _) = reduce(.idle, .keyDown, from: .frontmost, now: t0, threshold: .zero)
    let (up, effect) = reduce(
        down, .keyUp, from: .frontmost, now: t0.advanced(by: .milliseconds(80)), threshold: .zero
    )
    #expect(effect == .stopCaptureAndProcess(.frontmost))
    #expect(!up.isListening)
}

@Test func shortPressWithToggleKeepsListening() {
    // 토글 녹음은 뗀 뒤에도 녹음이 이어지므로 준비가 끝나면 음소거한다.
    let (down, _) = reduce(.idle, .keyDown, from: .frontmost, now: t0, threshold: th)
    let (up, _) = reduce(
        down, .keyUp, from: .frontmost, now: t0.advanced(by: .milliseconds(80)), threshold: th
    )
    #expect(up == .toggled(destination: .frontmost))
    #expect(up.isListening)
}

@Test func holdingIsListeningAndIdleIsNot() {
    #expect(DictationState.holding(since: t0, destination: .targetApp).isListening)
    #expect(!DictationState.idle.isListening)
}
