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

@Test func entryWithoutRawMarksAudioPathAndOmitsSTTLine() {
    // 오디오를 한 요청으로 다듬으면 원문이 없다. 빈 STT 줄 대신 헤더에 경로를 남긴다.
    let entry = DictationLog.entry(
        raw: nil, outcome: .refined("오늘 저녁에."),
        recorded: .milliseconds(7_240), at: fixedDate, timeZone: seoul
    )
    #expect(entry == """
    [2026-09-11 22:10:33] 녹음 7.2초 · 오디오에서 바로 다듬음
    결과: 오늘 저녁에.

    """)
}

@Test func failureEntryHasHeaderAndCauseButNoTextLines() {
    // 오디오 다듬기가 실패하면 원문도 결과도 없다. 헤더와 원인만 남기고 빈 STT 줄을 만들지 않는다.
    let entry = DictationLog.failureEntry(
        label: "다듬기 서버 오류", recorded: .milliseconds(7_240), at: fixedDate, timeZone: seoul,
        cause: "HTTP 400"
    )
    #expect(entry == "[2026-09-11 22:10:33] 녹음 7.2초 · 삽입 안 함 (다듬기 서버 오류)\n원인: HTTP 400\n")
    let noCause = DictationLog.failureEntry(
        label: "다듬기 결과 없음", recorded: .seconds(3), at: fixedDate, timeZone: seoul
    )
    #expect(noCause == "[2026-09-11 22:10:33] 녹음 3.0초 · 삽입 안 함 (다듬기 결과 없음)\n")
}

// MARK: - 소요 시간

@Test func timingLineDistinguishesSTTFromRefinement() {
    // 2단계 — 키를 뗀 뒤 최종 전사까지(STT)와 LLM 다듬기 요청을 따로 적는다.
    #expect(DictationTiming.apple(transcription: .milliseconds(320), refinement: .milliseconds(1_460)).line
        == "STT 0.3초 · 다듬기 1.5초")
    // 1단계 — 오디오를 보낸 LLM 요청 하나뿐이다.
    #expect(DictationTiming.llmAudio(request: .milliseconds(3_060)).line == "오디오 다듬기 3.1초")
}

@Test func entryPutsTimingRightAfterHeaderAndBeforeCause() {
    let entry = DictationLog.entry(
        raw: "원문", outcome: .fallback("원문", .timeout),
        recorded: .seconds(7), at: fixedDate, timeZone: seoul,
        cause: "다듬기 응답이 6.8초 안에 없음",
        timing: .apple(transcription: .milliseconds(280), refinement: .milliseconds(6_810))
    )
    #expect(entry == """
    [2026-09-11 22:10:33] 녹음 7.0초 · 원본 (다듬기 시간 초과)
    소요: STT 0.3초 · 다듬기 6.8초
    원인: 다듬기 응답이 6.8초 안에 없음
    STT : 원문
    결과: 원문

    """)
}

@Test func audioEntryAndFailureEntryCarryRequestTiming() {
    let refined = DictationLog.entry(
        raw: nil, outcome: .refined("오늘 저녁에."),
        recorded: .milliseconds(7_240), at: fixedDate, timeZone: seoul,
        timing: .llmAudio(request: .milliseconds(2_140))
    )
    #expect(refined == """
    [2026-09-11 22:10:33] 녹음 7.2초 · 오디오에서 바로 다듬음
    소요: 오디오 다듬기 2.1초
    결과: 오늘 저녁에.

    """)
    let failed = DictationLog.failureEntry(
        label: "다듬기 서버 오류", recorded: .milliseconds(7_240), at: fixedDate, timeZone: seoul,
        cause: "HTTP 400", timing: .llmAudio(request: .milliseconds(90))
    )
    #expect(failed == "[2026-09-11 22:10:33] 녹음 7.2초 · 삽입 안 함 (다듬기 서버 오류)\n소요: 오디오 다듬기 0.1초\n원인: HTTP 400\n")
}

@Test func entriesWithoutTimingKeepTheOldFormat() {
    // timing을 안 주면 이전 형식 그대로다 — 기존 로그를 읽는 쪽이 깨지지 않는다.
    let entry = DictationLog.entry(
        raw: "원문", outcome: .refined("결과"), recorded: .seconds(3), at: fixedDate, timeZone: seoul
    )
    #expect(entry == "[2026-09-11 22:10:33] 녹음 3.0초 · 다듬음\nSTT : 원문\n결과: 결과\n")
}
