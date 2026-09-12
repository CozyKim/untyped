import Testing
import Foundation
@testable import Untyped

// MARK: - 간격 매핑

@Test func intervalChoicesMapToWholeMinutes() {
    for interval in KeepAliveInterval.allCases {
        #expect(interval.duration == .seconds(interval.rawValue * 60))
        // 선택지는 1분 아래로 내려가지 않는다 — 초 단위 난타를 막는다.
        #expect(interval.duration >= .seconds(60))
    }
    #expect(KeepAliveInterval.fiveMinutes.duration == .seconds(300))
    #expect(KeepAliveInterval(rawValue: 7) == nil)
}

// MARK: - 로그 한 줄

@Test func logLineIsConciseAndCarriesTiming() {
    // 받아쓰기 로그 파일이 아니라 NSLog로 가는 한 줄. 요청·응답 본문이나 키는 들어가지 않는다.
    #expect(KeepAlive.logLine(took: .milliseconds(830), failure: nil) == "완료 0.8초")
    #expect(KeepAlive.logLine(took: .milliseconds(12), failure: "연결 거부 — 로컬 LLM 서버가 실행 중이 아님")
        == "실패 0.0초: 연결 거부 — 로컬 LLM 서버가 실행 중이 아님 — 다음 주기에 다시 시도")
}

// MARK: - 스케줄러

/// 실제 서버 대신 부르는 쪽. 호출 횟수와 실패·지연을 테스트가 조절한다.
@MainActor
private final class Probe {
    var calls = 0
    var busy = false
    var error: (any Error)?
    var delay: Duration = .zero

    func touch() async throws {
        calls += 1
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
    }
}

private let tick: Duration = .milliseconds(40)

@MainActor @Test func nilPeriodSendsNothing() async throws {
    // 설정이 꺼져 있으면 요청이 한 번도 나가지 않는다.
    let probe = Probe()
    let keepAlive = KeepAlive()
    keepAlive.start(every: nil, isBusy: { probe.busy }, touch: { try await probe.touch() })
    try await Task.sleep(for: tick * 3)
    #expect(probe.calls == 0)
    #expect(keepAlive.lastFailure == nil)
}

@MainActor @Test func sendsImmediatelyThenEveryInterval() async throws {
    let probe = Probe()
    let keepAlive = KeepAlive()
    defer { keepAlive.stop() }
    keepAlive.start(every: tick, isBusy: { probe.busy }, touch: { try await probe.touch() })
    // 첫 요청은 간격을 기다리지 않는다 — 앱 시작·설정 저장 시점에 모델을 바로 올려 둔다.
    try await Task.sleep(for: .milliseconds(10))
    #expect(probe.calls == 1)
    try await Task.sleep(for: tick * 3)
    #expect(probe.calls >= 3)
    #expect(keepAlive.lastFailure == nil)
}

@MainActor @Test func skipsTicksWhileBusyAndResumesAfter() async throws {
    // 받아쓰기가 진행 중이면 그 주기는 건너뛴다 — 다듬기 요청이 어차피 모델을 건드린다.
    let probe = Probe()
    probe.busy = true
    let keepAlive = KeepAlive()
    defer { keepAlive.stop() }
    keepAlive.start(every: tick, isBusy: { probe.busy }, touch: { try await probe.touch() })
    try await Task.sleep(for: tick * 3)
    #expect(probe.calls == 0)
    probe.busy = false
    try await Task.sleep(for: tick * 3)
    #expect(probe.calls >= 1)
}

@MainActor @Test func recordsAConciseFailureAndRetriesNextInterval() async throws {
    let probe = Probe()
    probe.error = URLError(.cannotConnectToHost)
    let keepAlive = KeepAlive()
    defer { keepAlive.stop() }
    keepAlive.start(every: tick, isBusy: { probe.busy }, touch: { try await probe.touch() })
    try await Task.sleep(for: tick * 3)
    // 실패해도 루프는 멈추지 않고 다음 주기에 다시 보낸다. 백오프 없음.
    #expect(probe.calls >= 2)
    #expect(keepAlive.lastFailure == "연결 거부 — 로컬 LLM 서버가 실행 중이 아님")

    probe.error = RefinerError.badStatus(404)
    try await Task.sleep(for: tick * 3)
    #expect(keepAlive.lastFailure == "HTTP 404")

    // 서버가 돌아오면 기록이 지워진다.
    probe.error = nil
    try await Task.sleep(for: tick * 3)
    #expect(keepAlive.lastFailure == nil)
}

@MainActor @Test func doesNotOverlapWhileATouchIsInFlight() async throws {
    // 요청 하나가 간격보다 오래 걸려도(모델 로드 중) 다음 요청은 그것이 끝난 뒤에 나간다.
    let probe = Probe()
    probe.delay = tick * 4
    let keepAlive = KeepAlive()
    defer { keepAlive.stop() }
    keepAlive.start(every: tick, isBusy: { probe.busy }, touch: { try await probe.touch() })
    try await Task.sleep(for: tick * 3)
    #expect(probe.calls == 1)
}

@MainActor @Test func stopEndsTheLoop() async throws {
    let probe = Probe()
    let keepAlive = KeepAlive()
    keepAlive.start(every: tick, isBusy: { probe.busy }, touch: { try await probe.touch() })
    try await Task.sleep(for: tick * 2)
    keepAlive.stop()
    let callsAtStop = probe.calls
    try await Task.sleep(for: tick * 3)
    #expect(probe.calls == callsAtStop)
}

@MainActor @Test func restartCancelsThePreviousLoopWithoutRecordingAFailure() async throws {
    // 설정을 저장하면 새 서버·간격으로 다시 시작한다. 이전 루프의 진행 중 요청은 취소되고,
    // 그 취소는 실패로 기록되지 않는다.
    let slow = Probe()
    slow.delay = tick * 5
    let fast = Probe()
    let keepAlive = KeepAlive()
    defer { keepAlive.stop() }
    keepAlive.start(every: tick, isBusy: { slow.busy }, touch: { try await slow.touch() })
    try await Task.sleep(for: .milliseconds(10))
    #expect(slow.calls == 1)
    keepAlive.start(every: tick, isBusy: { fast.busy }, touch: { try await fast.touch() })
    try await Task.sleep(for: tick * 7)
    #expect(slow.calls == 1)
    #expect(fast.calls >= 2)
    #expect(keepAlive.lastFailure == nil)
}
