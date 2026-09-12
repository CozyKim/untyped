/// 미리보기용 전사 결과를 확정 텍스트와 잠정 텍스트로 나눠 쌓는다.
/// 잠정 결과는 아직 확정되지 않은 구간 전체를 매번 새로 보내오므로 대체하고, 확정 결과는
/// 뒤에 붙인 뒤 잠정 텍스트를 비운다 — 확정된 구간을 잠정 텍스트가 한 번 더 말하면 안 된다.
struct InterimTranscript {
    private(set) var finalized = ""
    private var volatile = ""

    /// 화면에 보여줄 텍스트. 확정 뒤에 잠정이 이어진다.
    var text: String { finalized + volatile }

    mutating func add(_ text: String, isFinal: Bool) {
        if isFinal {
            finalized += text
            volatile = ""
        } else {
            volatile = text
        }
    }
}
