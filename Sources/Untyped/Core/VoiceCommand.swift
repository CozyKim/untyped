import Foundation

/// 명령의 위치와 경계를 명시한다. 본문 속의 '보내'나 '수정사항'은 받아쓰기다.
enum VoiceCommand: Equatable, Sendable {
    case edit(String)
    case submit

    static func parse(_ text: String, enabled: Bool = true, rules: VoiceCommandRules = .init()) -> Self? {
        guard enabled else { return nil }
        let rules = rules.normalized
        let whitespace = CharacterSet.whitespacesAndNewlines
        let sentenceEnd = CharacterSet(charactersIn: ".!?。！？")
        let trimmed = text.trimmingCharacters(in: whitespace)
        let editPhrases = rules.editEnabled ? rules.editPhrases : []
        let submitPhrases = rules.submitEnabled ? rules.submitPhrases : []
        let ambiguous = Set(editPhrases.map(VoiceCommandRules.phraseKey))
            .intersection(submitPhrases.map(VoiceCommandRules.phraseKey))
        let locale = Locale(identifier: "en_US_POSIX")
        for phrase in submitPhrases {
            guard let range = trimmed.range(of: phrase, options: .caseInsensitive, locale: locale) else { continue }
            let surroundings = String(trimmed[..<range.lowerBound]) + String(trimmed[range.upperBound...])
            guard surroundings.trimmingCharacters(in: whitespace.union(sentenceEnd)).isEmpty else { continue }
            guard !editPhrases.contains(where: { VoiceCommandRules.editInstruction(in: phrase, after: $0) != nil }) else { return nil }
            return .submit
        }
        // 구분 문장부호만 제거한다. 지시의 음수 부호·따옴표 등은 내용이다.
        for phrase in editPhrases.sorted(by: { $0.count > $1.count }) {
            guard let instruction = VoiceCommandRules.editInstruction(in: trimmed, after: phrase) else { continue }
            guard !ambiguous.contains(VoiceCommandRules.phraseKey(phrase)) else { return nil }
            return .edit(instruction)
        }
        return nil
    }
}
