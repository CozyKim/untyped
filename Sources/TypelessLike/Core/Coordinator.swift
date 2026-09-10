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

    private let overlay = OverlayController()
    private let refiner: (any TextRefiner)?
    private var hotkey: HotkeyMonitor?
    private var capture: AudioCapture?
    private var transcriber: Transcriber?
    /// beginCapture()를 감싼 핸들. 짧게 눌렀다 떼면 setup이 끝나기 전에
    /// finishAndInsert()가 먼저 시작될 수 있어, 그 가드가 "설정 실패"가 아니라
    /// "아직 안 끝남"을 보고 오판하지 않도록 이 핸들을 먼저 기다리게 한다.
    private var captureSetup: Task<Void, Never>?

    init(refiner: (any TextRefiner)?) {
        self.refiner = refiner
    }

    func start() {
        let monitor = HotkeyMonitor { [weak self] event in
            self?.handle(event)
        }
        monitor.start()
        hotkey = monitor
        Task { await pollRefinerAvailability() }
    }

    /// 다듬기 서버 연결 가능 여부를 주기적으로 확인한다. 앱이 떠 있는 동안
    /// 계속 돈다 — hotkey 감시와 마찬가지로 앱 종료와 함께 끝난다.
    private func pollRefinerAvailability() async {
        guard let refiner else { return }
        while true {
            refinerAvailable = await refiner.isAvailable
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private func handle(_ event: TriggerEvent) {
        let (next, effect) = reduce(state, event, now: .now, threshold: DictationTuning.holdThreshold)
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

        let text = await refineOrFallback(raw, using: refiner, timeout: refineTimeout(for: recorded))
        await TextInserter.insert(text)
        reset()
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
