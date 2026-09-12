import Testing
import Foundation
import Speech
@testable import Untyped

private actor Outcome {
    var value: String?
    func set(_ v: String) { value = v }
}

/// finish()가 제한 시간 안에 돌아오면 그 결과, 아니면 nil. 돌아오지 않는 Task는
/// 기다리지 않고 버린다 — TaskGroup으로 감싸면 그룹이 자식 완료를 기다려 러너까지 멈춘다.
private func finishOrTimeout(_ transcriber: Transcriber, seconds: Double) async -> String? {
    let outcome = Outcome()
    let task = Task { if let r = try? await transcriber.finish() { await outcome.set(r) } }
    let deadline = ContinuousClock.now + .seconds(seconds)
    while ContinuousClock.now < deadline {
        if let v = await outcome.value { return v }
        try? await Task.sleep(for: .milliseconds(50))
    }
    task.cancel()
    return await outcome.value
}

private func silence(seconds: Double) async throws -> AnalyzerInput {
    let format = try await Transcriber.targetAudioFormat()
    let frames = AVAudioFrameCount(format.sampleRate * seconds)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    return AnalyzerInput(buffer: buffer)
}

// 토글 녹음을 끄면 키를 아주 짧게 눌렀다 뗄 때 마이크가 첫 버퍼를 만들기도 전에
// 스트림이 닫힌다. SpeechTranscriber.results는 분석기가 입력을 하나도 못 받으면
// 종료되지 않으므로, finish()가 그 결과를 기다리면 앱이 "다듬는 중"에 영영 갇힌다.
@Test func finishReturnsEmptyWhenInputStreamHadNoBuffers() async throws {
    let transcriber = Transcriber()
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    try await transcriber.begin(inputSequence: stream)
    continuation.finish()

    let result = await finishOrTimeout(transcriber, seconds: 8)

    #expect(result == "")
}

@Test func finishReturnsWhenInputStreamHadOneTinyBuffer() async throws {
    let transcriber = Transcriber()
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    try await transcriber.begin(inputSequence: stream)
    continuation.yield(try await silence(seconds: 0.02))
    continuation.finish()

    let result = await finishOrTimeout(transcriber, seconds: 8)

    #expect(result == "")
}

// 빈 세션을 정리한 뒤에도 같은 인스턴스로 다음 받아쓰기가 되어야 한다.
@Test func sessionAfterEmptyOneStillFinishes() async throws {
    let transcriber = Transcriber()
    let (empty, emptyContinuation) = AsyncStream<AnalyzerInput>.makeStream()
    try await transcriber.begin(inputSequence: empty)
    emptyContinuation.finish()
    _ = await finishOrTimeout(transcriber, seconds: 8)

    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    try await transcriber.begin(inputSequence: stream)
    continuation.yield(try await silence(seconds: 0.5))
    continuation.finish()

    let result = await finishOrTimeout(transcriber, seconds: 8)

    #expect(result == "")
}

private actor PreviewLog {
    var texts: [String] = []
    func append(_ text: String) { texts.append(text) }
}

// 미리보기 분석기를 함께 돌려도 확정 경로는 그대로다 — 무음이면 빈 문자열, 멈추지 않음.
// 무음에서는 미리보기 콜백도 비지 않은 텍스트를 보내지 않는다.
@Test func silenceYieldsNoPreviewTextAndEmptyFinal() async throws {
    let transcriber = Transcriber()
    let log = PreviewLog()
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    try await transcriber.begin(inputSequence: stream) { text in
        Task { await log.append(text) }
    }
    continuation.yield(try await silence(seconds: 1.0))
    continuation.finish()

    let result = await finishOrTimeout(transcriber, seconds: 8)

    #expect(result == "")
    let texts = await log.texts
    #expect(texts.allSatisfy { $0.isEmpty })
}
