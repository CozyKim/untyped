import Testing
@testable import TypelessLike

@Test func systemPromptCarriesFourRulesAndGlossary() {
    let messages = RefinementPrompt.messages(for: "테스트")
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

@Test func nonceEnsuresUniquenessAcrossManyRequests() {
    // 저 entropy nonce는 1000 샘플 중 일부에서만 다른 값을 가질 수 있다.
    // 이 테스트는 완벽한 uniqueness를 확인하여 그런 회귀를 감지한다.
    // 현재 구현(32비트, 8개 hex)은 flake 없이 통과한다.
    var nonces = Set<String>()
    for _ in 0..<1000 {
        let systemPrompt = RefinementPrompt.messages(for: "테스트").first?.content ?? ""
        nonces.insert(systemPrompt)
    }
    #expect(nonces.count == 1000)
}
