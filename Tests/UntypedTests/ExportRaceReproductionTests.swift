import AppKit
import Testing
@testable import Untyped

/// 실제 NSPasteboard를 사용해 게시 이후 늦게 읽는 앱에도 보낸 텍스트가 남는지 확인한다.
@Suite(.serialized)
@MainActor
struct ExportRaceReproductionTests {
    @Test("게시 직후와 1초 넘게 지난 뒤 모두 새 문장을 읽는다", arguments: [20, 1150])
    func delayedReadsKeepPostedText(delayMilliseconds: Int) async {
        let board = NSPasteboard(name: .init("ExportRace-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let refined = "정리된 전체 문장 ✅\n마지막 줄"
        board.clearContents()
        board.setString("이전 원본 어 음", forType: .string)
        var received: String?
        var reader: Task<Void, Never>?
        let result = await TextInserter.insert(refined, into: board) {
            reader = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
                received = board.string(forType: .string)
            }
            return true
        }
        await reader?.value
        #expect(result == .posted)
        #expect(board.string(forType: .string) == refined)
        #expect(received == refined)
    }
}
