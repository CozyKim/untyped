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
    /// 앱으로 보내기 단축키. 설정에 없으면 nil.
    private var targetAppHotkey: HotkeyMonitor?
    private var availabilityPoll: Task<Void, Never>?
    private var capture: AudioCapture?
    private var transcriber: Transcriber?
    private let muter = SystemAudioMuter()
    /// beginCapture()를 감싼 핸들. 짧게 눌렀다 떼면 setup이 끝나기 전에
    /// finishAndInsert()가 먼저 시작될 수 있어, 그 가드가 "설정 실패"가 아니라
    /// "아직 안 끝남"을 보고 오판하지 않도록 이 핸들을 먼저 기다리게 한다.
    private var captureSetup: Task<Void, Never>?

    init(config: AppConfig) {
        self.config = config
        self.refiner = Self.makeRefiner(config)
    }

    func start() {
        hotkey = makeMonitor(config.hotkey, destination: .frontmost)
        targetAppHotkey = config.targetAppHotkey.map { makeMonitor($0, destination: .targetApp) }
        restartAvailabilityPoll()
    }

    /// 저장된 새 설정을 즉시 반영한다. 재시작이 필요 없다.
    func apply(_ newConfig: AppConfig) {
        let previous = config
        config = newConfig
        refiner = Self.makeRefiner(newConfig)
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
            let refiner = refiner
            Task { await refiner.warmUp() }
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
            // 마이크와 분석기가 먼저 돌기 시작한 뒤에 음소거한다. 탭과 aggregate device를
            // 만드는 데 100~200ms가 걸려, 먼저 하면 그만큼 첫 음절을 놓친다.
            await muter.mute()
        } catch {
            NSLog("[Coordinator] 녹음 시작 실패: %@", String(describing: error))
            reset()
        }
    }

    private func finishAndInsert(destination: InsertDestination) async {
        // 짧게 눌렀다 떼면 beginCapture()의 네 번의 await(포맷 조회, 마이크 시작,
        // 분석기 시작, 음소거)가 아직 안 끝난 채로 여기 먼저 도착할 수 있다. 기다리지
        // 않으면 아래 가드가 capture/transcriber를 nil로 보고 "설정 실패"로
        // 오판해 즉시 idle로 돌아가는데, beginCapture()는 뒤늦게 계속 진행되어
        // 아무도 멈추지 않는 마이크와 SpeechAnalyzer를 남긴다.
        await captureSetup?.value
        guard let capture, let transcriber else { reset(); return }
        let recorded = await capture.recordedDuration
        await capture.stop()
        // 다듬는 동안에는 소리가 돌아와 있어야 하므로 삽입까지 기다리지 않는다.
        await muter.unmute()

        let raw = (try? await transcriber.finish()) ?? ""
        // 빈 문자열이면 아무 동작도 하지 않는다. 빈 붙여넣기를 막는다.
        guard !raw.isEmpty else { reset(); return }

        let outcome = await refineOrFallback(raw, using: refiner, timeout: refineTimeout(
            for: recorded, base: .seconds(config.refineTimeoutSeconds)
        ))
        let pressReturn = config.pressesReturn(for: destination, outcome: outcome)
        var insertFailure: String?
        switch destination {
        case .frontmost:
            await TextInserter.insert(outcome.text, pressReturn: pressReturn)
        case .targetApp:
            // 녹음 중에 설정이 바뀌어 대상 앱이 비었으면 실행 중이 아닌 것과 같이 다룬다.
            let result: TargetApp.SendResult
            if let bundleID = config.targetAppBundleID {
                result = await TargetApp.send(outcome.text, toAppWithBundleID: bundleID, pressReturn: pressReturn)
            } else {
                result = .notRunning
            }
            if result != .inserted {
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
