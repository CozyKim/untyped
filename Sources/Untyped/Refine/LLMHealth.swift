import Foundation

/// 다듬기 서버가 모델을 올려 두었는지. 키를 누를 때 예열 요청을 보낼지 정하는 근거다.
///
/// oMLX는 base_url의 origin에 붙은 `/health`(`/v1/health`가 아님)에
/// `{"status":"healthy","engine_pool":{"model_count":1,"loaded_count":1,…}}`를 돌려주고,
/// 고정 모델을 올리는 동안은 503과 `status: "loading"`을 준다. 일반 OpenAI 호환 서버
/// (Ollama, LM Studio…)에는 이 경로가 없다. 그래서 이 확인은 최선 노력이다 — 판단할 수 없으면
/// `unknown`이고, 호출자는 그때 지금까지처럼 예열한다. 받아쓰기를 막는 조건으로는 쓰지 않는다.
///
/// 응답에는 어느 모델이 올라와 있는지가 없다(`default_model`은 null, `/v1/models`의 `loaded`도
/// null). `loaded_count`가 1 이상이면 설정한 모델이 올라와 있다고 본다 — 여러 모델을 두고 다른
/// 모델만 올라와 있으면 예열을 건너뛰어 콜드 스타트를 겪는다. 또 "올라와 있음"은 서버 엔진의 존재
/// 여부라, macOS가 모델 메모리를 스왑으로 밀어낸 상태는 잡지 못한다.
enum LLMHealth: Equatable, Sendable {
    /// 서버가 정상(HTTP 200)이고 모델이 하나 이상 올라와 있다.
    case loaded
    /// 서버는 응답했지만 올라온 모델이 없다(`loaded_count == 0`). 예열이 곧 로드다.
    case notLoaded
    /// `/health`가 없거나(404), 연결·시간 초과, 응답 형식이 다르거나, 로딩 중이라 확신할 수 없다.
    case unknown

    /// 모델이 올라와 있다고 확인된 경우에만 예열을 건너뛴다.
    var needsWarmUp: Bool { self != .loaded }

    /// base_url의 스킴·호스트·포트만 취해 `/health`를 붙인다. 경로(`/v1`)·쿼리·userinfo는
    /// 버린다. 호스트가 없는 URL이면 nil.
    static func url(for baseURL: URL) -> URL? {
        // file:// 같은 URL은 host가 nil이 아니라 빈 문자열이다.
        guard let base = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let host = base.host, !host.isEmpty else { return nil }
        var origin = URLComponents()
        origin.scheme = base.scheme
        origin.host = host
        origin.port = base.port
        origin.path = "/health"
        return origin.url
    }

    private struct Response: Decodable {
        struct EnginePool: Decodable { let loaded_count: Int? }
        let engine_pool: EnginePool?
    }

    /// 상태 코드와 본문만 받는다 — 네트워크를 모르므로 바이트로 검증한다.
    /// `loaded`는 HTTP 200일 때만이다. 503(로딩 중)에 `loaded_count`가 1이면 다른 모델이 올라온
    /// 채 설정한 모델을 올리는 중일 수 있어 `unknown`으로 둔다.
    static func parse(statusCode: Int, body: Data) -> LLMHealth {
        guard let decoded = try? JSONDecoder().decode(Response.self, from: body),
              let loadedCount = decoded.engine_pool?.loaded_count else { return .unknown }
        if loadedCount == 0 { return .notLoaded }
        return statusCode == 200 ? .loaded : .unknown
    }
}
