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
    /// 오디오를 한 요청으로 다듬는 쪽. 텍스트 다듬기와 같은 서버 클라이언트다.
    private var audioRefiner: any AudioRefiner
    private var hotkey: HotkeyMonitor?
    /// 앱으로 보내기 단축키. 설정에 없으면 nil.
    private var targetAppHotkey: HotkeyMonitor?
    private var availabilityPoll: Task<Void, Never>?
    /// 설정이 켜져 있으면 주기적으로 모델을 건드려 서버의 유휴 TTL을 새로 시작한다.
    private let keepAlive = KeepAlive()
    private var capture: AudioCapture?
    /// 녹음을 받는 쪽. 설정의 전사 방식에 따라 둘 중 하나만 있다.
    private var transcriber: Transcriber?
    private var recorder: AudioRecorder?
    /// 이번 녹음이 시작될 때의 전사 방식. Apple 두 경로(다듬기 있음·없음)는 싱크가 같아 어느 싱크가
    /// 살아 있는지만으로는 가릴 수 없고, 녹음 중에 설정이 바뀌어도 이 녹음은 시작한 쪽을 따라야 한다.
    private var captureBackend: TranscriptionBackend = .apple
    private let muter = SystemAudioMuter()
    /// beginCapture()를 감싼 핸들. 짧게 눌렀다 떼면 setup이 끝나기 전에
    /// finishAndInsert()가 먼저 시작될 수 있어, 그 가드가 "설정 실패"가 아니라
    /// "아직 안 끝남"을 보고 오판하지 않도록 이 핸들을 먼저 기다리게 한다.
    private var captureSetup: Task<Void, Never>?
    /// 녹음 세션 번호. 미리보기 콜백이 자기 번호를 들고 있어, 다음 녹음이 시작된 뒤 도착한 이전 녹음의
    /// 중간 결과를 걸러 낸다.
    private var captureSession = 0
    /// 이번 녹음의 예열 요청 시각. 다듬기가 시간 초과됐을 때 콜드 스타트(모델 로드) 때문이었는지
    /// 로그에 적기 위해 시작과 완료를 기억한다.
    private var warmUpStartedAt: ContinuousClock.Instant?
    private var warmUpFinishedAt: ContinuousClock.Instant?
    /// 서버가 모델이 올라와 있다고 답해 이번 녹음에는 예열 요청을 보내지 않았다.
    private var warmUpSkipped = false
    /// 직전 로그 쓰기. 다음 쓰기가 이걸 기다려 파일에 순서대로 붙는다.
    private var logWrite: Task<Void, Never>?

    init(config: AppConfig) {
        self.config = config
        let client = Self.makeClient(config)
        self.refiner = client
        self.audioRefiner = client
    }

    func start() {
        hotkey = makeMonitor(config.hotkey, destination: .frontmost)
        targetAppHotkey = config.targetAppHotkey.map { makeMonitor($0, destination: .targetApp) }
        restartAvailabilityPoll()
        restartKeepAlive()
    }

    /// 저장된 새 설정을 즉시 반영한다. 재시작이 필요 없다.
    func apply(_ newConfig: AppConfig) {
        let previous = config
        config = newConfig
        let client = Self.makeClient(newConfig)
        refiner = client
        audioRefiner = client
        // 키가 같으면 모니터를 그대로 둔다 — 교체하면 진행 중인 hold의 뗌을 놓친다.
        // start() 전이면(hotkey == nil) start()가 config로 설치하므로 여기서 만들지 않는다.
        if hotkey != nil {
            if newConfig.hotkey != previous.hotkey {
                hotkey?.stop()
                hotkey = makeMonitor(newConfig.hotkey, destination: .frontmost)
            }
            if newConfig.targetAppHotkey != previous.targetAppHotkey {
                targetAppHotkey?.stop()
                targetAppHotkey = newConfig.targetAppHotkey.map { makeMonitor($0, destination: .targetApp) }
            }
        }
        restartAvailabilityPoll()
        restartKeepAlive()
    }

    /// 다듬기 백엔드는 OpenAI 호환 서버 하나뿐이다. 설정으로 주소·모델·키만 갈아끼운다.
    /// 같은 서버가 오디오를 한 요청으로 다듬는 일도 맡는다.
    private static func makeClient(_ config: AppConfig) -> OpenAICompatibleRefiner {
        OpenAICompatibleRefiner(
            baseURL: config.baseURL, model: config.model, apiKey: config.apiKeyOrNil,
            systemPrompt: config.systemPrompt ?? RefinementPrompt.defaultSystemPrompt,
            includeExamples: config.includeExamples,
            maxTokens: config.maxTokens
        )
    }

    /// 모니터마다 출처를 붙여 둔다. 같은 handle이 두 키를 받지만, 어느 키인지는
    /// 상태 기계가 구분해야 하므로 여기서 destination을 정해 넘긴다.
    private func makeMonitor(_ key: HotkeyKey, destination: InsertDestination) -> HotkeyMonitor {
        let monitor = HotkeyMonitor(key: key) { [weak self] event in
            self?.handle(event, from: destination)
        }
        monitor.start()
        return monitor
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

    /// 설정이 바뀌면 새 서버·간격으로 다시 시작한다. 진행 중이던 요청은 취소된다. 꺼져 있으면 멈추기만
    /// 한다. 받아쓰기가 진행 중인 주기는 건너뛴다 — 그 다듬기 요청이 모델을 건드리고, 끼어든 요청은
    /// 다듬기 응답만 늦춘다.
    private func restartKeepAlive() {
        let refiner = refiner
        keepAlive.start(
            every: config.keepAlivePeriod,
            isBusy: { [weak self] in self?.state != .idle },
            touch: { try await refiner.keepAlive() }
        )
    }

    private func handle(_ event: TriggerEvent, from destination: InsertDestination) {
        // 앱으로 보내기는 대상 앱이 실행 중일 때만 시작한다. 말하기 전에 알려야 헛수고가
        // 없으므로 녹음 시작 시점에 확인하고, reduce에 넘기지 않아 상태는 idle로 남긴다.
        if destination == .targetApp, state == .idle, case .keyDown = event {
            guard let bundleID = config.targetAppBundleID,
                  TargetApp.runningApplication(bundleID: bundleID) != nil
            else {
                overlay.showNotice("\(targetAppName) 앱이 실행 중이 아님")
                return
            }
        }
        // 토글을 끄면 "짧은 누름"이 성립하지 않아 keyUp이 항상 처리로 넘어간다 — push-to-talk.
        let threshold: Duration = config.toggleEnabled ? DictationTuning.holdThreshold : .zero
        let (next, effect) = reduce(state, event, from: destination, now: .now, threshold: threshold)
        state = next
        switch effect {
        case .startCapture:
            overlay.show(status: .listening)
            // 키를 누르는 순간 다듬기 서버를 깨운다. 말하는 동안 모델 로드와 프리픽스
            // 캐시가 끝나 있어야 전사 직후 바로 다듬을 수 있다. 결과는 기다리지 않는다.
            // 서버가 모델이 이미 올라와 있다고 답하면(oMLX /health) 1토큰 요청도 보내지 않는다 —
            // 녹음 시작과 겹치는 부하를 줄인다. 확인이 안 되는 서버는 지금까지처럼 예열한다.
            // 예열을 꺼 두면 health 확인도 하지 않는다 — 그 결과로 정하는 일이 예열뿐이다.
            // STT만 쓰는 경로는 LLM에 아무것도 묻지 않으므로 예열도 없다.
            // 상태는 매번 비워 이전 녹음의 예열 시각이 이번 로그에 섞이지 않게 한다.
            warmUpStartedAt = nil
            warmUpFinishedAt = nil
            warmUpSkipped = false
            if config.warmUpEnabled, config.transcriptionBackend.refinesText {
                let refiner = refiner
                let startedAt = ContinuousClock.now
                warmUpStartedAt = startedAt
                Task { [weak self] in
                    let needsWarmUp = await refiner.health.needsWarmUp
                    if needsWarmUp {
                        await refiner.warmUp()
                    }
                    // 다음 녹음이 이미 시작됐으면 그쪽 예열이 기준이므로 덮어쓰지 않는다.
                    guard let self, self.warmUpStartedAt == startedAt else { return }
                    self.warmUpSkipped = !needsWarmUp
                    self.warmUpFinishedAt = .now
                }
            }
            captureSession += 1
            captureSetup = Task { await beginCapture() }
        case .stopCaptureAndProcess(let destination):
            overlay.show(status: .refining)
            Task { await finishAndInsert(destination: destination) }
        case .none:
            break
        }
    }

    /// 알림 문구용. 설정에 앱이 없으면 "대상"으로 대체해 문장이 깨지지 않게 한다.
    private var targetAppName: String {
        config.targetAppBundleID.map(TargetApp.displayName(bundleID:)) ?? "대상"
    }

    private func beginCapture() async {
        let session = captureSession
        // 음소거 대상 고르기는 프로세스마다 coreaudiod에 물어 40ms 넘게 걸린다. 마이크 준비와
        // 겹쳐 돌려 음소거가 걸리는 시점을 늦추지 않는다.
        async let renderers = muter.tapRenderers()
        do {
            // 백엔드는 녹음 시작 시점의 설정을 따른다. 녹음 중에 바뀌어도 이 녹음은 시작한
            // 쪽이 받는다 — finishAndInsert()는 어느 싱크가 살아 있는지와 이 스냅샷으로 판단한다.
            let backend = config.transcriptionBackend
            captureBackend = backend
            let format: AVAudioFormat
            switch backend {
            case .apple, .appleOnly: format = try await Transcriber.targetAudioFormat()
            case .llmAudio: format = AudioRecorder.format
            }
            let newCapture = AudioCapture(targetFormat: format) { [weak self] value in
                Task { @MainActor in
                    self?.level = value
                    self?.overlay.update(level: value)
                }
            }
            let stream = try await newCapture.start()
            switch backend {
            case .apple, .appleOnly:
                let newTranscriber = Transcriber()
                // 미리보기는 이 경로에만 있다 — 1단계(LLM 오디오)는 Apple STT를 쓰지 않아 중간 결과가 없다.
                try await newTranscriber.begin(inputSequence: stream) { [weak self] text in
                    Task { @MainActor in self?.showPreview(text, from: session) }
                }
                transcriber = newTranscriber
            case .llmAudio:
                let newRecorder = AudioRecorder()
                await newRecorder.begin(inputSequence: stream)
                recorder = newRecorder
            }
            capture = newCapture
            // 마이크와 분석기가 먼저 돌기 시작한 뒤에 음소거한다. 탭과 aggregate device를
            // 만드는 데 100~200ms가 걸려, 먼저 하면 그만큼 첫 음절을 놓친다.
            // 여기까지 오는 데 150ms 이상 걸리므로 짧게 눌렀다 떼면 이미 키가 올라와 있다.
            // 그때 걸면 finishAndInsert()가 곧 풀긴 해도 뗀 뒤 200~500ms 동안 소리가 끊겼다
            // 돌아오는 게 들리고, 녹음은 끝났으니 막을 되울림도 없다.
            if state.isListening {
                await muter.mute(renderers: await renderers)
            }
        } catch {
            NSLog("[Coordinator] 녹음 시작 실패: %@", String(describing: error))
            reset()
        }
    }

    /// 미리보기 분석기가 보낸 잠정 전사. 지금 녹음의 것이고 아직 듣는 중일 때만 오버레이에 올린다.
    /// 삽입·로그와는 무관하다 — 그쪽은 finish()가 돌려주는 확정 전사만 쓴다.
    private func showPreview(_ text: String, from session: Int) {
        guard acceptsPreview(from: session, current: captureSession, state: state) else { return }
        overlay.update(preview: text)
    }

    private func finishAndInsert(destination: InsertDestination) async {
        // 짧게 눌렀다 떼면 beginCapture()의 네 번의 await(포맷 조회, 마이크 시작,
        // 분석기 시작, 음소거)가 아직 안 끝난 채로 여기 먼저 도착할 수 있다. 기다리지
        // 않으면 아래 가드가 capture/transcriber를 nil로 보고 "설정 실패"로
        // 오판해 즉시 idle로 돌아가는데, beginCapture()는 뒤늦게 계속 진행되어
        // 아무도 멈추지 않는 마이크와 SpeechAnalyzer를 남긴다.
        await captureSetup?.value
        guard let capture else { reset(); return }
        let recorded = await capture.recordedDuration
        await capture.stop()
        // 다듬는 동안에는 소리가 돌아와 있어야 하므로 삽입까지 기다리지 않는다.
        await muter.unmute()

        // 삽입 중에 설정이 교체돼도 로그는 실제로 다듬기를 시도한 서버를 가리켜야 한다.
        let refiner = refiner
        let baseURL = config.baseURL
        let base: Duration = .seconds(config.refineTimeoutSeconds)
        // 2단계(Apple)는 원문이 있어 다듬기가 실패해도 원본을 넣는다. 1단계(LLM 오디오)는 원문이
        // 없어 실패하면 아무것도 넣지 않는다 — 그 경우는 refineAudioOrGiveUp()이 알림·로그까지 마친다.
        let raw: String?
        let timeout: Duration
        let outcome: RefineOutcome
        // 로그에 남길 단계별 소요 시간. 어느 단계가 느렸는지 로그만 보고 가릴 수 있어야 한다.
        let timing: DictationTiming
        if let transcriber {
            let transcriptionStartedAt = ContinuousClock.now
            let text = (try? await transcriber.finish()) ?? ""
            let transcription = ContinuousClock.now - transcriptionStartedAt
            // 빈 문자열이면 아무 동작도 하지 않는다. 빈 붙여넣기를 막는다.
            guard !text.isEmpty else { reset(); return }
            raw = text
            timeout = refineTimeout(for: recorded, base: base)
            if captureBackend.refinesText {
                let refinementStartedAt = ContinuousClock.now
                outcome = await refineOrFallback(text, using: refiner, timeout: timeout)
                timing = .apple(transcription: transcription, refinement: .now - refinementStartedAt)
            } else {
                outcome = .transcribed(text)
                timing = .appleOnly(transcription: transcription)
            }
        } else if let recorder {
            let wav = await recorder.finish()
            guard !wav.isEmpty else { reset(); return }
            raw = nil
            timeout = audioRefineTimeout(for: recorded, base: base)
            guard let (text, request) = await refineAudioOrGiveUp(
                wav, timeout: timeout, recorded: recorded, refiner: refiner, baseURL: baseURL
            ) else { return }
            outcome = .refined(text)
            timing = .llmAudio(request: request)
        } else {
            reset()
            return
        }
        // 예열 상태는 다듬기가 끝난 직후에 읽는다. 로그는 삽입 뒤에 쓰는데 그때는 다음 녹음이
        // 시작돼 예열 시각이 덮여 있을 수 있다.
        let warmUp = warmUpState(now: .now)
        let loggedAt = Date()
        let pressReturn = config.pressesReturn(for: destination, outcome: outcome)
        var insertFailure: String?
        var insertionDiagnostic = ""
        let insertionTarget = destination == .targetApp ? targetAppName : "현재 앱"
        switch destination {
        case .frontmost:
            let result = await TextInserter.insert(
                outcome.text, pressReturn: pressReturn, onDiagnostic: { insertionDiagnostic = $0 }
            )
            if result != .inserted {
                insertFailure = "삽입 확인 안 됨 — 입력창과 클립보드를 확인하세요"
            }
        case .targetApp:
            // 녹음 중에 설정이 바뀌어 대상 앱이 비었으면 실행 중이 아닌 것과 같이 다룬다.
            let result: TargetApp.SendResult
            if let bundleID = config.targetAppBundleID {
                result = await TargetApp.send(
                    outcome.text, toAppWithBundleID: bundleID, pressReturn: pressReturn,
                    onDiagnostic: { insertionDiagnostic = $0 }
                )
            } else {
                result = .notRunning
                insertionDiagnostic = "게시 전 중단 · 대상 앱이 설정되지 않음"
            }
            if result == .unconfirmed {
                insertFailure = "\(targetAppName) 삽입 확인 안 됨 — 입력창과 클립보드를 확인하세요"
            } else if result != .inserted {
                insertFailure = "\(targetAppName) 앱에 넣을 수 없음 — 삽입 안 함"
            }
        }
        reset()
        // 삽입 자체가 안 됐으면 그 사실이 폴백 이유보다 먼저다.
        if let insertFailure {
            overlay.showNotice(insertFailure)
        } else if case .fallback(_, let reason) = outcome {
            overlay.showNotice("\(reason.label) — 원본 삽입")
        }
        if config.logEnabled, let url = DictationLog.fileURL {
            var cause: String?
            if case .fallback(_, let reason) = outcome {
                cause = await fallbackCause(
                    for: reason, timeout: timeout, warmUp: warmUp, refiner: refiner, baseURL: baseURL
                )
            }
            let entry = DictationLog.entry(
                raw: raw, outcome: outcome, recorded: recorded, at: loggedAt, cause: cause, timing: timing,
                insertion: "\(insertionTarget) · \(insertionDiagnostic)"
            )
            appendLog(entry, to: url)
        }
    }

    /// 오디오를 한 요청으로 다듬는다. 결과와 함께 요청에 걸린 시간을 돌려준다. 실패하면 넣을 원본이
    /// 없다 — Apple 전사로 몰래 대체하지 않는다(사용자가 그 경로를 끈 것이므로). 상태를 되돌리고
    /// 실패를 알리고 로그에 원인과 소요 시간을 남긴 뒤 nil을 돌려준다.
    private func refineAudioOrGiveUp(
        _ wav: Data, timeout: Duration, recorded: Duration,
        refiner: any TextRefiner, baseURL: URL
    ) async -> (text: String, took: Duration)? {
        let audioRefiner = audioRefiner
        let startedAt = ContinuousClock.now
        let result = await requestLLMText(timeout: timeout, { try await audioRefiner.refine(wav: wav) })
        let took = ContinuousClock.now - startedAt
        switch result {
        case .text(let text):
            return (text, took)
        case .failed(let reason):
            let warmUp = warmUpState(now: .now)
            let loggedAt = Date()
            reset()
            overlay.showNotice("\(reason.label) — 삽입 안 함")
            if config.logEnabled, let url = DictationLog.fileURL {
                let cause = await fallbackCause(
                    for: reason, timeout: timeout, warmUp: warmUp, refiner: refiner, baseURL: baseURL
                )
                let entry = DictationLog.failureEntry(
                    label: reason.label, recorded: recorded, at: loggedAt, cause: cause,
                    timing: .llmAudio(request: took)
                )
                appendLog(entry, to: url)
            }
            return nil
        }
    }

    /// 파일 쓰기는 삽입이 끝난 뒤의 부수 작업이라 메인 액터를 붙들지 않는다. 다만 연결
    /// 확인이 최대 2초라 다음 받아쓰기의 로그가 먼저 도착할 수 있으므로, 직전 쓰기를
    /// 기다려 순서를 지킨다 — FileHandle의 seek+write는 두 작업이 겹치면 서로 덮어쓴다.
    private func appendLog(_ entry: String, to url: URL) {
        let previous = logWrite
        logWrite = Task.detached {
            await previous?.value
            do {
                try DictationLog.append(entry, to: url)
            } catch {
                NSLog("[Coordinator] 로그 기록 실패: %@", String(describing: error))
            }
        }
    }

    private func warmUpState(now: ContinuousClock.Instant) -> WarmUpState {
        guard let startedAt = warmUpStartedAt else { return .notStarted }
        guard let finishedAt = warmUpFinishedAt else { return .running(for: now - startedAt) }
        return warmUpSkipped ? .skipped : .finished(in: finishedAt - startedAt)
    }

    /// 폴백이나 오디오 다듬기 실패일 때 로그에 적을 원인을 판정한다. 로컬 LLM 서버 연결
    /// 확인(최대 2초)은 삽입과 상태 초기화가 끝난 뒤에 하므로 사용자를 기다리게 하지 않는다.
    private func fallbackCause(
        for reason: FallbackReason, timeout: Duration, warmUp: WarmUpState,
        refiner: any TextRefiner, baseURL: URL
    ) async -> String? {
        switch reason {
        case .timeout, .failed:
            let reachable = await refiner.isAvailable
            return Untyped.fallbackCause(
                reason: reason, timeout: timeout, serverReachable: reachable,
                warmUp: warmUp, baseURL: baseURL
            )
        case .noRefiner, .truncated, .emptyResult:
            return nil
        }
    }

    private func reset() {
        capture = nil
        transcriber = nil
        recorder = nil
        captureSetup = nil
        level = 0
        overlay.hide()
        state = .idle
    }
}
