import Foundation

/// keepalive 요청 간격. 자유 입력 대신 선택지로 제한한다 — 초 단위로 잦게 두면 서버 부하와 로그만
/// 늘고, 선택지 밖의 값이 파일에 있으면 설정 창의 Picker가 빈 상태가 된다.
/// 파일에는 분 단위 정수로 저장한다.
enum KeepAliveInterval: Int, Codable, CaseIterable, Sendable {
    case oneMinute = 1
    case twoMinutes = 2
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30

    var duration: Duration { .seconds(rawValue * 60) }

    var displayName: String { "\(rawValue)분" }
}

/// 설정한 간격마다 다듬기 서버의 모델을 한 번 건드려 유휴 TTL을 새로 시작한다. 서버가 모델을
/// 고정(pin)할 수 없는 환경에서 첫 받아쓰기의 콜드 스타트를 막는 용도다.
///
/// `GET /health`는 쓰지 않는다 — 서버 상태만 알려줄 뿐 모델의 last_access를 갱신하지 않아
/// TTL이 그대로 흐른다. 실제 chat/completions 요청이어야 한다.
///
/// 네트워크·설정·상태 기계를 모른다 — 요청은 `touch`로, "지금 받아쓰기 중이라 건너뛸지"는
/// `isBusy`로 받는다. 루프가 하나뿐이고 요청 완료 → 대기 → 다음 요청 순서로 돌기 때문에
/// 요청이 겹치지 않는다.
///
/// 실패는 최선 노력이다 — 이유를 한 줄로 기억해 두고 다음 주기에 다시 보낸다. 백오프도 사용자
/// 알림도 없다. 요청마다 걸린 시간을 NSLog 한 줄로 남긴다 — 받아쓰기 로그 파일에는 쓰지 않아
/// 받아쓰기 기록과 섞이지 않는다. API 키와 요청·응답 본문은 어디에도 남기지 않는다.
@MainActor
final class KeepAlive {
    private var loop: Task<Void, Never>?
    /// 직전 요청의 실패 이유. 성공하면 nil. 실패를 오버레이에 띄우지 않으므로 로그 외에 남는 유일한
    /// 기록이다 — 취소로 끝난 요청은 실패로 치지 않는다.
    private(set) var lastFailure: String?

    /// 돌던 루프를 취소하고 새로 시작한다. `interval`이 nil이면(설정 꺼짐) 멈추기만 한다.
    /// 첫 요청은 간격을 기다리지 않는다 — 앱 시작·설정 저장 시점에 모델을 바로 올려 둔다.
    func start(
        every interval: Duration?,
        isBusy: @escaping @MainActor () -> Bool,
        touch: @escaping @MainActor () async throws -> Void
    ) {
        stop()
        guard let interval else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                // 받아쓰기가 진행 중이면 이번 주기는 건너뛴다 — 그 다듬기 요청이 모델을 건드리므로
                // TTL은 어차피 새로 시작하고, 끼어든 요청은 다듬기 응답만 늦춘다.
                if !isBusy() {
                    let startedAt = ContinuousClock.now
                    let failure: String?
                    do {
                        try await touch()
                        failure = nil
                    } catch {
                        failure = failureDetail(of: error)
                    }
                    // 취소로 끝난 요청(설정 저장·종료)은 실패가 아니다.
                    guard !Task.isCancelled, let self else { return }
                    self.lastFailure = failure
                    NSLog("[KeepAlive] %@", Self.logLine(took: .now - startedAt, failure: failure))
                }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// 소유자(Coordinator)가 사라지면 루프도 끝난다. Task는 self를 약하게 잡아 순환이 없다.
    isolated deinit {
        loop?.cancel()
    }

    /// 요청 하나의 결과와 걸린 시간. 실패 이유는 `failureDetail(of:)`가 만든 한 줄이라 키·본문이 없다.
    nonisolated static func logLine(took: Duration, failure: String?) -> String {
        guard let failure else { return "완료 \(took.tenths)초" }
        return "실패 \(took.tenths)초: \(failure) — 다음 주기에 다시 시도"
    }
}
