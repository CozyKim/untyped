import Foundation

/// content가 문자열이거나 파트 배열인 채팅 메시지. 오디오는 OpenAI의 `input_audio` 파트로
/// 보낸다 — oMLX, vLLM, llama.cpp가 같은 모양을 받는다. 시스템·예시 메시지는 문자열 content로
/// 둔다 — 파트 배열 content를 시스템 역할에서 거부하는 서버가 있다.
struct MultipartChatMessage: Encodable, Sendable, Equatable {
    let role: String
    let content: Content

    enum Content: Encodable, Sendable, Equatable {
        case text(String)
        case parts([ContentPart])

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text): try container.encode(text)
            case .parts(let parts): try container.encode(parts)
            }
        }
    }

    enum ContentPart: Encodable, Sendable, Equatable {
        case text(String)
        /// data는 base64 문자열(data URI 아님). format은 "wav"처럼 파일 형식 이름.
        case inputAudio(base64: String, format: String)

        private enum CodingKeys: String, CodingKey {
            case type, text
            case inputAudio = "input_audio"
        }

        private struct InputAudio: Encodable {
            let data: String
            let format: String
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .inputAudio(let base64, let format):
                try container.encode("input_audio", forKey: .type)
                try container.encode(InputAudio(data: base64, format: format), forKey: .inputAudio)
            }
        }
    }
}
