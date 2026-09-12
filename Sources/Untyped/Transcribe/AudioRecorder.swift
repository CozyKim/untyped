import AVFAudio
import Foundation
import Speech

/// 마이크 버퍼를 모아 WAV 파일 바이트로 만든다. 오디오를 LLM에 통째로 보내 한 요청으로 다듬는
/// 경로가 SpeechAnalyzer 대신 쓴다. HTTP도 프롬프트도 모른다 — AudioCapture가 흘려주는 버퍼를
/// 받아 바이트로 쌓기만 한다.
actor AudioRecorder {
    /// 16 kHz mono 16-bit PCM. 음성 모델의 오디오 인코더가 받는 표준 입력이라 서버 쪽
    /// 리샘플링이 없고, Float32의 절반 크기라 base64로 실어 보내기에도 가볍다.
    static let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true
    )!

    private var pcm = Data()
    private var consumer: Task<Void, Never>?

    /// 스트림이 닫힐 때까지 버퍼를 쌓는다. 포맷은 `format`이어야 한다 — 그 외의 포맷은
    /// 조용히 버려서 헤더와 맞지 않는 바이트가 파일에 섞이지 않게 한다.
    func begin(inputSequence: AsyncStream<AnalyzerInput>) {
        pcm = Data()
        consumer = Task { [weak self] in
            for await input in inputSequence {
                await self?.append(input.buffer)
            }
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard buffer.format.commonFormat == .pcmFormatInt16,
              buffer.format.channelCount == 1,
              let samples = buffer.int16ChannelData?[0]
        else { return }
        pcm.append(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
    }

    /// 입력 스트림이 닫힌 뒤 호출한다. 버퍼가 하나도 없었으면 빈 Data — 헤더만 있는 파일을
    /// 보내지 않도록 호출자가 그 경우를 가려낸다.
    func finish() async -> Data {
        await consumer?.value
        consumer = nil
        defer { pcm = Data() }
        guard !pcm.isEmpty else { return Data() }
        return WAVFile.data(pcm16: pcm, sampleRate: Int(Self.format.sampleRate))
    }
}

/// 표준 44바이트 RIFF/WAVE 헤더 + PCM. mono 16-bit만 다룬다.
enum WAVFile {
    static func data(pcm16: Data, sampleRate: Int) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)

        var out = Data(capacity: 44 + pcm16.count)
        out.append(contentsOf: Array("RIFF".utf8))
        out.appendLittleEndian(UInt32(36 + pcm16.count))
        out.append(contentsOf: Array("WAVE".utf8))
        out.append(contentsOf: Array("fmt ".utf8))
        out.appendLittleEndian(UInt32(16))          // fmt 청크 길이
        out.appendLittleEndian(UInt16(1))           // PCM
        out.appendLittleEndian(channels)
        out.appendLittleEndian(UInt32(sampleRate))
        out.appendLittleEndian(byteRate)
        out.appendLittleEndian(blockAlign)
        out.appendLittleEndian(bitsPerSample)
        out.append(contentsOf: Array("data".utf8))
        out.appendLittleEndian(UInt32(pcm16.count))
        out.append(pcm16)
        return out
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
