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

    @Test("입력값을 읽지 못해도 전송을 완료하고 설정된 Return을 보낸다")
    func trustsPostedPasteWithoutReadingValue() async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        var events: [String] = []
        var diagnostics: [String] = []
        let result = await TextInserter.insert(
            "터미널 문장", into: board, timeout: .milliseconds(20), settleDelay: .milliseconds(1),
            onDiagnostic: { diagnostics.append($0) },
            paste: { events.append("paste"); return true },
            submit: { events.append("return"); return true }
        )
        #expect(result == .posted)
        #expect(events == ["paste", "return"])
        #expect(board.string(forType: .string) == "터미널 문장")
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.contains("전송 완료") == true)
    }

    @Test("Return 없이도 한 번 게시한 뒤 수신을 기다리지 않고 완료한다")
    func pasteOnlyCompletesWithoutReceipt() async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        var posts = 0
        var focused = true
        let result = await TextInserter.insert(
            "받아쓰기", into: board, settleDelay: .zero, hasFocus: { focused },
            paste: { posts += 1; focused = false; return true }
        )
        #expect(result == .posted)
        #expect(posts == 1)
        #expect(board.string(forType: .string) == "받아쓰기")
    }

    @Test("외부 클립보드 변경은 복원이나 재전송으로 덮어쓰지 않는다")
    func externalChangeIsNotOverwritten() async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        var returns = 0
        let result = await TextInserter.insert("받아쓰기", into: board, settleDelay: .zero, paste: {
            board.clearContents()
            board.setString("사용자가 새로 복사한 것", forType: .string)
            return true
        }, submit: { returns += 1; return true })
        #expect(result == .clipboardChanged)
        #expect(board.string(forType: .string) == "사용자가 새로 복사한 것")
        #expect(returns == 0)
    }

    @Test("게시 전 실패는 모든 클립보드 형식을 보존한다", arguments: ["empty", "activation", "event", "focus"])
    func failuresBeforePostingPreserveOriginal(scenario: String) async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        let custom = NSPasteboard.PasteboardType("test.binary")
        board.setData(Data([0, 1, 255]), forType: custom)
        var posts = 0
        var returns = 0
        let result = await TextInserter.insert(
            scenario == "empty" ? "" : "받아쓰기", into: board, settleDelay: .zero,
            prepare: { scenario != "activation" },
            hasFocus: { scenario != "focus" || board.string(forType: .string) == "원본" },
            paste: { posts += 1; return false }, submit: { returns += 1; return true }
        )
        #expect(result == (scenario == "event" ? .eventFailed : .notReady))
        #expect(posts == (scenario == "event" ? 1 : 0))
        #expect(returns == 0)
        #expect(board.string(forType: .string) == "원본")
        #expect(board.data(forType: custom) == Data([0, 1, 255]))
    }

    @Test("게시 전 포커스 조회 실패는 복구를 기다리되 실제 불일치는 거부한다", arguments: ["recover", "unknown", "other"])
    func preflightFocusHandling(scenario: String) async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        var reads = 0
        var posts = 0
        let result = await TextInserter.insert(
            "문장", into: board, timeout: .milliseconds(40), settleDelay: .zero,
            hasFocus: {
                reads += 1
                if scenario == "other" { return false }
                return scenario == "recover" && reads > 2 ? true : nil
            }, paste: { posts += 1; return true }
        )
        #expect(result == (scenario == "recover" ? .posted : .notReady))
        #expect(posts == (scenario == "recover" ? 1 : 0))
        #expect(board.string(forType: .string) == (scenario == "recover" ? "문장" : "원본"))
        if scenario == "other" { #expect(reads == 1) }
    }

    @Test("게시 뒤 포커스가 달라지거나 읽히지 않으면 다른 앱에 Return을 보내지 않는다", arguments: [false, nil] as [Bool?])
    func focusLossBeforeReturnKeepsPayload(focusAfterPaste: Bool?) async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        var focused: Bool? = true
        var returns = 0
        var diagnostics: [String] = []
        let result = await TextInserter.insert(
            "전체 문장", into: board, settleDelay: .zero, hasFocus: { focused },
            onDiagnostic: { diagnostics.append($0) },
            paste: { focused = focusAfterPaste; return true },
            submit: { returns += 1; return true }
        )
        #expect(result == .eventFailed)
        #expect(returns == 0)
        #expect(board.string(forType: .string) == "전체 문장")
        #expect(diagnostics.first?.contains("Return 생략") == true)
        #expect(diagnostics.first?.contains("⌘V 게시 후") == true)
    }

    @Test("Return 전송 실패 뒤에는 이미 보낸 문장을 클립보드에 남긴다")
    func submitFailureKeepsPayload() async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        let result = await TextInserter.insert(
            "전체 문장", into: board, settleDelay: .zero,
            paste: { true }, submit: { false }
        )
        #expect(result == .eventFailed)
        #expect(board.string(forType: .string) == "전체 문장")
    }

    @Test("게시 전 취소는 키 이벤트와 클립보드를 건드리지 않는다")
    func cancellationBeforePostPreservesOriginal() async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        var posts = 0
        let task = Task { @MainActor in
            await TextInserter.insert("문장", into: board, paste: { posts += 1; return true })
        }
        task.cancel()
        #expect(await task.value == .cancelled)
        #expect(posts == 0)
        #expect(board.string(forType: .string) == "원본")
    }

    @Test("게시 뒤 취소해도 클립보드는 남기고 Return은 보내지 않는다")
    func cancellationAfterPostKeepsPayload() async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        var posted = false
        var returns = 0
        let task = Task { @MainActor in
            await TextInserter.insert(
                "전체 문장", into: board,
                paste: { posted = true; return true }, submit: { returns += 1; return true }
            )
        }
        while !posted { await Task.yield() }
        task.cancel()
        #expect(await task.value == .cancelled)
        #expect(returns == 0)
        #expect(board.string(forType: .string) == "전체 문장")
    }

    @Test("동시 호출도 준비·붙여넣기·처리 여유·Return 순서가 섞이지 않는다")
    func concurrentInsertsAreSerialized() async {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        var order: [String] = []
        var received: [String] = []
        var readers: [Task<Void, Never>] = []
        var tasks: [Task<TextInserter.Result, Never>] = []
        for index in 0..<3 {
            tasks.append(Task { @MainActor in
                await TextInserter.insert(
                    "문장\(index)", into: board, settleDelay: .milliseconds(40),
                    prepare: { order.append("prepare"); await Task.yield(); return true },
                    paste: {
                        order.append("paste")
                        readers.append(Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(1))
                            received.append(board.string(forType: .string) ?? "")
                            order.append("read")
                        })
                        return true
                    }, submit: { order.append("return"); return true }
                )
            })
        }
        for task in tasks { #expect(await task.value == .posted) }
        for reader in readers { await reader.value }
        #expect(order == ["prepare", "paste", "read", "return", "prepare", "paste", "read", "return", "prepare", "paste", "read", "return"])
        #expect(Set(received) == Set(["문장0", "문장1", "문장2"]))
        #expect(board.string(forType: .string) == received.last)
    }

    @Test("전송 결과가 본문을 노출하지 않고 받아쓰기 로그의 같은 항목에 기록된다", arguments: [true, false])
    func insertionDiagnosticIsWrittenToDictationLog(postSucceeds: Bool) async throws {
        let board = makePasteboard()
        defer { board.releaseGlobally() }
        var diagnostics: [String] = []
        let result = await TextInserter.insert(
            "완성 문장", into: board, settleDelay: .zero,
            onDiagnostic: { diagnostics.append($0) }, paste: { postSucceeds }
        )
        #expect(result == (postSucceeds ? .posted : .eventFailed))
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.contains("완성 문장") == false)
        let entry = DictationLog.entry(
            raw: "원문", outcome: .refined("완성 문장"), recorded: .seconds(1),
            at: Date(), insertion: diagnostics.first.map { "테스트 앱 · " + $0 }
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("insertion-\(UUID()).log")
        defer { try? FileManager.default.removeItem(at: url) }
        try DictationLog.append(entry, to: url)
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved.contains(postSucceeds ? "입력: 테스트 앱 · 전송 완료" : "입력: 테스트 앱 · 키 이벤트 전송 실패"))
        #expect(saved.contains("STT : 원문\n결과: 완성 문장"))
    }

    @Test("대상 앱 미실행도 파일 기록용 진단을 전달한다")
    func missingTargetIncludesDiagnostic() async {
        var diagnostics: [String] = []
        let result = await TargetApp.send(
            "본문", toAppWithBundleID: "test.missing.\(UUID())", pressReturn: false,
            onDiagnostic: { diagnostics.append($0) }
        )
        #expect(result == .notRunning)
        #expect(diagnostics == ["게시 전 중단 · 대상 앱이 실행 중이 아님"])
    }
}
