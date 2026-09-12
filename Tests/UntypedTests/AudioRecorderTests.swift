import Testing
import Foundation
import AVFAudio
import Speech
@testable import Untyped

private func int16Buffer(_ samples: [Int16]) -> AnalyzerInput {
    let buffer = AVAudioPCMBuffer(
        pcmFormat: AudioRecorder.format, frameCapacity: AVAudioFrameCount(samples.count)
    )!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    for (index, sample) in samples.enumerated() {
        buffer.int16ChannelData![0][index] = sample
    }
    return AnalyzerInput(buffer: buffer)
}

private func readLE32(_ data: Data, at offset: Int) -> UInt32 {
    data[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) }
}

private func readLE16(_ data: Data, at offset: Int) -> UInt16 {
    data[offset..<offset + 2].reversed().reduce(0) { $0 << 8 | UInt16($1) }
}

@Test func wavHeaderDescribesMono16BitPCM() {
    // 서버(miniaudio)는 RIFF/WAVE 매직으로 형식을 판별하고 fmt 청크로 샘플 레이트를 읽는다.
    let pcm = Data([0x01, 0x00, 0xFF, 0x7F, 0x00, 0x80])  // 3 샘플
    let wav = WAVFile.data(pcm16: pcm, sampleRate: 16_000)

    #expect(wav.count == 44 + 6)
    #expect(String(decoding: wav[0..<4], as: UTF8.self) == "RIFF")
    #expect(readLE32(wav, at: 4) == 36 + 6)
    #expect(String(decoding: wav[8..<12], as: UTF8.self) == "WAVE")
    #expect(String(decoding: wav[12..<16], as: UTF8.self) == "fmt ")
    #expect(readLE32(wav, at: 16) == 16)
    #expect(readLE16(wav, at: 20) == 1)          // PCM
    #expect(readLE16(wav, at: 22) == 1)          // mono
    #expect(readLE32(wav, at: 24) == 16_000)
    #expect(readLE32(wav, at: 28) == 32_000)     // byte rate
    #expect(readLE16(wav, at: 32) == 2)          // block align
    #expect(readLE16(wav, at: 34) == 16)         // bits per sample
    #expect(String(decoding: wav[36..<40], as: UTF8.self) == "data")
    #expect(readLE32(wav, at: 40) == 6)
    #expect(wav[44...] == pcm)
}

@Test func recorderConcatenatesBuffersIntoOneWav() async {
    let recorder = AudioRecorder()
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    await recorder.begin(inputSequence: stream)
    continuation.yield(int16Buffer([1, 2]))
    continuation.yield(int16Buffer([3]))
    continuation.finish()

    let wav = await recorder.finish()

    #expect(wav.count == 44 + 6)
    #expect(readLE32(wav, at: 40) == 6)
    // 리틀 엔디언 Int16이 순서대로 들어간다.
    #expect(wav[44...] == Data([1, 0, 2, 0, 3, 0]))
}

@Test func recorderReturnsEmptyDataWhenNoBuffersArrived() async {
    // 토글 녹음을 끄고 아주 짧게 눌렀다 떼면 버퍼가 하나도 오지 않는다. 헤더만 있는 파일을
    // 서버에 보내지 않도록 빈 Data로 구분한다.
    let recorder = AudioRecorder()
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    await recorder.begin(inputSequence: stream)
    continuation.finish()

    #expect(await recorder.finish().isEmpty)
}

@Test func recorderIgnoresBuffersInAnotherFormat() async {
    // 헤더는 16 kHz mono Int16을 약속한다. 다른 포맷의 바이트가 섞이면 서버가 잡음을 듣는다.
    let recorder = AudioRecorder()
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    await recorder.begin(inputSequence: stream)
    let float = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: float, frameCapacity: 4)!
    buffer.frameLength = 4
    continuation.yield(AnalyzerInput(buffer: buffer))
    continuation.yield(int16Buffer([7]))
    continuation.finish()

    let wav = await recorder.finish()

    #expect(wav[44...] == Data([7, 0]))
}

@Test func recorderCanBeReusedAfterFinish() async {
    let recorder = AudioRecorder()
    let (first, firstContinuation) = AsyncStream<AnalyzerInput>.makeStream()
    await recorder.begin(inputSequence: first)
    firstContinuation.yield(int16Buffer([1]))
    firstContinuation.finish()
    _ = await recorder.finish()

    let (second, secondContinuation) = AsyncStream<AnalyzerInput>.makeStream()
    await recorder.begin(inputSequence: second)
    secondContinuation.yield(int16Buffer([9]))
    secondContinuation.finish()

    let wav = await recorder.finish()

    // 이전 녹음의 샘플이 남아 있지 않다.
    #expect(wav[44...] == Data([9, 0]))
}
