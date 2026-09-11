import Foundation

/// 입력도 출력도 순수 문자열이다. 오디오, 로케일, 삽입 대상 앱을 모른다.
protocol TextRefiner: Sendable {
    var isAvailable: Bool { get async }
    func refine(_ raw: String) async throws -> String
    /// 서버가 모델을 메모리에 올리고 프리픽스를 캐시하도록 미리 건드린다. 결과는 버린다.
    func warmUp() async
}

extension TextRefiner {
    func warmUp() async {}
}

/// 녹음 길이에 비례하는 타임아웃. 고정값만 쓰면 긴 발화가 항상 폴백된다.
/// 기본값(base)은 모델 로드·프리필 같은 고정 비용 몫이라 녹음 길이와 무관하게
/// 사용자가 조절한다 — 메모리가 부족해 모델이 스왑에서 돌아오는 기기에서는 이 몫이 커진다.
func refineTimeout(for recorded: Duration, base: Duration) -> Duration {
    base + recorded * 0.4
}

/// 원본 전사를 넣게 된 이유. 오버레이 알림과 로그가 같은 문구를 쓴다.
enum FallbackReason: Equatable, Sendable {
    case noRefiner
    case timeout
    case truncated
    case emptyResult
    /// 요청 자체가 실패했다. detail은 로그용이다 — 연결 거부인지, HTTP 상태인지, 응답 형식인지를
    /// 남겨야 "서버 오류"가 서버가 꺼진 것인지 응답이 이상한 것인지 나중에 가릴 수 있다.
    case failed(detail: String)

    var label: String {
        switch self {
        case .noRefiner: "다듬기 없음"
        case .timeout: "다듬기 시간 초과"
        case .truncated: "최대 토큰 초과"
        case .emptyResult: "다듬기 결과 없음"
        case .failed: "다듬기 서버 오류"
        }
    }
}

/// 요청 실패를 로그에 남길 한 줄로 바꾼다. 로컬 LLM 서버가 꺼져 있는 경우(연결 거부)를 가장
/// 먼저 알아볼 수 있어야 한다.
func failureDetail(of error: any Error) -> String {
    if let urlError = error as? URLError {
        switch urlError.code {
        case .cannotConnectToHost:
            return "연결 거부 — 로컬 LLM 서버가 실행 중이 아님"
        case .networkConnectionLost:
            // 예열 때 열린 keep-alive 연결을 서버가 유휴 종료한 뒤 다듬기 요청이 그 연결을
            // 재사용하면 이 오류가 난다. 서버가 꺼진 것과는 다르다.
            return "연결 끊김 — 요청 도중 서버가 연결을 닫음(크래시·재시작 또는 keep-alive 만료)"
        case .timedOut:
            return "요청 시간 초과 (URLSession)"
        default:
            return "네트워크 오류 — \(urlError.localizedDescription)"
        }
    }
    if let refinerError = error as? RefinerError {
        switch refinerError {
        case .badStatus(let code): return "HTTP \(code)"
        case .emptyResponse: return "응답에 choices가 없음"
        case .truncated: return "최대 토큰 초과"
        }
    }
    if error is DecodingError {
        return "응답 형식 오류 — JSON 해석 실패"
    }
    return String(describing: error)
}

enum RefineOutcome: Equatable, Sendable {
    case refined(String)
    case fallback(String, FallbackReason)

    /// 실제로 삽입할 텍스트.
    var text: String {
        switch self {
        case .refined(let text), .fallback(let text, _): text
        }
    }
}

/// 다듬기가 실패하거나 늦으면 원본 전사를 그대로 돌려준다.
/// 다듬기는 품질 향상 레이어이지 필수 경로가 아니다. 어느 쪽이었는지를 함께
/// 돌려주어 호출자가 사용자에게 알리고 기록할 수 있게 한다.
func refineOrFallback(
    _ raw: String,
    using refiner: (any TextRefiner)?,
    timeout: Duration
) async -> RefineOutcome {
    guard let refiner else { return .fallback(raw, .noRefiner) }

    enum Race: Sendable {
        case finished(Result<String, any Error>)
        case timedOut
    }
    let race = await withTaskGroup(of: Race.self) { group in
        group.addTask {
            do { return .finished(.success(try await refiner.refine(raw))) }
            catch { return .finished(.failure(error)) }
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return .timedOut
        }
        // 두 자식 중 하나는 반드시 값을 내므로 nil이 아니다.
        let first = await group.next() ?? .timedOut
        group.cancelAll()
        return first
    }

    switch race {
    case .timedOut:
        return .fallback(raw, .timeout)
    case .finished(.failure(let error)):
        if let refinerError = error as? RefinerError, case .truncated = refinerError {
            return .fallback(raw, .truncated)
        }
        return .fallback(raw, .failed(detail: failureDetail(of: error)))
    case .finished(.success(let text)):
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .fallback(raw, .emptyResult) }
        return .refined(trimmed)
    }
}
