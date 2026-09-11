import Testing
import Foundation
@testable import Untyped

private let url = URL(string: "http://127.0.0.1:8081/v1")!

@Test func timeoutWithUnreachableServerBlamesTheServer() {
    let cause = fallbackCause(
        reason: .timeout, timeout: .seconds(5), serverReachable: false,
        warmUp: .finished(in: .milliseconds(300)), baseURL: url
    )
    #expect(cause == "로컬 LLM 서버에 연결할 수 없음 (http://127.0.0.1:8081/v1) — 꺼져 있거나 주소가 잘못됨. 대기 상한 5.0초")
}

@Test func timeoutWithWarmUpRunningIsColdStartEvenIfProbeFails() {
    // 모델을 올리는 중인 서버는 연결 확인에도 답을 못 한다. 예열이 대기 중이라는 사실이
    // 서버가 살아 있다는 더 강한 증거다.
    let cause = fallbackCause(
        reason: .timeout, timeout: .seconds(5), serverReachable: false,
        warmUp: .running(for: .seconds(6)), baseURL: url
    )
    #expect(cause == "콜드 스타트 — 예열 요청이 6.0초째 응답 없음(모델 로드 중) · 연결 확인도 응답 없음. 대기 상한 5.0초")
}

@Test func timeoutWhileWarmUpStillRunningIsColdStart() {
    let cause = fallbackCause(
        reason: .timeout, timeout: .milliseconds(6_800), serverReachable: true,
        warmUp: .running(for: .milliseconds(9_300)), baseURL: url
    )
    #expect(cause == "콜드 스타트 — 예열 요청이 9.3초째 응답 없음(모델 로드 중). 대기 상한 6.8초")
}

@Test func timeoutAfterWarmUpFinishedIsNotColdStart() {
    let cause = fallbackCause(
        reason: .timeout, timeout: .seconds(5), serverReachable: true,
        warmUp: .finished(in: .milliseconds(400)), baseURL: url
    )
    #expect(cause == "예열은 0.4초에 끝났으나 다듬기 응답이 5.0초 안에 없음 — 로컬 LLM 과부하 또는 긴 입력")
}

@Test func timeoutWithoutWarmUpReportsOnlyTheLimit() {
    let cause = fallbackCause(
        reason: .timeout, timeout: .seconds(5), serverReachable: true,
        warmUp: .notStarted, baseURL: url
    )
    #expect(cause == "다듬기 응답이 5.0초 안에 없음")
}

@Test func failedReasonUsesItsDetailAndAddsAddressWhenUnreachable() {
    let reachable = fallbackCause(
        reason: .failed(detail: "HTTP 500"), timeout: .seconds(5), serverReachable: true,
        warmUp: .finished(in: .seconds(1)), baseURL: url
    )
    #expect(reachable == "HTTP 500")
    let unreachable = fallbackCause(
        reason: .failed(detail: "연결 거부 — 로컬 LLM 서버가 실행 중이 아님"), timeout: .seconds(5),
        serverReachable: false, warmUp: .finished(in: .seconds(1)), baseURL: url
    )
    #expect(unreachable == "연결 거부 — 로컬 LLM 서버가 실행 중이 아님 (http://127.0.0.1:8081/v1)")
}

@Test(arguments: [FallbackReason.noRefiner, .truncated, .emptyResult])
func reasonsThatAreSelfExplanatoryHaveNoCause(reason: FallbackReason) {
    let cause = fallbackCause(
        reason: reason, timeout: .seconds(5), serverReachable: true,
        warmUp: .finished(in: .seconds(1)), baseURL: url
    )
    #expect(cause == nil)
}
