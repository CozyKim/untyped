import AVFAudio
import Foundation
import Speech

/// SpeechAnalyzer와 SpeechTranscriber를 감싸 오디오 스트림을 문자열로 만든다.
/// HTTP도 프롬프트도 모른다.
actor Transcriber {
    private let locale: Locale
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var collector: Task<String, Error>?
    /// 입력을 분석기로 그대로 흘려보내며 개수만 센다.
    private var forwarder: Task<Void, Never>?
    private var forwardedInputs = 0
    /// 미리보기용 두 번째 분석기. 확정용과 같은 입력을 받되 작은 문맥 창(fastResults)으로 말한 지
    /// 1초 안에 잠정 결과를 낸다. 확정 텍스트는 절대 여기서 가져오지 않는다 — 빠른 모드는 정확도가
    /// 떨어진다. 확정용 모듈에 잠정 결과만 켜는 것으로는 안 된다 — 그 모듈은 12~20초 창 단위로만
    /// 결과를 내서 짧은 받아쓰기에서는 키를 쥔 동안 아무것도 오지 않고, 한 분석기에 두 모듈을 붙이면
    /// 빠른 쪽도 느린 쪽에 묶인다. 키를 떼면 마무리하지 않고 바로 버린다.
    private var previewAnalyzer: SpeechAnalyzer?
    /// 미리보기 분석기의 start(). 확정 경로가 이를 기다리지 않도록 별도 태스크로 돌린다.
    private var previewStarter: Task<Void, Never>?
    private var previewCollector: Task<Void, Never>?
    private var previewContinuation: AsyncStream<AnalyzerInput>.Continuation?

    init(locale: Locale = Locale(identifier: "ko-KR")) {
        self.locale = locale
    }

    /// 전사기가 요구하는 오디오 포맷. AudioCapture가 여기에 맞춰 변환한다.
    static func targetAudioFormat(locale: Locale = Locale(identifier: "ko-KR")) async throws -> AVAudioFormat {
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw TranscriberError.noCompatibleAudioFormat
        }
        return format
    }

    /// `onPreview`를 주면 듣는 동안 잠정 전사(확정 + 잠정)를 갱신될 때마다 보낸다. 어느 스레드에서
    /// 불릴지 정해져 있지 않으므로 받는 쪽이 자기 격리로 옮긴다. `finish()`가 시작되면 더 오지 않는다.
    func begin(
        inputSequence: AsyncStream<AnalyzerInput>,
        onPreview: (@Sendable (String) -> Void)? = nil
    ) async throws {
        // 이전 세션이 진행 중이면 정리한다. 새 세션 시작 시 이전 상태를 명시적으로 취소한다.
        // 핸들을 버리는 것만으로는 Task와 Analyzer가 취소되지 않으므로 명시적으로 정리해야 한다.
        if let previousAnalyzer = analyzer {
            await teardown(for: previousAnalyzer)
        }

        // 확정용은 잠정 결과 없이 둔다. 미리보기는 아래 별도 분석기가 맡는다.
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        let engine = SpeechAnalyzer(modules: [module])
        transcriber = module
        analyzer = engine

        // 미리보기 입력. 확정용과 같은 버퍼를 한 번 더 흘린다.
        var previewStream: AsyncStream<AnalyzerInput>?
        if onPreview != nil {
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            previewStream = stream
            previewContinuation = continuation
        }
        let previewContinuation = self.previewContinuation

        // 분석기가 버퍼를 하나도 받지 못한 채 입력이 닫히면 module.results가 끝나지
        // 않는다. 그 상태에서 finish()가 결과를 기다리면 영영 돌아오지 않으므로
        // 몇 개를 넘겼는지 세어 두었다가 finish()에서 그 경우를 피한다.
        forwardedInputs = 0
        let (counted, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        forwarder = Task { [weak self] in
            for await input in inputSequence {
                continuation.yield(input)
                previewContinuation?.yield(input)
                await self?.noteForwardedInput()
            }
            continuation.finish()
            previewContinuation?.finish()
        }

        collector = Task {
            var text = ""
            for try await result in module.results {
                text += String(result.text.characters)
            }
            return text
        }
        do {
            try await engine.start(inputSequence: counted)
        } catch {
            await teardown(for: engine)
            throw error
        }
        if let onPreview, let previewStream {
            startPreview(inputSequence: previewStream, onPreview: onPreview)
        }
    }

    private func noteForwardedInput() {
        forwardedInputs += 1
    }

    /// 미리보기 분석기를 띄운다. 시작을 기다리지 않는다 — 확정 경로(마이크 준비, 음소거, finalize)가
    /// 미리보기 때문에 늦어져서는 안 된다. 실패해도 받아쓰기는 계속된다.
    private func startPreview(
        inputSequence: AsyncStream<AnalyzerInput>, onPreview: @escaping @Sendable (String) -> Void
    ) {
        let module = SpeechTranscriber(
            locale: locale, transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults], attributeOptions: []
        )
        let engine = SpeechAnalyzer(modules: [module])
        previewAnalyzer = engine
        previewCollector = Task {
            var transcript = InterimTranscript()
            do {
                for try await result in module.results {
                    transcript.add(String(result.text.characters), isFinal: result.isFinal)
                    // 취소된 뒤 도착한 결과는 보내지 않는다.
                    guard !Task.isCancelled else { return }
                    onPreview(transcript.text)
                }
            } catch {
                // 취소·오류로 결과가 끊기면 미리보기만 멈춘다. 확정 경로와는 별개다.
            }
        }
        previewStarter = Task.detached {
            do {
                try await engine.start(inputSequence: inputSequence)
            } catch {
                NSLog("[Transcriber] 미리보기 시작 실패: %@", String(describing: error))
            }
        }
    }

    /// 미리보기 분석기를 버린다. 마무리하지 않는다 — 키를 뗀 뒤의 잠정 결과는 쓸 데가 없다. 결과
    /// 태스크와 입력은 여기서 바로 끊고, 분석기 취소는 기다리지 않는다 — 확정 finalize가 그 뒤에
    /// 줄 서면 그만큼 삽입이 늦어진다. 취소는 start()가 끝난 뒤에 해야 하므로 시작 태스크를 먼저
    /// 기다린다. 없으면 아무것도 하지 않는다.
    private func stopPreview() {
        previewCollector?.cancel()
        previewContinuation?.finish()
        previewCollector = nil
        previewContinuation = nil
        guard let engine = previewAnalyzer else { return }
        let starter = previewStarter
        previewAnalyzer = nil
        previewStarter = nil
        Task.detached {
            await starter?.value
            await engine.cancelAndFinishNow()
        }
    }

    /// 입력 스트림이 닫힌 뒤 호출한다. 남은 결과를 마무리하고 전체 텍스트를 돌려준다.
    func finish() async throws -> String {
        // 키를 뗐다. 미리보기는 여기서 끝이다 — 확정 finalize보다 먼저 버린다.
        stopPreview()
        guard let analyzer, let collector else { return "" }

        // 스트림은 이미 닫혔으므로 전달이 끝나기를 잠깐 기다리면 개수가 확정된다.
        await forwarder?.value
        guard forwardedInputs > 0 else {
            await teardown(for: analyzer)
            return ""
        }

        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let text = try await collector.value
            // 정상 경로: 현재 세션을 정리하고 텍스트를 반환한다.
            await teardown(for: analyzer)
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // 오류 경로: 현재 세션을 정리하고 오류를 재발생한다.
            await teardown(for: analyzer)
            throw error
        }
    }

    private func teardown(for session: SpeechAnalyzer) async {
        // 현재 세션이 이것과 같을 경우만 정리한다. re-entry 중에는 새 세션이 이미 설정되어 있을 수 있다.
        guard analyzer === session else { return }

        // 핸들을 버리는 것만으로는 Task가 취소되지 않으므로 명시적으로 취소해야 한다.
        collector?.cancel()
        forwarder?.cancel()

        // await 전에 프로퍼티를 nil하여 stale 쓰기 경쟁을 방지한다.
        // session 로컬이 강한 참조를 유지하므로 await 중에도 session은 유효하다.
        // 이 순서로 진행하면 identity 체크 후 await 전까지 다른 재진입이 상태를 변경할 수 없다.
        self.analyzer = nil
        self.transcriber = nil
        self.collector = nil
        self.forwarder = nil
        stopPreview()

        // Analyzer는 자신의 분석 작업으로 인해 자기 자신을 retain하고 있다.
        // 분석을 시작했으면 드롭만으로는 deallocate되지 않으므로 명시적으로 정리해야 한다.
        await session.cancelAndFinishNow()
    }
}

enum TranscriberError: Error {
    case noCompatibleAudioFormat
}
