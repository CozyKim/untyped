import Testing
import Foundation
@testable import Untyped

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

private struct SlowButReturningRefiner: TextRefiner {
    var isAvailable: Bool { get async { true } }
    func refine(_ raw: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(100))
        return "다듬음: " + raw
    }
}

private struct TruncatedRefiner: TextRefiner {
    var isAvailable: Bool { get async { true } }
    func refine(_ raw: String) async throws -> String { throw RefinerError.truncated }
}

private struct EmptyResultRefiner: TextRefiner {
    var isAvailable: Bool { get async { true } }
    func refine(_ raw: String) async throws -> String { "" }
}

private struct WhitespaceOnlyRefiner: TextRefiner {
    var isAvailable: Bool { get async { true } }
    func refine(_ raw: String) async throws -> String { "   \n  " }
}

@Test func throwingRefinerFallsBackToRawText() async {
    let out = await refineOrFallback("원본 전사", using: ThrowingRefiner(), timeout: .seconds(5))
    #expect(out == .fallback("원본 전사", .failed(detail: "연결 거부 — 로컬 LLM 서버가 실행 중이 아님")))
}

@Test func timeoutFallsBackToRawText() async {
    let out = await refineOrFallback("원본 전사", using: SlowRefiner(), timeout: .milliseconds(200))
    #expect(out == .fallback("원본 전사", .timeout))
}

@Test func missingRefinerFallsBackToRawText() async {
    let out = await refineOrFallback("원본 전사", using: nil, timeout: .seconds(5))
    #expect(out == .fallback("원본 전사", .noRefiner))
}

@Test func workingRefinerResultIsUsed() async {
    let out = await refineOrFallback("원본 전사", using: EchoRefiner(), timeout: .seconds(5))
    #expect(out == .refined("다듬음: 원본 전사"))
}

@Test func realisticRefinerWithComfortableTimeoutSucceeds() async {
    let out = await refineOrFallback("원본 전사", using: SlowButReturningRefiner(), timeout: .seconds(5))
    #expect(out == .refined("다듬음: 원본 전사"))
}

@Test func cancelAllExitsFastAfterRefinerCompletes() async {
    let clock = ContinuousClock()
    let elapsed = await clock.measure {
        _ = await refineOrFallback("원본 전사", using: SlowButReturningRefiner(), timeout: .seconds(5))
    }
    // 100ms 다듬기 + 측정 오버헤드. 5초 타임아웃이 드레인되지 않으므로 1초 이내
    #expect(elapsed < .seconds(1))
}

@Test func cancelAllExitsFastAfterTimeout() async {
    let clock = ContinuousClock()
    let elapsed = await clock.measure {
        _ = await refineOrFallback("원본 전사", using: SlowRefiner(), timeout: .milliseconds(200))
    }
    // 200ms 타임아웃 + 측정 오버헤드. 10초 다듬기가 드레인되지 않으므로 2초 이내
    #expect(elapsed < .seconds(2))
}

@Test func emptyResultFallsBackToRawText() async {
    let out = await refineOrFallback("원본 전사", using: EmptyResultRefiner(), timeout: .seconds(5))
    #expect(out == .fallback("원본 전사", .emptyResult))
}

@Test func whitespaceOnlyResultFallsBackToRawText() async {
    let out = await refineOrFallback("원본 전사", using: WhitespaceOnlyRefiner(), timeout: .seconds(5))
    #expect(out == .fallback("원본 전사", .emptyResult))
}

@Test func timeoutGrowsWithRecordingLength() {
    // 기본 + 길이 * 0.4
    #expect(refineTimeout(for: .seconds(5), base: .seconds(4)) == .seconds(6))
    #expect(refineTimeout(for: .seconds(30), base: .seconds(4)) == .seconds(16))
}

@Test func timeoutBaseIsConfigurable() {
    // 모델이 스왑에서 돌아오는 고정 비용은 녹음 길이와 무관하므로 기본값을 따로 올릴 수 있어야 한다.
    #expect(refineTimeout(for: .seconds(5), base: .seconds(10)) == .seconds(12))
}

@Test func truncatedResultFallsBackWithItsOwnReason() async {
    // 최대 토큰을 넘어 잘린 경우는 사용자가 설정을 올려 고칠 수 있으므로 이유를 구분한다.
    let out = await refineOrFallback("원본 전사", using: TruncatedRefiner(), timeout: .seconds(5))
    #expect(out == .fallback("원본 전사", .truncated))
}

@Test func outcomeTextIsWhatGetsInserted() {
    #expect(RefineOutcome.refined("다듬음").text == "다듬음")
    #expect(RefineOutcome.fallback("원본", .timeout).text == "원본")
}

@Test func failureDetailNamesTheActualCause() {
    // 로그에서 "서버 오류"만 보고는 서버가 꺼진 건지 응답이 이상한 건지 알 수 없다.
    #expect(failureDetail(of: URLError(.cannotConnectToHost)) == "연결 거부 — 로컬 LLM 서버가 실행 중이 아님")
    #expect(failureDetail(of: URLError(.timedOut)) == "요청 시간 초과 (URLSession)")
    #expect(failureDetail(of: RefinerError.badStatus(500)) == "HTTP 500")
    #expect(failureDetail(of: RefinerError.emptyResponse) == "응답에 choices가 없음")
    #expect(failureDetail(of: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x"))) == "응답 형식 오류 — JSON 해석 실패")
}

@Test func failedReasonLabelIgnoresDetail() {
    #expect(FallbackReason.failed(detail: "HTTP 500").label == "다듬기 서버 오류")
}
