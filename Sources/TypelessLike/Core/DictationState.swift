import Foundation

enum DictationState: Equatable, Sendable {
    case idle
    case holding(since: ContinuousClock.Instant)
    case toggled
    case processing
}

enum TriggerEvent: Sendable {
    case keyDown
    case keyUp
}

enum Effect: Equatable, Sendable {
    case startCapture
    case stopCaptureAndProcess
    case none
}

enum DictationTuning {
    /// 이 시간보다 짧게 눌렀다 떼면 토글 녹음으로 들어간다.
    static let holdThreshold: Duration = .milliseconds(250)
}

func reduce(
    _ state: DictationState,
    _ event: TriggerEvent,
    now: ContinuousClock.Instant,
    threshold: Duration
) -> (DictationState, Effect) {
    switch (state, event) {
    case (.idle, .keyDown):
        return (.holding(since: now), .startCapture)
    case (.idle, .keyUp):
        return (.idle, .none)
    case (.holding(let start), .keyUp):
        if now - start < threshold {
            return (.toggled, .none)
        }
        return (.processing, .stopCaptureAndProcess)
    case (.holding(let start), .keyDown):
        return (.holding(since: start), .none)
    case (.toggled, .keyDown):
        return (.processing, .stopCaptureAndProcess)
    case (.toggled, .keyUp):
        return (.toggled, .none)
    case (.processing, _):
        return (.processing, .none)
    }
}
