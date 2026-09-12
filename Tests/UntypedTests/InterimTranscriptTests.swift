import Testing
@testable import Untyped

// 잠정 결과는 "아직 확정되지 않은 구간 전체"를 매번 새로 보내오므로 앞의 잠정 텍스트를 대체한다.
@Test func volatileResultReplacesPreviousVolatile() {
    var transcript = InterimTranscript()
    transcript.add("오늘", isFinal: false)
    transcript.add("오늘 오후에", isFinal: false)
    #expect(transcript.text == "오늘 오후에")
}

// 확정 결과가 오면 그 구간은 확정 텍스트 뒤에 붙고, 같은 구간을 가리키던 잠정 텍스트는 비운다.
@Test func finalResultAppendsAndClearsVolatile() {
    var transcript = InterimTranscript()
    transcript.add("오늘 오후에 회의가", isFinal: false)
    transcript.add("오늘 오후에 회의가 있어요.", isFinal: true)
    #expect(transcript.text == "오늘 오후에 회의가 있어요.")
    #expect(transcript.finalized == "오늘 오후에 회의가 있어요.")
}

// 미리보기 = 확정 + 잠정. 확정 뒤에 새 구간의 잠정 결과가 이어진다.
@Test func previewIsFinalizedFollowedByVolatile() {
    var transcript = InterimTranscript()
    transcript.add("먼저 시작하세요.", isFinal: true)
    transcript.add(" 그리고", isFinal: false)
    transcript.add(" 그리고 내일", isFinal: false)
    #expect(transcript.text == "먼저 시작하세요. 그리고 내일")
    #expect(transcript.finalized == "먼저 시작하세요.")
}

@Test func emptyTranscriptHasEmptyText() {
    #expect(InterimTranscript().text == "")
}
