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
