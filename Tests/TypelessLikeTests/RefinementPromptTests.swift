import Testing
@testable import TypelessLike

@Test func systemPromptCarriesFourRulesAndGlossary() {
    let messages = RefinementPrompt.messages(for: "테스트")
    let system = messages.first
    #expect(system?.role == "system")
    let text = system?.content ?? ""
    for marker in ["1.", "2.", "3.", "4."] {
        #expect(text.contains(marker))
    }
    #expect(!text.contains("5."))  // 규칙을 넷보다 늘리면 성능이 떨어진다
    #expect(text.contains("langchain"))
    #expect(text.contains("typeless"))
    #expect(text.contains("사전에 없는 말은 손대지 않는다"))
}

@Test func eightFewShotPairsPrecedeTheInput() {
    let messages = RefinementPrompt.messages(for: "원문")
    // system 1 + (user, assistant) * 8 + user 1 = 18
    #expect(messages.count == 18)
    #expect(messages.last?.role == "user")
    #expect(messages.last?.content == "원문")
    let shots = messages.dropFirst().dropLast()
    #expect(shots.count == 16)
    for (index, message) in shots.enumerated() {
        #expect(message.role == (index % 2 == 0 ? "user" : "assistant"))
    }
}

@Test func nonceDiffersOnEveryCall() {
    let a = RefinementPrompt.messages(for: "같은 입력").first?.content ?? ""
    let b = RefinementPrompt.messages(for: "같은 입력").first?.content ?? ""
    #expect(a != b)
}
