import Foundation

/// oMLX, Ollama, LM Studio가 모두 같은 형식을 쓴다.
/// 구현체를 늘리지 않고 baseURL과 model만 바꿔 백엔드를 갈아끼운다.
struct OpenAICompatibleRefiner: TextRefiner {
    let baseURL: URL
    let model: String
    let apiKey: String?

    private struct Request: Encodable {
        let model: String
        let messages: [ChatMessage]
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

    func refine(_ raw: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        // temperature 0으로 고정한다. 프롬프트가 정해지면 모델의 출력 변동이 없다.
        request.httpBody = try JSONEncoder().encode(
            Request(model: model, messages: RefinementPrompt.messages(for: raw),
                    temperature: 0, max_tokens: 900)
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RefinerError.badStatus
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let choice = decoded.choices.first else {
            throw RefinerError.emptyResponse
        }
        if choice.finish_reason == "length" {
            throw RefinerError.truncated
        }
        return choice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum RefinerError: Error {
    case badStatus
    case emptyResponse
    case truncated
}
