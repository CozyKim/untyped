import AppKit
import Testing
@testable import Untyped

@MainActor
struct PartialPasteTests {
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
