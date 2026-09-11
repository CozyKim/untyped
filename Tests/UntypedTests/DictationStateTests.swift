import Testing
import Foundation
@testable import Untyped

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

@Test func zeroThresholdNeverToggles() {
    // 토글 녹음을 끈 설정은 threshold 0으로 표현된다. 249ms 탭도 즉시 처리로 넘어간다.
    let now = t0.advanced(by: .milliseconds(249))
    let (s, e) = reduce(.holding(since: t0), .keyUp, now: now, threshold: .zero)
    #expect(s == .processing)
    #expect(e == .stopCaptureAndProcess)
}
