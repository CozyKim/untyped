import Testing
import Foundation
@testable import Untyped

@Test func audioRequestKeepsTextPrefixAndEndsWithAudioPart() throws {
    // 오디오 경로는 텍스트 경로와 같은 시스템 프롬프트·예시 뒤에 원문 대신 오디오를 붙인다.
    // 마지막 사용자 메시지는 OpenAI input_audio 형식이어야 한다:
    // {"type":"input_audio","input_audio":{"data":"<base64>","format":"wav"}}
    let wav = Data([0x52, 0x49, 0x46, 0x46])
    let messages = RefinementPrompt.audioMessages(
        wav: wav, systemPrompt: RefinementPrompt.defaultSystemPrompt, includeExamples: true
    )
    let data = try JSONEncoder().encode(messages)
    let array = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

    // system 1 + (user, assistant) * 8 + user(audio) 1 = 18 — 텍스트 경로와 같은 수
    #expect(array.count == 18)
    #expect(array[0]["role"] as? String == "system")
    // 프리픽스는 문자열 content — 파트 배열을 시스템 역할에서 거부하는 서버가 있고, 텍스트
    // 경로와 바이트 단위로 같아야 프리픽스 캐시를 공유한다.
    #expect(array[0]["content"] as? String == RefinementPrompt.defaultSystemPrompt)
    #expect(array[1]["content"] as? String == RefinementPrompt.examples[0].input)
    #expect(array[2]["content"] as? String == RefinementPrompt.examples[0].output)

    let last = array[17]
    #expect(last["role"] as? String == "user")
    let parts = try #require(last["content"] as? [[String: Any]])
    #expect(parts.count == 2)
    #expect(parts[0]["type"] as? String == "input_audio")
    let audio = try #require(parts[0]["input_audio"] as? [String: Any])
    #expect(audio["data"] as? String == wav.base64EncodedString())
    #expect(audio["format"] as? String == "wav")
    // data URI 접두사를 붙이지 않는다.
    #expect((audio["data"] as? String)?.hasPrefix("data:") == false)
    #expect(parts[1]["type"] as? String == "text")
    #expect(parts[1]["text"] as? String == RefinementPrompt.audioInstruction)
}

@Test func audioRequestHonorsCustomPromptAndExampleFlag() {
    let messages = RefinementPrompt.audioMessages(
        wav: Data([1]), systemPrompt: "받아쓰기 원문을 영어로 번역한다.", includeExamples: false
    )
    #expect(messages.count == 2)
    #expect(messages[0] == MultipartChatMessage(role: "system", content: .text("받아쓰기 원문을 영어로 번역한다.")))
    #expect(messages[1].role == "user")
}

@Test func audioPrefixMatchesTextPathPrefix() {
    // 두 경로가 같은 프리픽스를 보내야 서버 캐시가 한 번만 채워진다.
    let text = RefinementPrompt.messages(
        for: "원문", systemPrompt: RefinementPrompt.defaultSystemPrompt, includeExamples: true
    ).dropLast()
    let audio = RefinementPrompt.audioMessages(
        wav: Data([1]), systemPrompt: RefinementPrompt.defaultSystemPrompt, includeExamples: true
    ).dropLast()
    #expect(text.count == audio.count)
    for (a, b) in zip(text, audio) {
        #expect(a.role == b.role)
        #expect(b.content == .text(a.content))
    }
}

@Test func textPartEncodesAsOpenAITextPart() throws {
    let message = MultipartChatMessage(role: "user", content: .parts([.text("안녕")]))
    let data = try JSONEncoder().encode(message)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let parts = try #require(object["content"] as? [[String: String]])
    #expect(parts == [["type": "text", "text": "안녕"]])
}
