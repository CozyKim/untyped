import AVFAudio
import Foundation
import Observation

/// 상태 기계와 실제 컴포넌트를 잇는 유일한 지점.
/// 하위 모듈들은 서로를 모른다.
@MainActor
@Observable
final class Coordinator {
    private(set) var state: DictationState = .idle
    private(set) var level: Float = 0
    /// 다듬기 서버에 연결할 수 있는지. 메뉴가 이 값을 보고 안내 문구를 보여준다.
    /// 다듬기가 실패해도 원본 전사로 자동 대체되므로, 이 값은 받아쓰기 동작
    /// 자체를 막지 않고 상태를 알려주는 용도로만 쓴다.
    private(set) var refinerAvailable = true
    /// 현재 적용된 설정. 설정 창이 초안의 출발점으로 읽고, 메뉴가 단축키 이름을 보여준다.
    private(set) var config: AppConfig

    private let overlay = OverlayController()
    private var refiner: any TextRefiner
    private var hotkey: HotkeyMonitor?
    private var availabilityPoll: Task<Void, Never>?
    private var capture: AudioCapture?
    private var transcriber: Transcriber?
    /// beginCapture()를 감싼 핸들. 짧게 눌렀다 떼면 setup이 끝나기 전에
    /// finishAndInsert()가 먼저 시작될 수 있어, 그 가드가 "설정 실패"가 아니라
    /// "아직 안 끝남"을 보고 오판하지 않도록 이 핸들을 먼저 기다리게 한다.
    private var captureSetup: Task<Void, Never>?

    init(config: AppConfig) {
        self.config = config
        self.refiner = Self.makeRefiner(config)
    }

    func start() {
        installHotkey(config.hotkey)
        restartAvailabilityPoll()
    }

    /// 저장된 새 설정을 즉시 반영한다. 재시작이 필요 없다.
    func apply(_ newConfig: AppConfig) {
        let previousHotkey = config.hotkey
        config = newConfig
        refiner = Self.makeRefiner(newConfig)
        // 키가 같으면 모니터를 그대로 둔다 — 교체하면 진행 중인 hold의 뗌을 놓친다.
        // start() 전이면 start()가 config.hotkey로 설치하므로 여기서 만들지 않는다.
        if newConfig.hotkey != previousHotkey, let current = hotkey {
            current.stop()
            installHotkey(newConfig.hotkey)
        }
        restartAvailabilityPoll()
    }

    /// 다듬기 백엔드는 OpenAI 호환 서버 하나뿐이다. 설정으로 주소·모델·키만 갈아끼운다.
    private static func makeRefiner(_ config: AppConfig) -> any TextRefiner {
        OpenAICompatibleRefiner(
            baseURL: config.baseURL, model: config.model, apiKey: config.apiKeyOrNil,
            systemPrompt: config.systemPrompt ?? RefinementPrompt.defaultSystemPrompt,
            includeExamples: config.includeExamples,
            maxTokens: config.maxTokens
        )
    }

    private func installHotkey(_ key: HotkeyKey) {
        let monitor = HotkeyMonitor(key: key) { [weak self] event in
            self?.handle(event)
        }
        monitor.start()
        hotkey = monitor
    }

    /// 다듬기 서버 연결 가능 여부를 주기적으로 확인한다. 설정이 바뀌면 새로 시작해
    /// 메뉴의 안내가 최대 10초 뒤가 아니라 곧바로 새 서버를 반영하게 한다.
    private func restartAvailabilityPoll() {
        availabilityPoll?.cancel()
        availabilityPoll = Task { await pollRefinerAvailability() }
    }

    private func pollRefinerAvailability() async {
        while !Task.isCancelled {
            let available = await refiner.isAvailable
            // 취소된 뒤 돌아온 결과는 이전 서버의 것이다. 새 폴링이 쓰게 둔다.
            guard !Task.isCancelled else { return }
            refinerAvailable = available
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private func handle(_ event: TriggerEvent) {
        // 토글을 끄면 "짧은 누름"이 성립하지 않아 keyUp이 항상 처리로 넘어간다 — push-to-talk.
        let threshold: Duration = config.toggleEnabled ? DictationTuning.holdThreshold : .zero
        let (next, effect) = reduce(state, event, now: .now, threshold: threshold)
        state = next
        switch effect {
        case .startCapture:
            overlay.show(status: .recording)
            captureSetup = Task { await beginCapture() }
        case .stopCaptureAndProcess:
            overlay.show(status: .refining)
            Task { await finishAndInsert() }
        case .none:
            break
        }
    }

    private func beginCapture() async {
        do {
            let format = try await Transcriber.targetAudioFormat()
            let newTranscriber = Transcriber()
            let newCapture = AudioCapture(targetFormat: format) { [weak self] value in
                Task { @MainActor in
                    self?.level = value
                    self?.overlay.update(level: value)
                }
            }
            let stream = try await newCapture.start()
            try await newTranscriber.begin(inputSequence: stream)
            capture = newCapture
            transcriber = newTranscriber
        } catch {
            NSLog("[Coordinator] 녹음 시작 실패: %@", String(describing: error))
            reset()
        }
    }

    private func finishAndInsert() async {
        // 짧게 눌렀다 떼면 beginCapture()의 세 번의 await(포맷 조회, 마이크 시작,
        // 분석기 시작)가 아직 안 끝난 채로 여기 먼저 도착할 수 있다. 기다리지
        // 않으면 아래 가드가 capture/transcriber를 nil로 보고 "설정 실패"로
        // 오판해 즉시 idle로 돌아가는데, beginCapture()는 뒤늦게 계속 진행되어
        // 아무도 멈추지 않는 마이크와 SpeechAnalyzer를 남긴다.
        await captureSetup?.value
        guard let capture, let transcriber else { reset(); return }
        let recorded = await capture.recordedDuration
        await capture.stop()

        let raw = (try? await transcriber.finish()) ?? ""
        // 빈 문자열이면 아무 동작도 하지 않는다. 빈 붙여넣기를 막는다.
        guard !raw.isEmpty else { reset(); return }

        let outcome = await refineOrFallback(raw, using: refiner, timeout: refineTimeout(
            for: recorded, base: .seconds(config.refineTimeoutSeconds)
        ))
        await TextInserter.insert(outcome.text)
        reset()
        if case .fallback(_, let reason) = outcome {
            overlay.showNotice("\(reason.label) — 원본 삽입")
        }
        if config.logEnabled, let url = DictationLog.fileURL {
            let entry = DictationLog.entry(raw: raw, outcome: outcome, recorded: recorded, at: .now)
            // 파일 쓰기는 삽입이 끝난 뒤의 부수 작업이라 메인 액터를 붙들지 않는다.
            Task.detached {
                do {
                    try DictationLog.append(entry, to: url)
                } catch {
                    NSLog("[Coordinator] 로그 기록 실패: %@", String(describing: error))
                }
            }
        }
    }

    private func reset() {
        capture = nil
        transcriber = nil
        captureSetup = nil
        level = 0
        overlay.hide()
        state = .idle
    }
}
