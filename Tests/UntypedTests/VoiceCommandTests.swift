import Foundation
import Testing
@testable import Untyped

struct VoiceCommandTests {
    @Test func oldConfigsEnableCommandsAndOptOutRoundTrips() throws {
        let legacy = Data("{\"base_url\":\"http://localhost:8081/v1\",\"model\":\"m\",\"api_key\":\"\"}".utf8)
        var config = try JSONDecoder().decode(AppConfig.self, from: legacy)
        #expect(config.voiceCommandsEnabled)
        config.voiceCommandsEnabled = false
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(AppConfig.self, from: data).voiceCommandsEnabled == false)
        #expect(VoiceCommand.parse("보내", enabled: false) == nil)
        #expect(VoiceCommand.parse("수정 내일을 오늘로", enabled: false) == nil)
    }

    @Test func audioCommandModeUsesVerbatimRecognition() {
        let messages = VoiceEditPrompt.audioMessages(wav: Data([1, 2]))
        #expect(messages.count == 2)
        #expect(messages[0].role == "system")
        #expect(messages[1].content == .parts([
            .inputAudio(base64: "AQI=", format: "wav"),
            .text("이 음성을 원문 그대로 전사한다."),
        ]))
    }

    @Test func recognizesOnlyStandaloneSubmit() {
        for text in ["보내", " 보내.\n", "보내!", "보내。"] {
            #expect(VoiceCommand.parse(text) == .submit)
        }
        for text in ["자료를 보내", "보내 주세요", "보내는 방법", "수정사항 확인", "수정된 문장", ""] {
            #expect(VoiceCommand.parse(text) == nil)
        }
    }

    @Test func extractsEditInstructionWithoutChangingIt() {
        #expect(VoiceCommand.parse("수정, 내일을 오늘로 바꿔.") == .edit("내일을 오늘로 바꿔."))
        #expect(VoiceCommand.parse("수정 마지막 문장을 지워") == .edit("마지막 문장을 지워"))
        #expect(VoiceCommand.parse("수정. 첫 문장을 짧게 해줘") == .edit("첫 문장을 짧게 해줘"))
        #expect(VoiceCommand.parse("수정") == .edit(""))
        #expect(VoiceCommand.parse("수정해 주세요") == nil)
        #expect(VoiceCommand.parse("수정, -1을 1로 바꿔") == .edit("-1을 1로 바꿔"))
        #expect(VoiceCommand.parse("수정, ‘내일’을 ‘오늘’로 바꿔") == .edit("‘내일’을 ‘오늘’로 바꿔"))
    }

    @Test func editPayloadSeparatesFieldTextFromInstruction() throws {
        let messages = VoiceEditPrompt.messages(
            text: "내일 회의합니다.\n발표는 제가 합니다.", instruction: "내일을 오늘로 바꿔"
        )
        #expect(messages.count == 2)
        #expect(messages[0].role == "system")
        #expect(messages[1].role == "user")
        let data = try #require(messages[1].content.data(using: .utf8))
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(payload["text"] == "내일 회의합니다.\n발표는 제가 합니다.")
        #expect(payload["instruction"] == "내일을 오늘로 바꿔")
    }
}
