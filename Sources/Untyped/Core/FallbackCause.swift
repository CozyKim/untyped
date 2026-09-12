import Foundation

/// 녹음 시작 때 보낸 예열 요청의 상태. 다듬기가 시간 초과됐을 때 콜드 스타트(모델 로드)
/// 때문이었는지 가려내는 근거다.
enum WarmUpState: Equatable, Sendable {
    case notStarted
    case running(for: Duration)
    case finished(in: Duration)
    /// 서버가 모델이 올라와 있다고 답해(`LLMHealth.loaded`) 예열 요청을 보내지 않았다.
    case skipped
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
        // 예열 요청이 아직 대기 중이면 서버는 연결을 받아 준 것이다 — 꺼진 서버는 즉시 거부해
        // 예열이 끝나 있다. 모델을 올리는 중인 서버는 연결 확인에도 답을 못 할 수 있으므로,
        // 그 확인 결과로 "꺼져 있음"이라고 단정하지 않는다.
        if case .running(let elapsed) = warmUp {
            let probe = serverReachable ? "" : " · 연결 확인도 응답 없음"
            return "콜드 스타트 — 예열 요청이 \(seconds(elapsed))초째 응답 없음(모델 로드 중)\(probe). 대기 상한 \(limit)초"
        }
        guard serverReachable else {
            return "로컬 LLM 서버에 연결할 수 없음 (\(baseURL.absoluteString)) — 꺼져 있거나 주소가 잘못됨. 대기 상한 \(limit)초"
        }
        switch warmUp {
        case .finished(let took):
            return "예열은 \(seconds(took))초에 끝났으나 다듬기 응답이 \(limit)초 안에 없음 — 로컬 LLM 과부하 또는 긴 입력"
        case .skipped:
            // "올라와 있음"은 서버 엔진의 존재 여부라 스왑으로 밀려난 상태를 못 잡는다. 예열을
            // 건너뛴 탓에 첫 응답이 스왑 복귀 비용을 치렀을 수 있음을 로그가 알려야 한다.
            return "서버가 모델이 올라와 있다고 답해 예열을 생략했으나 다듬기 응답이 \(limit)초 안에 없음 — 로컬 LLM 과부하, 스왑에서 복귀 중 또는 긴 입력"
        case .running, .notStarted:
            return "다듬기 응답이 \(limit)초 안에 없음"
        }
    }
}

private func seconds(_ duration: Duration) -> String {
    let value = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    return String(format: "%.1f", value)
}
