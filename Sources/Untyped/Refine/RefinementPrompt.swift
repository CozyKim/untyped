import Foundation

struct ChatMessage: Codable, Sendable {
    let role: String
    let content: String
}

enum RefinementPrompt {
    /// 음차된 용어를 되돌릴 후보 집합. 음차와 영문의 대응을 주지 않는다.
    /// 대응을 병기한 판은 점수가 같으면서 길이만 늘어 희석을 키운다.
    /// 항목을 늘릴 때는 회귀 스위트로 확인한다.
    private static let glossary = """
    PR, approve, review, merge, main, branch, commit, rebase, push, pull, revert, \
    deploy, staging, production, rollback, endpoint, timeout, retry, logic, log, debug, error, \
    authentication, authorization, token, refactoring, dependency, injection, container, restart, \
    cache, migration, schema, queue, worker, latency, throughput, build, release, hotfix, \
    agent, subagent, orchestrator, prompt, context, embedding, langchain, typeless, diagram, \
    TTS, STT, LLM, API, SDK, CLI, UI, repo, config
    """

    /// 기본 시스템 프롬프트. 설정 창에서 바꾸지 않았을 때 쓰이고, "기본값으로 되돌리기"의
    /// 원본이다.
    ///
    /// 규칙은 넷을 넘기지 않는다. 같은 내용을 여섯으로 나눠 쓴 판이
    /// 회귀 스위트에서 더 낮은 점수를 냈다. 규칙이 많아지면 각각의 영향력이 희석된다.
    static let defaultSystemPrompt = """
        받아쓰기 원문을 다듬는다.
        1. 정정 표시어('아니', '아니다', '그게 아니라')가 나오면 표시어와 그 앞의 말을 전부 지우고 \
        뒤의 말만 남긴다. 앞뒤 주제가 달라도 마찬가지다. 문장이 길고 절이 여러 개여도 똑같이 적용한다.
        2. 군말(어, 음, 그, 그 뭐지)과 더듬어 반복한 말을 지운다.
        3. 아래 사전의 단어가 음차돼 있으면 영문으로 되돌린다. 사전에 없는 말은 손대지 않는다.
          사전: \(glossary)
        4. 문장부호와 띄어쓰기를 정리한다. 그 외의 내용은 바꾸지 않는다.
        다듬은 문장만 출력한다.
        """

    /// few-shot 예시. 규칙 하나씩을 시연한다. 설정 창이 읽기 전용으로 보여주므로
    /// 순서와 내용이 곧 사용자가 보는 목록이다.
    static let examples: [(input: String, output: String)] = [
        // 1. 짧은 문장의 정정
        ("어 내일 아침에 자료를 보내드릴게요 아니 오늘 저녁에 자료를 보내드릴게요",
         "오늘 저녁에 자료를 보내드릴게요"),
        // 2. 필러만 있는 경우
        ("그 뭐지 그 회의실을 음 3층으로 잡아줘",
         "회의실을 3층으로 잡아줘"),
        // 3. 문장 일부만 정정되고 나머지는 보존
        ("보고서는 김 대리가 쓰고 발표는 이 과장이 하기로 했는데 아니 발표도 김 대리가 합니다",
         "보고서는 김 대리가 쓰고 발표도 김 대리가 합니다"),
        // 4. 음차된 개발 용어를 영문으로
        ("제플로이는 스테이징에 먼저 하고 프로덕션은 그 다음에 하고 로그도 체크해주세요",
         "deploy는 staging에 먼저 하고 production은 그 다음에 하고 log도 확인해주세요"),
        // 5. 영어 용어가 없는 순수 한국어 - 손대지 않는다
        ("이번 분기 목표는 신규 사용자 확보하고 이탈률을 낮추는 겁니다",
         "이번 분기 목표는 신규 사용자 확보하고 이탈률을 낮추는 겁니다"),
        // 6. 주제가 전환되는 정정 - 앞 절을 통째로 버린다
        ("엑셀로 정리하려고 했는데 아 아니다 그게 아니라 대시보드로 보여주고 싶어",
         "대시보드로 보여주고 싶어"),
        // 7. 주제 전환 정정과 용어 복원이 겹치는 경우
        ("배포 자동화를 먼저 하려고 했거든 아 아니다 그게 아니라 테스트 커버리지부터 올리는 게 급해",
         "test coverage부터 올리는 게 급해"),
        // 8. 음절을 더듬어 반복한 경우
        ("그 다 다이얼 다 다이어그램으로 그려줘 그려줘",
         "다이어그램으로 그려줘"),
    ]

    /// 시스템 메시지는 받은 프롬프트를 그대로 쓴다. 매 호출 바이트 단위로 같아야
    /// 서버의 프리픽스 캐시가 적중해 첫 토큰이 빨리 나온다. 텍스트만 보내는 요청에서는
    /// 사용자 메시지가 프리픽스 뒤에 붙어 캐시가 요청을 정확히 구분하므로(실측으로
    /// 확인), 캐시를 깨기 위한 난수를 붙이지 않는다.
    ///
    /// few-shot 예시는 기본 규칙(정정 삭제, 군말 제거, 용어 복원)을 시연한다. 성격이
    /// 다른 프롬프트(예: 번역)를 쓰면 예시가 지시보다 세게 작용해 지시가 무시되므로
    /// 호출자가 예시를 뺄 수 있어야 한다.
    static func messages(for raw: String, systemPrompt: String, includeExamples: Bool) -> [ChatMessage] {
        prefix(systemPrompt: systemPrompt, includeExamples: includeExamples)
            + [ChatMessage(role: "user", content: raw)]
    }

    /// 오디오를 한 요청으로 다듬을 때 오디오 파트 뒤에 붙이는 지시. 시스템 프롬프트와 예시는
    /// "원문 텍스트"를 전제로 쓰였으므로, 오디오가 그 원문 자리라는 것을 한 줄로 알린다.
    static let audioInstruction = "이 음성이 받아쓰기 원문이다. 받아쓴 뒤 규칙대로 다듬은 문장만 출력한다."

    /// 텍스트 경로와 같은 시스템 프롬프트·예시 뒤에, 원문 대신 녹음 오디오를 붙인다. 프리픽스가
    /// 바이트 단위로 같아 서버의 프리픽스 캐시가 텍스트 경로와 공유된다. 전사 단계가 따로
    /// 없으므로 실패하면 넣을 원본이 없다 — 그 대신 요청이 한 번이다.
    static func audioMessages(
        wav: Data, systemPrompt: String, includeExamples: Bool
    ) -> [MultipartChatMessage] {
        prefix(systemPrompt: systemPrompt, includeExamples: includeExamples)
            .map { MultipartChatMessage(role: $0.role, content: .text($0.content)) }
            + [MultipartChatMessage(role: "user", content: .parts([
                .inputAudio(base64: wav.base64EncodedString(), format: "wav"),
                .text(audioInstruction),
            ]))]
    }

    private static func prefix(systemPrompt: String, includeExamples: Bool) -> [ChatMessage] {
        var messages = [ChatMessage(role: "system", content: systemPrompt)]
        if includeExamples {
            for (input, output) in examples {
                messages.append(ChatMessage(role: "user", content: input))
                messages.append(ChatMessage(role: "assistant", content: output))
            }
        }
        return messages
    }
}
