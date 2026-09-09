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

    func begin(inputSequence: AsyncStream<AnalyzerInput>) async throws {
        // MVP에 실시간 미리보기가 없으므로 volatileResults가 필요 없다.
        // 미리보기를 넣을 때 .progressiveTranscription 계열로 교체한다.
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        let engine = SpeechAnalyzer(modules: [module])
        transcriber = module
        analyzer = engine

        collector = Task {
            var text = ""
            for try await result in module.results {
                text += String(result.text.characters)
            }
            return text
        }
        try await engine.start(inputSequence: inputSequence)
    }

    /// 입력 스트림이 닫힌 뒤 호출한다. 남은 결과를 마무리하고 전체 텍스트를 돌려준다.
    func finish() async throws -> String {
        guard let analyzer, let collector else { return "" }
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = try await collector.value
        self.analyzer = nil
        self.transcriber = nil
        self.collector = nil
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TranscriberError: Error {
    case noCompatibleAudioFormat
}
