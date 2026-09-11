import AppKit
import Testing
@testable import Untyped

/// 복원 예약이 전역 상태(직전 삽입의 복원 작업)를 공유하므로 병렬 실행하면 서로 간섭한다.
@Suite(.serialized)
@MainActor
struct TextInserterTests {
    /// 시스템 클립보드를 건드리지 않도록 매 테스트마다 고유한 이름의 pasteboard를 쓴다.
    private func makePasteboard(containing text: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("TextInserterTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard
    }

    /// Chromium·Electron 계열 앱은 붙여넣기가 렌더러↔브라우저 프로세스 IPC를 거쳐
    /// 클립보드를 늦게 읽는다. 그 시점에 이미 복원돼 있으면 옛 내용이 붙여넣어진다.
    @Test("붙여넣기가 늦은 앱도 새 텍스트를 읽고, 그 뒤에 원본이 복원된다")
    func slowPasteReadsNewTextThenOriginalIsRestored() async throws {
        let pasteboard = makePasteboard(containing: "원본")

        await TextInserter.insert("받아쓰기", into: pasteboard, paste: {})

        try await Task.sleep(for: .milliseconds(500))
        #expect(pasteboard.string(forType: .string) == "받아쓰기")

        try await Task.sleep(for: TextInserter.restoreDelay)
        #expect(pasteboard.string(forType: .string) == "원본")
    }

    @Test("복원 전에 다른 곳에서 클립보드를 바꾸면 덮어쓰지 않는다")
    func externalChangeIsNotOverwritten() async throws {
        let pasteboard = makePasteboard(containing: "원본")

        await TextInserter.insert("받아쓰기", into: pasteboard, paste: {})
        pasteboard.clearContents()
        pasteboard.setString("사용자가 새로 복사한 것", forType: .string)

        try await Task.sleep(for: TextInserter.restoreDelay + .milliseconds(200))
        #expect(pasteboard.string(forType: .string) == "사용자가 새로 복사한 것")
    }

    /// 복원이 아직 남은 채로 다음 삽입이 스냅샷을 뜨면 직전 받아쓰기 텍스트를
    /// 원본으로 오인해 사용자의 클립보드가 영영 사라진다.
    @Test("복원 대기 중에 다시 삽입해도 원래 클립보드가 보존된다")
    func consecutiveInsertsPreserveOriginal() async throws {
        let pasteboard = makePasteboard(containing: "원본")

        await TextInserter.insert("첫 번째", into: pasteboard, paste: {})
        await TextInserter.insert("두 번째", into: pasteboard, paste: {})
        #expect(pasteboard.string(forType: .string) == "두 번째")

        try await Task.sleep(for: TextInserter.restoreDelay + .milliseconds(200))
        #expect(pasteboard.string(forType: .string) == "원본")
    }
}
