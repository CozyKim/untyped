import Foundation

/// 입력도 출력도 순수 문자열이다. 오디오, 로케일, 삽입 대상 앱을 모른다.
protocol TextRefiner: Sendable {
    var isAvailable: Bool { get async }
    func refine(_ raw: String) async throws -> String
    /// 서버가 모델을 메모리에 올리고 프리픽스를 캐시하도록 미리 건드린다. 결과는 버린다.
    func warmUp() async
    /// 예열과 같은 최소 요청이지만 실패를 던진다 — 주기적으로 모델을 건드려 유휴 TTL을 새로 시작하는
    /// keepalive가 실패 이유를 기록할 수 있어야 한다.
    func keepAlive() async throws
    /// 서버가 모델을 올려 두었는지. `loaded`면 호출자가 예열을 건너뛴다. 확인할 방법이 없는
    /// 서버는 `unknown`이라 예열 동작이 그대로다.
    var health: LLMHealth { get async }
}

extension TextRefiner {
    func warmUp() async {}
    func keepAlive() async throws {}
    var health: LLMHealth { get async { .unknown } }
}

/// 녹음 오디오(WAV 바이트)를 한 요청으로 다듬은 문장으로 만든다 — 전사와 다듬기를 오디오
/// 입력을 받는 LLM이 한 번에 한다. 마이크도 포맷 변환도 모른다 — 완성된 파일 바이트만 받는다.
protocol AudioRefiner: Sendable {
    func refine(wav: Data) async throws -> String
}

/// 녹음 길이에 비례하는 타임아웃. 고정값만 쓰면 긴 발화가 항상 폴백된다.
/// 기본값(base)은 모델 로드·프리필 같은 고정 비용 몫이라 녹음 길이와 무관하게
/// 사용자가 조절한다 — 메모리가 부족해 모델이 스왑에서 돌아오는 기기에서는 이 몫이 커진다.
func refineTimeout(for recorded: Duration, base: Duration) -> Duration {
    base + recorded * 0.4
}

/// 오디오를 한 요청으로 다듬을 때의 타임아웃. 같은 기본값을 쓰되 녹음 길이를 40%가 아니라
/// 전부 더한다 — 오디오 토큰을 프리필하고 발화를 듣고 써내는 일이 한 요청에 들어가고, 시간이
/// 초과되면 넣을 원본이 없어 받아쓰기 한 번이 통째로 사라지므로 텍스트 다듬기보다 넉넉히 기다린다.
func audioRefineTimeout(for recorded: Duration, base: Duration) -> Duration {
    base + recorded
}

/// 원본 전사를 넣게 된 이유. 오버레이 알림과 로그가 같은 문구를 쓴다.
/// 오디오를 한 요청으로 다듬다 실패한 이유로도 쓴다 — 같은 서버에 같은 방식으로 묻기 때문에
/// 실패의 종류가 같다. 다만 그때는 넣을 원본이 없어 "원본 삽입" 대신 "삽입 안 함"이 된다.
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
    /// 설정상 다듬기를 거치지 않은 전사. 폴백이 아니라 의도한 결과라 알림·Return 게이트에 걸리지 않는다.
    case transcribed(String)

    /// 실제로 삽입할 텍스트.
    var text: String {
        switch self {
        case .refined(let text), .fallback(let text, _), .transcribed(let text): text
        }
    }
}

/// LLM에 텍스트 하나를 요구한 결과. 시간 초과·요청 실패·빈 결과를 한 이유 체계로 묶는다.
enum LLMTextResult: Equatable, Sendable {
    case text(String)
    case failed(FallbackReason)
}

/// LLM 요청을 타임아웃과 경쟁시킨다. 텍스트 다듬기와 오디오 다듬기가 같은 정책을 쓴다 —
/// 늦으면 취소하고, 오류는 로그용 원인으로 바꾸고, 공백뿐인 결과는 실패로 친다.
func requestLLMText(
    timeout: Duration,
    _ request: @escaping @Sendable () async throws -> String
) async -> LLMTextResult {
    enum Race: Sendable {
        case finished(Result<String, any Error>)
        case timedOut
    }
    let race = await withTaskGroup(of: Race.self) { group in
        group.addTask {
            do { return .finished(.success(try await request())) }
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
        return .failed(.timeout)
    case .finished(.failure(let error)):
        if let refinerError = error as? RefinerError, case .truncated = refinerError {
            return .failed(.truncated)
        }
        return .failed(.failed(detail: failureDetail(of: error)))
    case .finished(.success(let text)):
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failed(.emptyResult) }
        return .text(trimmed)
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
    switch await requestLLMText(timeout: timeout, { try await refiner.refine(raw) }) {
    case .text(let text): return .refined(text)
    case .failed(let reason): return .fallback(raw, reason)
    }
}
