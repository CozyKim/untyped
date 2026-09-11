import Testing
@testable import Untyped

@Test func systemPromptCarriesFourRulesAndGlossary() {
    let messages = RefinementPrompt.messages(
        for: "테스트", systemPrompt: RefinementPrompt.defaultSystemPrompt, includeExamples: true
    )
    let system = messages.first
    #expect(system?.role == "system")
    let text = system?.content ?? ""

    // 1-4 규칙이 line-leading 번호로 정확히 존재하는지 확인한다.
    // 이 방식은 "5)", 전각 문자, rule 4에 반영되는 경우, 중복된 규칙 등
    // 다양한 회귀를 감지한다.
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    var ruleNumbers = [String]()
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("1.") || trimmed.hasPrefix("1)") {
            ruleNumbers.append("1")
        } else if trimmed.hasPrefix("2.") || trimmed.hasPrefix("2)") {
            ruleNumbers.append("2")
        } else if trimmed.hasPrefix("3.") || trimmed.hasPrefix("3)") {
            ruleNumbers.append("3")
        } else if trimmed.hasPrefix("4.") || trimmed.hasPrefix("4)") {
            ruleNumbers.append("4")
        } else if trimmed.hasPrefix("5.") || trimmed.hasPrefix("5)") ||
                  trimmed.hasPrefix("6.") || trimmed.hasPrefix("6)") ||
                  trimmed.hasPrefix("7.") || trimmed.hasPrefix("7)") ||
                  trimmed.hasPrefix("8.") || trimmed.hasPrefix("8)") ||
                  trimmed.hasPrefix("9.") || trimmed.hasPrefix("9)") {
            // 규칙이 4개를 초과하면 별도로 기록해서 테스트 실패를 유도
            ruleNumbers.append("?")
        }
    }

    // 규칙이 정확히 1, 2, 3, 4 순서로 한 번씩만 나타나는지 확인
    #expect(ruleNumbers == ["1", "2", "3", "4"])

    // Semantic dilution (rule 4에 반영되거나 번호 없이 추가됨)은
    // 단위 테스트로는 감지할 수 없으며 회귀 스위트에서 다룬다.

    #expect(text.contains("langchain"))
    #expect(text.contains("typeless"))
    #expect(text.contains("사전에 없는 말은 손대지 않는다"))
}

@Test func eightFewShotPairsPrecedeTheInput() {
    let messages = RefinementPrompt.messages(
        for: "원문", systemPrompt: RefinementPrompt.defaultSystemPrompt, includeExamples: true
    )
    // system 1 + (user, assistant) * 8 + user 1 = 18
    #expect(messages.count == 18)
    #expect(messages.last?.role == "user")
    #expect(messages.last?.content == "원문")
    let shots = messages.dropFirst().dropLast()
    #expect(shots.count == 16)
    for (index, message) in shots.enumerated() {
        #expect(message.role == (index % 2 == 0 ? "user" : "assistant"))
    }

    // Few-shot 내용과 순서가 보존되었는지 확인한다.
    // 각 쌍의 고유한 anchor를 검사해 swap이나 duplication을 감지한다.
    #expect(messages[1].content.contains("어 내일"))  // pair 1 user
    #expect(messages[2].content.contains("오늘 저녁에"))  // pair 1 assistant
    #expect(messages[3].content.contains("그 뭐지 그 회의실"))  // pair 2 user
    #expect(messages[4].content.contains("회의실을 3층"))  // pair 2 assistant
    #expect(messages[5].content.contains("보고서는 김 대리가"))  // pair 3 user
    #expect(messages[6].content.contains("발표도 김 대리가"))  // pair 3 assistant
    #expect(messages[7].content.contains("제플로이는"))  // pair 4 user
    #expect(messages[8].content.contains("log도"))  // pair 4 assistant (glossary demonstration)
    #expect(messages[9].content.contains("이번 분기 목표는"))  // pair 5 user
    #expect(messages[10].content.contains("이탈률을"))  // pair 5 assistant
    #expect(messages[11].content.contains("엑셀로 정리하려고"))  // pair 6 user
    #expect(messages[12].content.contains("대시보드로"))  // pair 6 assistant
    #expect(messages[13].content.contains("배포 자동화를"))  // pair 7 user
    #expect(messages[14].content.contains("test coverage부터"))  // pair 7 assistant
    #expect(messages[15].content.contains("그 다 다이얼"))  // pair 8 user
    #expect(messages[16].content.contains("다이어그램으로"))  // pair 8 assistant
}

@Test func systemMessageIsExactlyTheGivenPromptEveryTime() {
    // 서버의 프리픽스 캐시가 적중하려면 시스템 메시지가 호출마다 바이트 단위로 같아야 한다.
    // 텍스트만 보내는 요청에서는 사용자 메시지가 프리픽스 뒤에 붙어 캐시가 요청을
    // 정확히 구분하므로, 캐시를 깨는 난수를 붙일 이유가 없다 — 붙이면 매 요청이 느려질 뿐이다.
    let first = RefinementPrompt.messages(for: "a", systemPrompt: "규칙", includeExamples: false)
    let second = RefinementPrompt.messages(for: "b", systemPrompt: "규칙", includeExamples: false)
    #expect(first.first?.content == "규칙")
    #expect(second.first?.content == "규칙")
}

@Test func customSystemPromptReplacesTheDefault() {
    let messages = RefinementPrompt.messages(
        for: "원문", systemPrompt: "받아쓰기 원문을 영어로 번역한다.", includeExamples: true
    )
    #expect(messages.first?.role == "system")
    #expect(messages.first?.content == "받아쓰기 원문을 영어로 번역한다.")
    #expect(messages.count == 18)
    #expect(messages.last?.content == "원문")
}

@Test func examplesCanBeOmitted() {
    let messages = RefinementPrompt.messages(
        for: "원문", systemPrompt: RefinementPrompt.defaultSystemPrompt, includeExamples: false
    )
    #expect(messages.count == 2)
    #expect(messages[0].role == "system")
    #expect(messages[1].role == "user")
    #expect(messages[1].content == "원문")
}

@Test func defaultSystemPromptEndsWithOutputInstructionAndNoTag() {
    let prompt = RefinementPrompt.defaultSystemPrompt
    #expect(prompt.hasSuffix("다듬은 문장만 출력한다."))
    #expect(!prompt.contains("["))
}

@Test func examplesAreExposedInTheOrderTheyAreSent() {
    // 설정 창이 읽기 전용으로 보여주는 목록은 실제로 보내는 예시와 같아야 한다.
    let messages = RefinementPrompt.messages(
        for: "원문", systemPrompt: RefinementPrompt.defaultSystemPrompt, includeExamples: true
    )
    #expect(RefinementPrompt.examples.count == 8)
    for (index, example) in RefinementPrompt.examples.enumerated() {
        #expect(messages[1 + index * 2].content == example.input)
        #expect(messages[2 + index * 2].content == example.output)
    }
}
