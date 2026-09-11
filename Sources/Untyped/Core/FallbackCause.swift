import Foundation

/// 녹음 시작 때 보낸 예열 요청의 상태. 다듬기가 시간 초과됐을 때 콜드 스타트(모델 로드)
/// 때문이었는지 가려내는 근거다.
enum WarmUpState: Equatable, Sendable {
    case notStarted
    case running(for: Duration)
    case finished(in: Duration)
}

/// 원본 전사를 넣게 된 원인을 로그에 적을 한 줄로 만든다. 종류만으로 충분한 이유는 nil.
/// 로컬 LLM 서버가 꺼져 있는 경우와 모델을 아직 올리는 중인 경우가 사용자가 가장 자주
/// 마주치는 두 원인이라, 그 둘을 먼저 구분한다.
func fallbackCause(
    reason: FallbackReason, timeout: Duration, serverReachable: Bool,
    warmUp: WarmUpState, baseURL: URL
) -> String? {
    switch reason {
    case .noRefiner, .truncated, .emptyResult:
        return nil
    case .failed(let detail):
        return serverReachable ? detail : "\(detail) (\(baseURL.absoluteString))"
    case .timeout:
        let limit = seconds(timeout)
        guard serverReachable else {
            return "로컬 LLM 서버에 연결할 수 없음 (\(baseURL.absoluteString)) — 꺼져 있거나 주소가 잘못됨. 대기 상한 \(limit)초"
        }
        switch warmUp {
        case .running(let elapsed):
            return "콜드 스타트 — 예열 요청이 \(seconds(elapsed))초째 응답 없음(모델 로드 중). 대기 상한 \(limit)초"
        case .finished(let took):
            return "예열은 \(seconds(took))초에 끝났으나 다듬기 응답이 \(limit)초 안에 없음 — 로컬 LLM 과부하 또는 긴 입력"
        case .notStarted:
            return "다듬기 응답이 \(limit)초 안에 없음"
        }
    }
}

private func seconds(_ duration: Duration) -> String {
    let value = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    return String(format: "%.1f", value)
}
