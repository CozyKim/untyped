import Testing
import Foundation
@testable import Untyped

// MARK: - URL 구성

@Test func healthURLDropsTheV1PathAndKeepsTheOrigin() {
    // oMLX는 /v1/health가 아니라 origin의 /health에 답한다.
    let url = LLMHealth.url(for: URL(string: "http://127.0.0.1:8081/v1")!)
    #expect(url == URL(string: "http://127.0.0.1:8081/health"))
}

@Test func healthURLDropsDeeperPathsTrailingSlashesQueryAndUserInfo() {
    let url = LLMHealth.url(for: URL(string: "https://user:pw@llm.local:8443/api/v1/?x=1#frag")!)
    #expect(url == URL(string: "https://llm.local:8443/health"))
}

@Test func healthURLWithoutHostIsNil() {
    #expect(LLMHealth.url(for: URL(string: "file:///tmp/v1")!) == nil)
}

// MARK: - 응답 해석

private func body(_ json: String) -> Data { Data(json.utf8) }

@Test func healthyServerWithLoadedModelIsLoaded() {
    let omlx = """
    {"status":"healthy","default_model":null,"engine_pool":{"model_count":1,"loaded_count":1,\
    "final_ceiling":10339489672,"current_model_memory":6159910215},"mcp":null}
    """
    #expect(LLMHealth.parse(statusCode: 200, body: body(omlx)) == .loaded)
}

@Test func healthyServerWithNoLoadedModelIsNotLoaded() {
    let omlx = #"{"status":"healthy","default_model":null,"engine_pool":{"model_count":1,"loaded_count":0}}"#
    #expect(LLMHealth.parse(statusCode: 200, body: body(omlx)) == .notLoaded)
}

@Test func loadingServerWithNothingLoadedIsNotLoaded() {
    // oMLX는 고정(pinned) 모델을 올리는 동안 503과 status: loading을 돌려준다.
    let omlx = #"{"status":"loading","default_model":null,"engine_pool":{"model_count":1,"loaded_count":0}}"#
    #expect(LLMHealth.parse(statusCode: 503, body: body(omlx)) == .notLoaded)
}

@Test func loadingServerWithSomethingLoadedIsUnknown() {
    // 여러 모델 중 일부만 올라온 채 아직 로딩 중이면 설정한 모델이 그 안에 있는지 알 수 없다.
    let omlx = #"{"status":"loading","engine_pool":{"model_count":2,"loaded_count":1}}"#
    #expect(LLMHealth.parse(statusCode: 503, body: body(omlx)) == .unknown)
}

@Test func notFoundIsUnknown() {
    // 일반 OpenAI 호환 서버(Ollama, LM Studio…)에는 /health가 없다. FastAPI 계열은 JSON 404를 준다.
    #expect(LLMHealth.parse(statusCode: 404, body: body(#"{"detail":"Not Found"}"#)) == .unknown)
    #expect(LLMHealth.parse(statusCode: 404, body: body("Not Found")) == .unknown)
}

@Test(arguments: [
    "",
    "<html><body>ok</body></html>",
    "{",
    "{}",
    "[]",
    #"{"status":"healthy"}"#,
    #"{"status":"healthy","engine_pool":null}"#,
    #"{"status":"healthy","engine_pool":{"model_count":1}}"#,
    #"{"status":"healthy","engine_pool":{"loaded_count":"1"}}"#,
    #"{"status":"healthy","engine_pool":"1"}"#,
])
func malformedOrUninformativeBodiesAreUnknown(json: String) {
    #expect(LLMHealth.parse(statusCode: 200, body: body(json)) == .unknown)
}

@Test func loadedCountOnNon200IsNeverTrustedAsLoaded() {
    let omlx = #"{"status":"healthy","engine_pool":{"loaded_count":1}}"#
    #expect(LLMHealth.parse(statusCode: 500, body: body(omlx)) == .unknown)
}

// MARK: - 예열 결정

@Test func onlyALoadedModelSkipsWarmUp() {
    // 확인이 안 되면(서버에 /health가 없음, 응답 이상, 시간 초과) 지금까지처럼 예열한다.
    #expect(LLMHealth.loaded.needsWarmUp == false)
    #expect(LLMHealth.notLoaded.needsWarmUp == true)
    #expect(LLMHealth.unknown.needsWarmUp == true)
}

private struct PlainRefiner: TextRefiner {
    var isAvailable: Bool { get async { true } }
    func refine(_ raw: String) async throws -> String { raw }
}

@Test func refinersWithoutAHealthEndpointReportUnknownAndKeepWarmingUp() async {
    // 프로토콜 기본값 — /health를 모르는 구현체는 예열 동작이 그대로다.
    let health = await PlainRefiner().health
    #expect(health == .unknown)
    #expect(health.needsWarmUp)
}
