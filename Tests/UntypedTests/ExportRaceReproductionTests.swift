import AppKit
import Testing
@testable import Untyped

/// 실제 NSPasteboard와 기존 삽입 경로를 사용하며 수신 앱의 읽기 지연만 제어한다.
@Suite(.serialized)
@MainActor
struct ExportRaceReproductionTests {
    @Test func alternatingFastAndDelayedReads50Cycles() async throws {
        for cycle in 0..<50 {
            let board = NSPasteboard(name: .init("ExportRace-\(UUID().uuidString)"))
            defer { board.releaseGlobally() }
            let original = "이전 원본 어 음 \(cycle)"
            let refined = "정리된 전체 문장 \(cycle) ✅\n마지막 줄"
            board.clearContents()
            board.setString(original, forType: .string)
            let start = ContinuousClock.now
            var received: String? = ""
            var reader: Task<Void, Never>?
            let result = await TextInserter.insert(refined, into: board, targetValue: { received }) {
                print("TRACE cycle=\(cycle) boundary=post value=\(String(reflecting: board.string(forType: .string))) count=\(board.changeCount)")
                reader = Task { @MainActor in
                    try? await Task.sleep(for: cycle.isMultiple(of: 2) ? .milliseconds(20) : .milliseconds(1150))
                    let value = board.string(forType: .string)
                    print("TRACE cycle=\(cycle) boundary=read elapsed=\(ContinuousClock.now - start) value=\(String(reflecting: value)) count=\(board.changeCount)")
                    received = value
                }
                return true
            }
            await reader?.value
            #expect(result == .inserted)
            #expect(board.string(forType: .string) == original)
            #expect(received == refined)
        }
    }
}
