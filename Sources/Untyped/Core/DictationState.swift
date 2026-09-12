import Foundation

/// 받아쓰기 결과가 들어가는 곳. 단축키마다 하나씩 대응한다.
enum InsertDestination: Equatable, Sendable {
    /// 지금 포커스된 앱. 기본 단축키.
    case frontmost
    /// 설정에서 지정한 앱. 앱으로 보내기 단축키.
    case targetApp
}

enum DictationState: Equatable, Sendable {
    case idle
    /// 녹음 중. 어느 키로 시작했는지를 함께 기억해야 그 키만 이 녹음을 끝낼 수 있고,
    /// 끝났을 때 어디에 넣을지 알 수 있다.
    case holding(since: ContinuousClock.Instant, destination: InsertDestination)
    case toggled(destination: InsertDestination)
    case processing

    /// 마이크가 켜져 있어야 하는 상태인지 — 키를 쥐고 있거나 토글로 녹음이 이어지는 동안.
    /// 마이크 준비는 keyDown 뒤 비동기로 끝나므로, 준비가 끝난 시점에 이 값을 봐야
    /// 그 사이에 키가 올라온 짧은 누름에 뒤늦게 음소거를 걸지 않는다.
    var isListening: Bool {
        switch self {
        case .holding, .toggled: true
        case .idle, .processing: false
        }
    }
}

enum TriggerEvent: Sendable {
    case keyDown
    case keyUp
}

enum Effect: Equatable, Sendable {
    case startCapture
    case stopCaptureAndProcess(InsertDestination)
    case none
}

enum DictationTuning {
    /// 이 시간보다 짧게 눌렀다 떼면 토글 녹음으로 들어간다.
    static let holdThreshold: Duration = .milliseconds(250)
}

/// `destination`은 이 이벤트를 보낸 키다. 녹음 중인 상태의 destination과 다르면 다른 키의
/// 이벤트이므로 무시한다 — 기본 키를 누른 채 앱으로 보내기 키를 떼도 홀드가 끝나지 않는다.
func reduce(
    _ state: DictationState,
    _ event: TriggerEvent,
    from destination: InsertDestination,
    now: ContinuousClock.Instant,
    threshold: Duration
) -> (DictationState, Effect) {
    switch (state, event) {
    case (.idle, .keyDown):
        return (.holding(since: now, destination: destination), .startCapture)
    case (.idle, .keyUp):
        return (.idle, .none)
    case (.holding(let start, let active), .keyUp) where active == destination:
        if now - start < threshold {
            return (.toggled(destination: active), .none)
        }
        return (.processing, .stopCaptureAndProcess(active))
    case (.holding, .keyUp):
        return (state, .none)
    case (.holding, .keyDown):
        return (state, .none)
    case (.toggled(let active), .keyDown) where active == destination:
        return (.processing, .stopCaptureAndProcess(active))
    case (.toggled, .keyDown):
        return (state, .none)
    case (.toggled, .keyUp):
        return (state, .none)
    case (.processing, _):
        return (.processing, .none)
    }
}
