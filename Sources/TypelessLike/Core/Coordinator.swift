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

    private let overlay = OverlayController()
    private let refiner: (any TextRefiner)?
    private var hotkey: HotkeyMonitor?
    private var capture: AudioCapture?
    private var transcriber: Transcriber?

    init(refiner: (any TextRefiner)?) {
        self.refiner = refiner
    }

    func start() {
        let monitor = HotkeyMonitor { [weak self] event in
            self?.handle(event)
        }
        monitor.start()
        hotkey = monitor
    }

    private func handle(_ event: TriggerEvent) {
        let (next, effect) = reduce(state, event, now: .now, threshold: DictationTuning.holdThreshold)
        state = next
        switch effect {
        case .startCapture:
            overlay.show(status: .recording)
            Task { await beginCapture() }
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
        level = 0
        overlay.hide()
        state = .idle
    }
}
