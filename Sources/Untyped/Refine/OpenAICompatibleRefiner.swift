import Foundation

/// oMLX, Ollama, LM Studio가 모두 같은 형식을 쓴다.
/// 구현체를 늘리지 않고 baseURL과 model만 바꿔 백엔드를 갈아끼운다.
///
/// 같은 서버가 오디오를 한 요청으로 다듬는 일도 맡는다(`AudioRefiner`). 모델이 오디오 입력을
/// 받을 때만 동작하며, 텍스트 전용 모델이면 서버가 400을 돌려주고 그 상태 코드가 실패 원인으로 남는다.
struct OpenAICompatibleRefiner: TextRefiner, AudioRefiner {
    let baseURL: URL
    let model: String
    let apiKey: String?
    let systemPrompt: String
    let includeExamples: Bool
    let maxTokens: Int

    /// 텍스트 경로는 문자열 메시지만, 오디오 경로는 오디오 파트가 섞인 메시지를 보낸다. 나머지 필드는 같다.
    private struct Request<Message: Encodable>: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let max_tokens: Int
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
            let finish_reason: String?
        }
        let choices: [Choice]
    }

    var isAvailable: Bool {
        get async {
            var request = URLRequest(url: baseURL.appendingPathComponent("models"))
            request.timeoutInterval = 2
            if let apiKey {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        }
    }

    /// origin의 `/health`에 묻는다. 1초 안에 답이 없거나 어떤 오류든 나면 `unknown` — 예열을
    /// 건너뛸 근거를 찾는 것이지 받아쓰기를 막는 조건이 아니라, 길게 기다리지 않는다. 응답도
    /// 요청도 로그에 남기지 않는다.
    var health: LLMHealth {
        get async {
            guard let url = LLMHealth.url(for: baseURL) else { return .unknown }
            var request = URLRequest(url: url)
            request.timeoutInterval = 1
            if let apiKey {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse else { return .unknown }
            return LLMHealth.parse(statusCode: http.statusCode, body: data)
        }
    }

    /// 실제 요청과 같은 프리픽스로 1토큰만 요청한다. 메모리가 부족한 기기에서는 모델이
    /// 스왑에 밀려나 첫 응답이 수 초~수십 초 걸리는데, 녹음하는 동안 그 비용을 미리 치르고
    /// 프리픽스 블록도 캐시에 올려 두면 전사가 끝났을 때 곧바로 다듬을 수 있다.
    func warmUp() async {
        guard let request = try? chatRequest(for: ".", maxTokens: 1) else { return }
        _ = try? await URLSession.shared.data(for: request)
    }

    private func chatRequest(for raw: String, maxTokens: Int) throws -> URLRequest {
        try chatCompletionsRequest(
            messages: RefinementPrompt.messages(
                for: raw, systemPrompt: systemPrompt, includeExamples: includeExamples
            ),
            maxTokens: maxTokens
        )
    }

    private func chatCompletionsRequest<Message: Encodable>(
        messages: [Message], maxTokens: Int
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        // temperature 0으로 고정한다. 프롬프트가 정해지면 모델의 출력 변동이 없다.
        request.httpBody = try JSONEncoder().encode(
            Request(model: model, messages: messages, temperature: 0, max_tokens: maxTokens)
        )
        return request
    }

    func refine(_ raw: String) async throws -> String {
        try await completionText(for: chatRequest(for: raw, maxTokens: maxTokens))
    }

    /// 녹음 전체를 같은 프롬프트·예시 뒤에 붙여 한 요청으로 다듬는다. 출력 상한도 같다 —
    /// 결과가 그보다 길면 잘린 채 넣지 않고 실패로 처리해 사용자가 상한을 올리게 한다.
    func refine(wav: Data) async throws -> String {
        try await completionText(for: chatCompletionsRequest(
            messages: RefinementPrompt.audioMessages(
                wav: wav, systemPrompt: systemPrompt, includeExamples: includeExamples
            ),
            maxTokens: maxTokens
        ))
    }

    private func completionText(for request: URLRequest) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RefinerError.badStatus(0) }
        guard http.statusCode == 200 else { throw RefinerError.badStatus(http.statusCode) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let choice = decoded.choices.first else {
            throw RefinerError.emptyResponse
        }
        // 출력 제한에 걸리면 서버는 200과 문법적으로 올바른 잘린 텍스트를 반환한다.
        // 이 검사 없이는 불완전한 문장이 그대로 삽입되고 폴백이 작동하지 않으며
        // 사용자 음성의 끝이 조용히 손실된다. 원본 전사 삽입보다 훨씬 나쁘다.
        if choice.finish_reason == "length" {
            throw RefinerError.truncated
        }
        return choice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum RefinerError: Error {
    case badStatus(Int)
    case emptyResponse
    case truncated
}
