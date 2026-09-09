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
