import AppKit
import Testing
@testable import Untyped

@Suite(.serialized)
@MainActor
struct TextInserterTests {
    private func makePasteboard(containing text: String = "원본") -> NSPasteboard {
        let board = NSPasteboard(name: .init("TextInserterTests-\(UUID().uuidString)"))
        board.clearContents()
        board.setString(text, forType: .string)
        return board
    }

    @Test("수신 확인 뒤에만 원래 클립보드의 모든 형식을 복원한다")
    func confirmedPasteRestoresAllRepresentations() async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        let custom = NSPasteboard.PasteboardType("test.binary")
        board.setData(Data([0, 1, 255]), forType: custom)
        var value = "기존 문장 "
        let result = await TextInserter.insert("받아쓰기", into: board, targetValue: { value }) {
            value += board.string(forType: .string) ?? ""
            return true
        }
        #expect(result == .inserted)
        #expect(value == "기존 문장 받아쓰기")
        #expect(board.string(forType: .string) == "원본")
        #expect(board.data(forType: custom) == Data([0, 1, 255]))
    }

    @Test("수신 미확인은 복원·Return·재시도를 하지 않는다")
    func unconfirmedPasteKeepsRefinedText() async throws {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        var events = 0
        var returns = 0
        let result = await TextInserter.insert(
            "다듬음", into: board, timeout: .milliseconds(20), targetValue: { nil },
            paste: { events += 1; return true }, submit: { returns += 1; return true }
        )
        try await Task.sleep(for: .milliseconds(1150))
        #expect(result == .unconfirmed)
        #expect(board.string(forType: .string) == "다듬음")
        #expect(events == 1)
        #expect(returns == 0)
    }

    @Test("외부 클립보드 변경은 복원이나 재전송으로 덮어쓰지 않는다")
    func externalChangeIsNotOverwritten() async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        let result = await TextInserter.insert("받아쓰기", into: board) {
            board.clearContents()
            board.setString("사용자가 새로 복사한 것", forType: .string)
            return true
        }
        #expect(result == .clipboardChanged)
        #expect(board.string(forType: .string) == "사용자가 새로 복사한 것")
    }

    @Test("실패한 게시와 활성화는 원래 클립보드를 보존한다")
    func failuresBeforePostingPreserveOriginal() async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        let inactive = await TextInserter.insert("받아쓰기", into: board, prepare: { false }, paste: {
            Issue.record("활성화 실패 뒤 붙여넣으면 안 된다")
            return true
        })
        #expect(inactive == .notReady)
        #expect(board.string(forType: .string) == "원본")
        let failed = await TextInserter.insert("받아쓰기", into: board, paste: { false })
        #expect(failed == .eventFailed)
        #expect(board.string(forType: .string) == "원본")
    }

    @Test("클립보드 쓰기 뒤 포커스가 바뀌면 게시 전에 중단한다")
    func lostFocusBeforePostingRestoresOriginal() async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        let result = await TextInserter.insert(
            "다듬음", into: board,
            hasFocus: { board.string(forType: .string) == "원본" },
            paste: { Issue.record("다른 앱에 게시하면 안 된다"); return true }
        )
        #expect(result == .notReady)
        #expect(board.string(forType: .string) == "원본")
    }

    @Test("동시 호출도 준비·게시·수신·복원 전체가 직렬화된다")
    func concurrentInsertsPreserveOriginal() async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        var received = ""
        var order: [String] = []
        var tasks: [Task<TextInserter.Result, Never>] = []
        for index in 0..<3 {
            tasks.append(Task { @MainActor in
                await TextInserter.insert(
                    "문장\(index)", into: board,
                    prepare: {
                        #expect(board.string(forType: .string) == "원본")
                        order.append("prepare")
                        return true
                    }, targetValue: { received }, paste: {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(30))
                            received += board.string(forType: .string) ?? ""
                            order.append("read")
                        }
                        return true
                    }
                )
            })
        }
        for task in tasks { #expect(await task.value == .inserted) }
        #expect(order == ["prepare", "read", "prepare", "read", "prepare", "read"])
        for index in 0..<3 { #expect(received.contains("문장\(index)")) }
        #expect(board.string(forType: .string) == "원본")
    }

    @Test("동일한 끝부분·부분 결과·오래된 전체 문장을 수신으로 오인하지 않는다")
    func receiptRequiresNewCompleteText() {
        #expect(!TextInserter.received("새 문장 마지막", before: "옛 문장 마지막", after: "옛 문장 마지막"))
        #expect(!TextInserter.received("새 문장 마지막", before: "", after: "새 문장"))
        #expect(!TextInserter.received("전체", before: "전체", after: "전체 일부"))
        #expect(TextInserter.received("전체", before: "전체", after: "전체전체"))
        #expect(!TextInserter.received("전체", before: nil, after: "전체"))
    }

    @Test("Return은 전체 텍스트를 수신한 뒤 한 번만 보낸다")
    func submitFollowsReceipt() async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        var value = ""
        var submitted: [String] = []
        let result = await TextInserter.insert(
            "전체 문장", into: board, targetValue: { value }, paste: {
                Task { @MainActor in
                    value = "전체"
                    try? await Task.sleep(for: .milliseconds(30))
                    value = board.string(forType: .string) ?? ""
                }
                return true
            }, submit: { submitted.append(value); return true }
        )
        #expect(result == .inserted)
        #expect(submitted == ["전체 문장"])
        #expect(board.string(forType: .string) == "원본")
    }

    @Test("게시 뒤 포커스 손실과 취소는 늦은 읽기의 데이터를 복원하지 않는다")
    func interruptionAfterPostPreservesPayload() async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        var focused = true
        let lost = await TextInserter.insert("다듬음", into: board, hasFocus: { focused }, paste: {
            focused = false
            return true
        })
        #expect(lost == .unconfirmed)
        #expect(board.string(forType: .string) == "다듬음")
        var posted = false
        let task = Task { @MainActor in
            await TextInserter.insert("취소 후에도 보존", into: board, paste: { posted = true; return true })
        }
        while !posted { await Task.yield() }
        task.cancel()
        #expect(await task.value == .cancelled)
        #expect(board.string(forType: .string) == "취소 후에도 보존")
    }
    @Test("수신 관측 중 포커스가 바뀌면 Return을 보내지 않는다")
    func focusChangeDuringReceiptPreventsSubmit() async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        var posted = false
        var focused = true
        var returns = 0
        let result = await TextInserter.insert(
            "전체 문장", into: board, hasFocus: { focused }, targetValue: {
                if posted { focused = false; return "전체 문장" }
                return ""
            }, paste: { posted = true; return true },
            submit: { returns += 1; return true }
        )
        #expect(result == .unconfirmed)
        #expect(returns == 0)
        #expect(board.string(forType: .string) == "전체 문장")
    }

}
