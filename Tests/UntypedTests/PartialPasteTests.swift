import AppKit
import Testing
@testable import Untyped

@MainActor
struct PartialPasteTests {
    @Test func ordinaryDictationPreservesMainPostedWithoutReceiptBehavior() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("clipboard", forType: .string)
        let result = await TextInserter.insert(
            "일반 받아쓰기", into: board, settleDelay: .zero,
            targetValue: { Issue.record("일반 삽입은 입력값을 확인하지 않는다"); return nil },
            paste: { true }
        )
        #expect(result == .posted)
        #expect(board.string(forType: .string) == "일반 받아쓰기")
    }

    @Test func partialEditWithoutReceiptNeverRetriesOrRestoresThePayload() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("clipboard", forType: .string)
        var posts = 0
        let result = await TextInserter.insert(
            "오늘", into: board, timeout: .milliseconds(20),
            expectedReplacement: (before: "내일 회의", after: "오늘 회의"),
            targetValue: { "내일 회의" }, paste: { posts += 1; return true }
        )
        #expect(result == .unconfirmed)
        #expect(posts == 1)
        #expect(board.string(forType: .string) == "오늘")
    }

    @Test func exactResultConfirmsReplacementEvenWhenNewWordAlreadyExists() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("clipboard", forType: .string)
        var value = "내일 회의. 오늘 발표."
        let result = await TextInserter.insert(
            "오늘", into: board, timeout: .milliseconds(100),
            expectedReplacement: (before: "내일 회의. 오늘 발표.", after: "오늘 회의. 오늘 발표."),
            targetValue: { value }, paste: { value = "오늘 회의. 오늘 발표."; return true }
        )
        #expect(result == .inserted)
        #expect(board.string(forType: .string) == "clipboard")
    }

    @Test func deletionCanConfirmAnEmptyFieldWithoutSubmitting() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("clipboard", forType: .string)
        var value = "삭제할 문장"
        let result = await TextInserter.insert(
            "", into: board, timeout: .milliseconds(100),
            expectedReplacement: (before: "삭제할 문장", after: ""),
            targetValue: { value }, paste: { value = ""; return true }
        )
        #expect(result == .inserted)
        #expect(value == "")
        #expect(board.string(forType: .string) == "clipboard")
    }

    @Test func changedBaselineNeverPostsAReplacement() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("clipboard", forType: .string)
        let result = await TextInserter.insert(
            "xy", into: board, timeout: .milliseconds(100),
            expectedReplacement: (before: "é ab", after: "é xy"),
            targetValue: { "e\u{301} ab" },
            paste: { Issue.record("변경된 UTF-16 오프셋에 붙여넣기 금지"); return true }
        )
        #expect(result == .notReady)
        #expect(board.string(forType: .string) == "clipboard")
    }
}
