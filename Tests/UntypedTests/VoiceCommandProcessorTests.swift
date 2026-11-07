import Foundation
import Testing
@testable import Untyped

@MainActor
struct VoiceCommandProcessorTests {
    @Test func partialWriteFailureExplainsTheActualStoppedStage() async {
        let input = VoiceCommandInput(
            text: "내일 회의", isCurrent: { true }, read: { "내일 회의" },
            writeRange: { _, _, _ in .unavailable }, postReturn: { false },
            failureReason: { "부분 수정 · 선택 범위 재조회 실패" }
        )
        let result = await VoiceCommandProcessor.run(.edit("내일을 오늘로"), input: input) { _, _ in
            .text(#"{"edits":[{"old":"내일","new":"오늘"}]}"#)
        }
        #expect(result == .failed("부분 수정 · 선택 범위 재조회 실패"))
    }

    @Test func invalidPatchSetsNeverWriteEvenWhenTheFirstPatchIsValid() async {
        var writes = 0
        let input = VoiceCommandInput(text: "내일 회의. 내일 발표.", isCurrent: { true }, read: { "내일 회의. 내일 발표." }, writeRange: { _, _, _ in
            writes += 1; return .completed
        }, postReturn: { Issue.record("수정 중 전송 금지"); return false })
        for json in [
            #"{"text":"입력창 전체를 다시 쓴 결과"}"#,
            #"{"edits":[{"old":"내일 회의","new":"오늘 회의"},{"old":"없는 문구","new":"오류"}]}"#,
            #"{"edits":[{"old":"내일","new":"오늘"}]}"#,
            #"{"edits":[]}"#,
        ] {
            let outcome = await VoiceCommandProcessor.run(.edit("일부 수정"), input: input) { _, _ in .text(json) }
            if case .failed = outcome {} else { Issue.record("유효하지 않은 수정은 원문을 유지해야 한다") }
        }
        #expect(writes == 0)
    }

    @Test func targetActivationRequiresCapturedOriginFocus() async {
        var activations = 0
        for guardFocus: (() -> Bool)? in [nil, { false }] {
            let prepared = await VoiceCommandProcessor.prepareTarget(originIsCurrent: guardFocus) {
                activations += 1; return true
            }
            #expect(!prepared)
        }
        #expect(activations == 0)
        var focusedElement = "web page"
        let originalElement = focusedElement
        let originIsCurrent = { focusedElement == originalElement }
        focusedElement = "another input in the same app"
        #expect(!(await VoiceCommandProcessor.prepareTarget(originIsCurrent: originIsCurrent) {
            activations += 1; return true
        }))
        #expect(activations == 0)
        focusedElement = originalElement
        #expect(await VoiceCommandProcessor.prepareTarget(originIsCurrent: originIsCurrent) {
            activations += 1; return true
        })
        #expect(activations == 1)
    }

    @Test func explicitDeletionCanClearTheWholeField() async {
        var value: String? = "삭제할 문장"
        let input = VoiceCommandInput(text: value, isCurrent: { true }, read: { value }, writeRange: { range, replacement, expected in
            value = (expected as NSString).replacingCharacters(in: range, with: replacement); return .completed
        }, postReturn: { false })
        let result = await VoiceCommandProcessor.run(.edit("내용을 모두 지워"), input: input) { _, _ in .text(#"{"edits":[{"old":"삭제할 문장","new":""}]}"#) }
        #expect(result == .edited(""))
        #expect(value == "")
    }

    @Test func editingUsesFieldTextAndDoesNotSubmit() async {
        var value: String? = "내일 회의. 발표는 제가 합니다."
        let input = VoiceCommandInput(text: value, isCurrent: { true }, read: { value }, writeRange: { range, replacement, expected in
            value = (expected as NSString).replacingCharacters(in: range, with: replacement); return .completed
        }, postReturn: { Issue.record("수정 중 Enter 금지"); return true })
        let result = await VoiceCommandProcessor.run(.edit("내일을 오늘로 바꿔"), input: input) { text, instruction in
            #expect(text == "내일 회의. 발표는 제가 합니다.")
            #expect(instruction == "내일을 오늘로 바꿔")
            return .text(#"{"edits":[{"old":"내일 회의.","new":"오늘 회의."}]}"#)
        }
        #expect(result == .edited("오늘 회의. 발표는 제가 합니다."))
        #expect(value == "오늘 회의. 발표는 제가 합니다.")
    }

    @Test func inferenceFailureDoesNotWriteInstructionOrPressReturn() async {
        var events = 0
        let input = VoiceCommandInput(text: "원문", isCurrent: { true }, read: { "원문" }, writeRange: { _, _, _ in events += 1; return .completed
        }, postReturn: { events += 1; return true })
        let result = await VoiceCommandProcessor.run(.edit("수정 지시"), input: input) { _, _ in .failed(.timeout) }
        if case .failed = result {} else { Issue.record("실패가 사용자에게 전달되어야 한다") }
        #expect(events == 0)
    }

    @Test func missingInstructionOrInputSkipsInference() async {
        let input = VoiceCommandInput(text: "원문", isCurrent: { true }, read: { "원문" }, writeRange: { _, _, _ in Issue.record("쓰기 금지"); return .unavailable
        }, postReturn: { false })
        for (command, target) in [(VoiceCommand.edit(""), input), (.edit("바꿔"), nil)] {
            let result = await VoiceCommandProcessor.run(command, input: target) { _, _ in
                Issue.record("불가능한 수정에서 서버 요청 금지"); return .text("오류")
            }
            if case .failed = result {} else { Issue.record("실패여야 한다") }
        }
    }

    @Test func submitSkipsInferenceAndDoesNotWriteCommand() async {
        var returns = 0
        let input = VoiceCommandInput(text: "원문", isCurrent: { true }, read: { "원문" }, writeRange: { _, _, _ in Issue.record("보내를 삽입하면 안 된다"); return .unavailable
        }, postReturn: { returns += 1; return true })
        let result = await VoiceCommandProcessor.run(.submit, input: input) { _, _ in
            Issue.record("보내는 LLM 요청 없음"); return .text("오류")
        }
        #expect(result == .submitted)
        #expect(returns == 1)
    }

    @Test func editRacingWithManualChangeDoesNotOverwrite() async {
        var value: String? = "원문"
        let input = VoiceCommandInput(text: value, isCurrent: { true }, read: { value }, writeRange: { _, _, _ in Issue.record("직접 수정한 내용을 덮어쓰면 안 된다"); return .unavailable
        }, postReturn: { false })
        let result = await VoiceCommandProcessor.run(.edit("바꿔"), input: input) { _, _ in
            value = "직접 편집"
            return .text(#"{"edits":[{"old":"원문","new":"수정문"}]}"#)
        }
        #expect(result == .failed(VoiceCommandInput.Result.changed.notice))
        #expect(value == "직접 편집")
    }
}
