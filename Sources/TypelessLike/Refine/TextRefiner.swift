import Foundation

/// 입력도 출력도 순수 문자열이다. 오디오, 로케일, 삽입 대상 앱을 모른다.
protocol TextRefiner: Sendable {
    var isAvailable: Bool { get async }
    func refine(_ raw: String) async throws -> String
}

/// 녹음 길이에 비례하는 타임아웃. 고정값을 쓰면 긴 발화가 항상 폴백된다.
func refineTimeout(for recorded: Duration) -> Duration {
    .seconds(4) + recorded * 0.4
}

/// 원본 전사를 넣게 된 이유. 오버레이 알림과 로그가 같은 문구를 쓴다.
enum FallbackReason: Equatable, Sendable {
    case noRefiner
    case timeout
    case truncated
    case emptyResult
    case failed

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
        return .fallback(raw, .failed)
    case .finished(.success(let text)):
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .fallback(raw, .emptyResult) }
        return .refined(trimmed)
    }
}
