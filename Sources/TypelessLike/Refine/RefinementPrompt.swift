import Foundation

struct ChatMessage: Codable, Sendable {
    let role: String
    let content: String
}

enum RefinementPrompt {
    /// 음차된 용어를 되돌릴 후보 집합. 음차와 영문의 대응을 주지 않는다.
    /// 대응을 병기한 판은 점수가 같으면서 길이만 늘어 희석을 키운다.
    /// 항목을 늘릴 때는 회귀 스위트로 확인한다.
    static let glossary = """
    PR, approve, review, merge, main, branch, commit, rebase, push, pull, revert, \
    deploy, staging, production, rollback, endpoint, timeout, retry, logic, log, debug, error, \
    authentication, authorization, token, refactoring, dependency, injection, container, restart, \
    cache, migration, schema, queue, worker, latency, throughput, build, release, hotfix, \
    agent, subagent, orchestrator, prompt, context, embedding, langchain, typeless, diagram, \
    TTS, STT, LLM, API, SDK, CLI, UI, repo, config
    """

    /// 규칙은 넷을 넘기지 않는다. 같은 내용을 여섯으로 나눠 쓴 판이
    /// 회귀 스위트에서 더 낮은 점수를 냈다. 규칙이 많아지면 각각의 영향력이 희석된다.
    private static func rules(nonce: String) -> String {
        """
        받아쓰기 원문을 다듬는다.
        1. 정정 표시어('아니', '아니다', '그게 아니라')가 나오면 표시어와 그 앞의 말을 전부 지우고 \
        뒤의 말만 남긴다. 앞뒤 주제가 달라도 마찬가지다. 문장이 길고 절이 여러 개여도 똑같이 적용한다.
        2. 군말(어, 음, 그, 그 뭐지)과 더듬어 반복한 말을 지운다.
        3. 아래 사전의 단어가 음차돼 있으면 영문으로 되돌린다. 사전에 없는 말은 손대지 않는다.
          사전: \(glossary)
        4. 문장부호와 띄어쓰기를 정리한다. 그 외의 내용은 바꾸지 않는다.
        다듬은 문장만 출력한다. [\(nonce)]
        """
    }

    private static let fewShots: [(String, String)] = [
        // 1. 짧은 문장의 정정
        ("어 내일 아침에 자료를 보내드릴게요 아니 오늘 저녁에 자료를 보내드릴게요",
         "오늘 저녁에 자료를 보내드릴게요."),
        // 2. 필러만 있는 경우
        ("그 뭐지 그 회의실을 음 3층으로 잡아줘",
         "회의실을 3층으로 잡아줘."),
        // 3. 문장 일부만 정정되고 나머지는 보존
        ("보고서는 김 대리가 쓰고 발표는 이 과장이 하기로 했는데 아니 발표도 김 대리가 합니다",
         "보고서는 김 대리가 쓰고 발표도 김 대리가 합니다."),
        // 4. 음차된 개발 용어를 영문으로
        ("제플로이는 스테이징에 먼저 하고 프로덕션은 그 다음에 하고 로그도 체크해주세요",
         "deploy는 staging에 먼저 하고 production은 그 다음에 하고 log도 확인해주세요."),
        // 5. 영어 용어가 없는 순수 한국어 - 손대지 않는다
        ("이번 분기 목표는 신규 사용자 확보하고 이탈률을 낮추는 겁니다",
         "이번 분기 목표는 신규 사용자 확보하고 이탈률을 낮추는 겁니다."),
        // 6. 주제가 전환되는 정정 - 앞 절을 통째로 버린다
        ("엑셀로 정리하려고 했는데 아 아니다 그게 아니라 대시보드로 보여주고 싶어",
         "대시보드로 보여주고 싶어."),
        // 7. 주제 전환 정정과 용어 복원이 겹치는 경우
        ("배포 자동화를 먼저 하려고 했거든 아 아니다 그게 아니라 테스트 커버리지부터 올리는 게 급해",
         "test coverage부터 올리는 게 급해."),
        // 8. 음절을 더듬어 반복한 경우
        ("그 다 다이얼 다 다이어그램으로 그려줘 그려줘",
         "다이어그램으로 그려줘."),
    ]

    static func messages(for raw: String) -> [ChatMessage] {
        var messages = [ChatMessage(role: "system", content: rules(nonce: UUID().uuidString.prefix(8).lowercased()))]
        for (input, output) in fewShots {
            messages.append(ChatMessage(role: "user", content: input))
            messages.append(ChatMessage(role: "assistant", content: output))
        }
        messages.append(ChatMessage(role: "user", content: raw))
        return messages
    }
}
