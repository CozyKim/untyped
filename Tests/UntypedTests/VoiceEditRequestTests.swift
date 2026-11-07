import Foundation
import Testing
@testable import Untyped

private final class VoiceEditServer: URLProtocol {
    nonisolated(unsafe) static var content = ""
    nonisolated(unsafe) static var finishReason = "stop"
    nonisolated(unsafe) static var sentBody = Data()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "voice-edit.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        if let data = request.httpBody {
            Self.sentBody = data
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            Self.sentBody = data
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let body: [String: Any] = ["choices": [[
            "message": ["content": Self.content], "finish_reason": Self.finishReason,
        ]]]
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized)
struct VoiceEditRequestTests {
    init() {
        URLProtocol.registerClass(VoiceEditServer.self)
        VoiceEditServer.finishReason = "stop"
        VoiceEditServer.content = ""
        VoiceEditServer.sentBody = Data()
    }

    private var client: OpenAICompatibleRefiner {
        OpenAICompatibleRefiner(
            baseURL: URL(string: "http://voice-edit.test/v1")!, model: "test", apiKey: nil,
            systemPrompt: "translate everything", includeExamples: true, maxTokens: 900
        )
    }

    @Test func requestUsesDedicatedEditingContextAndPreservesNewlines() async throws {
        VoiceEditServer.content = #"{"edits":[{"old":"내일 회의","new":"오늘 회의"}]}"#
        let edited = try await client.edit("\n내일 회의\n다른 문장\n", instruction: "내일을 오늘로 바꿔")
        let plan = try VoiceEditPlan.decode(edited, original: "\n내일 회의\n다른 문장\n")
        #expect(plan.result == "\n오늘 회의\n다른 문장\n")
        #expect(plan.patches[0].range == NSRange(location: 1, length: 2))
        let body = try #require(JSONSerialization.jsonObject(with: VoiceEditServer.sentBody) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.count == 2)
        #expect(messages[0]["content"]?.contains("translate everything") == false)
        let data = try #require(messages[1]["content"]?.data(using: .utf8))
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(payload["text"] == "\n내일 회의\n다른 문장\n")
        #expect(payload["instruction"] == "내일을 오늘로 바꿔")
    }

    @Test func onlyAnchoredDeletionCanDeleteText() async throws {
        VoiceEditServer.content = #"{"edits":[{"old":"원문","new":""}]}"#
        let json = try await client.edit("원문", instruction: "모두 삭제")
        #expect(try VoiceEditPlan.decode(json, original: "원문").result == "")
        for invalid in ["", "수정문", "{}", #"{"text":"전체 재작성"}"#, #"{"edits":null}"#] {
            VoiceEditServer.content = invalid
            await #expect(throws: DecodingError.self) { try await client.edit("원문", instruction: "바꿔") }
        }
    }

    @Test func truncatedEditsAreRejected() async {
        VoiceEditServer.content = #"{"edits":[{"old":"원문","new":"일부만 수정됨"}]}"#
        VoiceEditServer.finishReason = "length"
        await #expect(throws: RefinerError.self) { try await client.edit("원문", instruction: "바꿔") }
    }

    @Test func audioCommandTranscriptionOmitsCustomRefinementRules() async throws {
        VoiceEditServer.content = "수정, 내일을 오늘로 바꿔"
        #expect(try await client.transcribe(wav: Data([1, 2])) == "수정, 내일을 오늘로 바꿔")
        let body = try #require(JSONSerialization.jsonObject(with: VoiceEditServer.sentBody) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect((messages[0]["content"] as? String)?.contains("translate everything") == false)
        let parts = try #require(messages[1]["content"] as? [[String: Any]])
        let audio = try #require(parts[0]["input_audio"] as? [String: String])
        #expect(audio["data"] == "AQI=")
        #expect(audio["format"] == "wav")
    }
}
