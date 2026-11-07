import Foundation
import Testing
@testable import Untyped

struct VoiceEditPlanTests {
    @Test func preservesContextAndMinimizesTheActualWrite() throws {
        let original = "  안녕하세요.\n내일 회의합니다.\n발표는 제가 합니다.\n"
        let plan = try VoiceEditPlan.decode(
            #"{"edits":[{"old":"내일 회의합니다.","new":"오늘 회의합니다."}]}"#, original: original
        )
        #expect(plan.result == "  안녕하세요.\n오늘 회의합니다.\n발표는 제가 합니다.\n")
        #expect(plan.patches.count == 1)
        #expect(plan.patches[0].range == NSRange(location: 9, length: 2))
        #expect(plan.patches[0].replacement == "오늘")
    }

    @Test func multipleEditsResolveAgainstOriginalAndApplyFromTheEnd() throws {
        let plan = try VoiceEditPlan.decode(
            #"{"edits":[{"old":"내일","new":"오늘 저녁"},{"old":"김 대리","new":"이 과장"}]}"#,
            original: "내일 회의. 발표는 김 대리."
        )
        #expect(plan.result == "오늘 저녁 회의. 발표는 이 과장.")
        #expect(plan.patches.count == 2)
        #expect(plan.patches[0].range.location > plan.patches[1].range.location)
    }

    @Test func repeatedAnchorsNeedUnchangedContextToChooseTheRightOccurrence() throws {
        let original = "내일 회의. 내일 발표."
        #expect(throws: VoiceEditPlan.Failure.ambiguousAnchor) {
            try VoiceEditPlan.decode(#"{"edits":[{"old":"내일","new":"오늘"}]}"#, original: original)
        }
        let plan = try VoiceEditPlan.decode(#"{"edits":[{"old":"내일 발표","new":"오늘 발표"}]}"#, original: original)
        #expect(plan.result == "내일 회의. 오늘 발표.")
    }

    @Test func missingOrOverlappingAnchorsRejectTheWholePlan() {
        #expect(throws: VoiceEditPlan.Failure.missingAnchor) {
            try VoiceEditPlan.decode(#"{"edits":[{"old":"없는 말","new":"변경"}]}"#, original: "내일 회의")
        }
        #expect(throws: VoiceEditPlan.Failure.overlappingEdits) {
            try VoiceEditPlan.decode(
                #"{"edits":[{"old":"내일 회의","new":"오늘 회의"},{"old":"회의","new":"발표"}]}"#,
                original: "내일 회의"
            )
        }
        #expect(throws: VoiceEditPlan.Failure.ambiguousAnchor) {
            try VoiceEditPlan.decode(#"{"edits":[{"old":"aa","new":"b"}]}"#, original: "aaa")
        }
        #expect(throws: VoiceEditPlan.Failure.overlappingEdits) {
            try VoiceEditPlan.decode(
                #"{"edits":[{"old":"a","new":"ax"},{"old":"b","new":"yb"}]}"#, original: "ab"
            )
        }
    }

    @Test func insertionAndDeletionUseAnExistingAnchor() throws {
        let insertion = try VoiceEditPlan.decode(
            #"{"edits":[{"old":"회의","new":"중요한 회의"}]}"#, original: "내일 회의"
        )
        #expect(insertion.result == "내일 중요한 회의")
        #expect(insertion.patches[0].range == NSRange(location: 3, length: 0))
        #expect(insertion.patches[0].replacement == "중요한 ")
        let deletion = try VoiceEditPlan.decode(
            #"{"edits":[{"old":"삭제할 문장","new":""}]}"#, original: "삭제할 문장"
        )
        #expect(deletion.result == "")
    }

    @Test func unicodeRangesPreserveEmojiAndDecomposedText() throws {
        let original = "👩🏽‍💻 e\u{301}\n내일 회의 ✅"
        let plan = try VoiceEditPlan.decode(#"{"edits":[{"old":"내일","new":"오늘"}]}"#, original: original)
        #expect(plan.result == "👩🏽‍💻 e\u{301}\n오늘 회의 ✅")
        #expect(plan.patches[0].range == NSRange(location: 11, length: 2))
        #expect(throws: VoiceEditPlan.Failure.missingAnchor) {
            try VoiceEditPlan.decode(#"{"edits":[{"old":"é","new":"e"}]}"#, original: original)
        }
    }

    @Test func malformedResponsesAndEmptyAnchorsAreRejected() {
        for json in ["", "{}", #"{"text":"전체 재작성"}"#, #"{"edits":[{"old":"a"}]}"#] {
            #expect(throws: DecodingError.self) { try VoiceEditPlan.decode(json, original: "a") }
        }
        #expect(throws: VoiceEditPlan.Failure.emptyAnchor) {
            try VoiceEditPlan.decode(#"{"edits":[{"old":"","new":"추가"}]}"#, original: "a")
        }
    }

    @Test func emptyOrIdenticalEditsDoNotMutateAnything() throws {
        let empty = try VoiceEditPlan.decode(#"{"edits":[]}"#, original: "원문\n")
        #expect(empty.result == "원문\n")
        #expect(empty.patches.isEmpty)
        let identical = try VoiceEditPlan.decode(#"{"edits":[{"old":"원문","new":"원문"}]}"#, original: "원문\n")
        #expect(identical.patches.isEmpty)
    }
}
