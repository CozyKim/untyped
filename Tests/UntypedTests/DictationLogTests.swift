import Testing
import Foundation
@testable import Untyped

private let seoul = TimeZone(identifier: "Asia/Seoul")!
private let fixedDate: Date = {
    var components = DateComponents()
    components.year = 2026; components.month = 9; components.day = 11
    components.hour = 22; components.minute = 10; components.second = 33
    components.timeZone = seoul
    return Calendar(identifier: .gregorian).date(from: components)!
}()

private func temporaryLogURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("UntypedTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("dictation.log", isDirectory: false)
}

@Test func entryFormatsRefinedResult() {
    let entry = DictationLog.entry(
        raw: "어 내일 아침에 아니 오늘 저녁에", outcome: .refined("오늘 저녁에."),
        recorded: .milliseconds(7_240), at: fixedDate, timeZone: seoul
    )
    #expect(entry == """
    [2026-09-11 22:10:33] 녹음 7.2초 · 다듬음
    STT : 어 내일 아침에 아니 오늘 저녁에
    결과: 오늘 저녁에.

    """)
}

@Test func entryMarksFallbackWithReason() {
    let entry = DictationLog.entry(
        raw: "원문", outcome: .fallback("원문", .truncated),
        recorded: .seconds(41), at: fixedDate, timeZone: seoul
    )
    #expect(entry.hasPrefix("[2026-09-11 22:10:33] 녹음 41.0초 · 원본 (최대 토큰 초과)\n"))
    #expect(entry.contains("결과: 원문\n"))
}

@Test func appendCreatesOwnerOnlyFileAndKeepsAppending() throws {
    let url = temporaryLogURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try DictationLog.append("첫 줄\n", to: url)
    try DictationLog.append("둘째 줄\n", to: url)

    #expect(try String(contentsOf: url, encoding: .utf8) == "첫 줄\n둘째 줄\n")
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect(attributes[.posixPermissions] as? Int == 0o600)
}

@Test func entryAddsCauseLineAfterHeader() {
    let entry = DictationLog.entry(
        raw: "원문", outcome: .fallback("원문", .timeout),
        recorded: .seconds(7), at: fixedDate, timeZone: seoul,
        cause: "콜드 스타트 — 예열 요청이 9.3초째 응답 없음(모델 로드 중). 대기 상한 6.8초"
    )
    #expect(entry == """
    [2026-09-11 22:10:33] 녹음 7.0초 · 원본 (다듬기 시간 초과)
    원인: 콜드 스타트 — 예열 요청이 9.3초째 응답 없음(모델 로드 중). 대기 상한 6.8초
    STT : 원문
    결과: 원문

    """)
}

@Test func entryWithoutCauseIsUnchanged() {
    // 다듬은 경우와 원인 줄이 없는 폴백은 이전 형식 그대로다.
    let entry = DictationLog.entry(
        raw: "원문", outcome: .fallback("원문", .truncated),
        recorded: .seconds(41), at: fixedDate, timeZone: seoul, cause: nil
    )
    #expect(entry == """
    [2026-09-11 22:10:33] 녹음 41.0초 · 원본 (최대 토큰 초과)
    STT : 원문
    결과: 원문

    """)
}

@Test func rotatesWhenFileReachesLimit() throws {
    let url = temporaryLogURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try DictationLog.append("0123456789", to: url, maxBytes: 10)

    // 이미 한계에 닿은 파일은 .1로 밀려나고 새 파일이 시작된다.
    try DictationLog.append("새 파일", to: url, maxBytes: 10)

    #expect(try String(contentsOf: url, encoding: .utf8) == "새 파일")
    let rotated = url.appendingPathExtension("1")
    #expect(try String(contentsOf: rotated, encoding: .utf8) == "0123456789")
}
