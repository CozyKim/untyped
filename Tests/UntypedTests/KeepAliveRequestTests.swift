import Testing
import Foundation
@testable import Untyped

/// `URLSession.shared`가 keepalive.test 호스트로 보내는 요청만 가로채 정해진 상태 코드로 답한다.
/// 전역 등록이라 같은 호스트를 쓰는 이 파일의 테스트들은 순서대로 돈다(`.serialized`).
private final class StubServer: URLProtocol {
    static let host = "keepalive.test"
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var lastRequest: (method: String?, path: String?, authorization: String?, body: Data)?

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = (
            request.httpMethod, request.url?.path,
            request.value(forHTTPHeaderField: "Authorization"), Self.body(of: request)
        )
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"choices":[{"message":{"content":"."},"finish_reason":"length"}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLProtocol에 도착한 요청은 httpBody가 비어 있고 스트림으로만 본문을 준다.
    private static func body(of request: URLRequest) -> Data {
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private func makeRefiner(includeExamples: Bool = true) -> OpenAICompatibleRefiner {
    OpenAICompatibleRefiner(
        baseURL: URL(string: "http://\(StubServer.host)/v1")!, model: "m", apiKey: "sk-test",
        systemPrompt: "다듬는다.", includeExamples: includeExamples, maxTokens: 900
    )
}

@Suite(.serialized)
struct KeepAliveRequestTests {
    init() {
        URLProtocol.registerClass(StubServer.self)
        StubServer.status = 200
        StubServer.lastRequest = nil
    }

    @Test func keepAliveSendsAOneTokenChatCompletionWithTheRefinementPrefix() async throws {
        try await makeRefiner().keepAlive()

        let sent = try #require(StubServer.lastRequest)
        #expect(sent.method == "POST")
        #expect(sent.path == "/v1/chat/completions")
        #expect(sent.authorization == "Bearer sk-test")
        let body = try #require(JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        #expect(body["model"] as? String == "m")
        #expect(body["max_tokens"] as? Int == 1)
        #expect(body["temperature"] as? Double == 0)
        // 실제 다듬기와 같은 프리픽스(시스템 프롬프트 + 예시 8쌍) 뒤에 "."를 붙인다 — 모델을 건드리면서
        // 프리픽스 캐시도 함께 유지된다.
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.count == 1 + RefinementPrompt.examples.count * 2 + 1)
        #expect(messages.first == ["role": "system", "content": "다듬는다."])
        #expect(messages.last == ["role": "user", "content": "."])
    }

    @Test func keepAliveWithoutExamplesSendsOnlyPromptAndDot() async throws {
        try await makeRefiner(includeExamples: false).keepAlive()

        let sent = try #require(StubServer.lastRequest)
        let body = try #require(JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "system", "content": "다듬는다."], ["role": "user", "content": "."]])
    }

    @Test func keepAliveThrowsOnANon200Status() async {
        // 예열은 결과를 버리지만 keepalive는 실패 이유를 기록해야 하므로 상태 코드를 던진다.
        StubServer.status = 503
        await #expect(throws: RefinerError.self) {
            try await makeRefiner().keepAlive()
        }
        #expect(StubServer.lastRequest?.path == "/v1/chat/completions")
    }

    @Test func warmUpSendsTheSameRequestAndSwallowsFailure() async {
        StubServer.status = 503
        await makeRefiner().warmUp()
        let sent = StubServer.lastRequest
        #expect(sent?.method == "POST")
        #expect(sent?.path == "/v1/chat/completions")
    }
}

@Test func keepAliveThrowsWhenTheServerIsUnreachable() async {
    // 스텁 없이 실제로 닫힌 포트에 보낸다 — 연결 거부가 그대로 올라와야 루프가 이유를 기록한다.
    let refiner = OpenAICompatibleRefiner(
        baseURL: URL(string: "http://127.0.0.1:1/v1")!, model: "m", apiKey: nil,
        systemPrompt: "p", includeExamples: false, maxTokens: 1
    )
    await #expect(throws: URLError.self) {
        try await refiner.keepAlive()
    }
}

private struct PlainRefiner: TextRefiner {
    var isAvailable: Bool { get async { true } }
    func refine(_ raw: String) async throws -> String { raw }
}

@Test func refinersWithoutKeepAliveDoNothing() async throws {
    // 프로토콜 기본값 — 서버를 모르는 구현체는 아무 요청도 보내지 않고 실패도 하지 않는다.
    try await PlainRefiner().keepAlive()
}
