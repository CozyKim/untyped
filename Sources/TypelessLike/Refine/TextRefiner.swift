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

/// 다듬기가 실패하거나 늦으면 원본 전사를 그대로 돌려준다.
/// 다듬기는 품질 향상 레이어이지 필수 경로가 아니다.
func refineOrFallback(
    _ raw: String,
    using refiner: (any TextRefiner)?,
    timeout: Duration
) async -> String {
    guard let refiner else { return raw }
    return await withTaskGroup(of: String?.self) { group in
        group.addTask {
            try? await refiner.refine(raw)
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        guard let first, !first.isEmpty else { return raw }
        return first
    }
}
