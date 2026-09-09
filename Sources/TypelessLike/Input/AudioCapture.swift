@preconcurrency import AVFAudio
import Foundation
import Speech

/// 마이크를 열어 전사기가 요구하는 포맷으로 변환한 버퍼를 흘린다.
/// 목표 포맷은 호출자가 정한다. 마이크 네이티브 포맷을 추측하지 않는다.
actor AudioCapture {
    private let engine = AVAudioEngine()
    private let targetFormat: AVAudioFormat
    private let onLevel: @Sendable (Float) -> Void
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var startedAt: ContinuousClock.Instant?
    private var stoppedAt: ContinuousClock.Instant?

    init(targetFormat: AVAudioFormat, onLevel: @escaping @Sendable (Float) -> Void) {
        self.targetFormat = targetFormat
        self.onLevel = onLevel
    }

    var recordedDuration: Duration {
        guard let startedAt else { return .zero }
        return (stoppedAt ?? ContinuousClock.now) - startedAt
    }

    func start() throws -> AsyncStream<AnalyzerInput> {
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        continuation = cont

        let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: source, to: targetFormat) else {
            throw AudioCaptureError.converterUnavailable
        }
        let ratio = targetFormat.sampleRate / source.sampleRate
        let level = onLevel
        let outputFormat = converter.outputFormat

        // 탭 콜백은 오디오 스레드에서만 실행되고 AVAudioEngine이 모든 접근을 직렬화한다.
        input.installTap(onBus: 0, bufferSize: 4096, format: source) { buffer, _ in
            if let channel = buffer.floatChannelData?[0] {
                let value = rms(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                level(value)
            }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
            // convert() 호출 내에서만 동기적으로 한 번 또는 두 번 호출되고 동일 스레드에서만 접근됨
            class ConsumedFlag: @unchecked Sendable { var value = false }
            let consumed = ConsumedFlag()
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if consumed.value {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed.value = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, out.frameLength > 0 else { return }
            cont.yield(AnalyzerInput(buffer: out))
        }

        engine.prepare()
        try engine.start()
        startedAt = ContinuousClock.now
        stoppedAt = nil
        return stream
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        stoppedAt = ContinuousClock.now
        continuation?.finish()
        continuation = nil
    }
}

enum AudioCaptureError: Error {
    case converterUnavailable
}
