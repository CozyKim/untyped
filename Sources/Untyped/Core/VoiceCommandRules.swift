import Foundation

struct VoiceCommandRules: Codable, Equatable, Sendable {
    var editEnabled: Bool = true
    var submitEnabled: Bool = true
    var editPhrases: [String] = ["수정"]
    var submitPhrases: [String] = ["보내"]

    init(
        editEnabled: Bool = true,
        submitEnabled: Bool = true,
        editPhrases: [String] = ["수정"],
        submitPhrases: [String] = ["보내"]
    ) {
        self.editEnabled = editEnabled
        self.submitEnabled = submitEnabled
        self.editPhrases = editPhrases
        self.submitPhrases = submitPhrases
    }

    enum CodingKeys: String, CodingKey {
        case editEnabled = "edit_enabled"
        case submitEnabled = "submit_enabled"
        case editPhrases = "edit_phrases"
        case submitPhrases = "submit_phrases"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        editEnabled = try container.decodeIfPresent(Bool.self, forKey: .editEnabled) ?? true
        submitEnabled = try container.decodeIfPresent(Bool.self, forKey: .submitEnabled) ?? true
        editPhrases = try container.decodeIfPresent([String].self, forKey: .editPhrases) ?? ["수정"]
        submitPhrases = try container.decodeIfPresent([String].self, forKey: .submitPhrases) ?? ["보내"]
    }

    var normalized: Self {
        var result = self
        result.editPhrases = Self.normalize(editPhrases)
        result.submitPhrases = Self.normalize(submitPhrases)
        return result
    }

    var validationError: String? {
        let rules = normalized
        if rules.editEnabled && rules.editPhrases.isEmpty {
            return "수정 명령을 켜려면 명령 문구를 하나 이상 입력하세요."
        }
        if rules.submitEnabled && rules.submitPhrases.isEmpty {
            return "보내기 명령을 켜려면 명령 문구를 하나 이상 입력하세요."
        }
        if rules.editEnabled && rules.submitEnabled {
            if rules.submitPhrases.contains(where: { submit in
                rules.editPhrases.contains(where: { Self.editInstruction(in: submit, after: $0) != nil })
            }) {
                return "수정과 보내기로 동시에 해석되는 명령어를 사용할 수 없습니다. 전송 문구를 수정 명령어와 구분해 주세요."
            }
        }
        return nil
    }

    static func phraseKey(_ phrase: String) -> String {
        phrase.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// 검증과 실제 인식이 같은 경계를 사용해야 전송이 수정 지시를 가로채지 않는다.
    static func editInstruction(in text: String, after phrase: String) -> String? {
        let locale = Locale(identifier: "en_US_POSIX")
        guard let range = text.range(of: phrase, options: [.anchored, .caseInsensitive], locale: locale) else { return nil }
        let rest = String(text[range.upperBound...])
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.:;!?，。：；！？"))
        guard rest.isEmpty || rest.unicodeScalars.first.map(separators.contains) == true else { return nil }
        return String(rest.unicodeScalars.drop(while: separators.contains)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalize(_ phrases: [String]) -> [String] {
        var seen: Set<String> = []
        return phrases.compactMap { phrase in
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?。！？")))
            guard !trimmed.isEmpty, seen.insert(phraseKey(trimmed)).inserted else { return nil }
            return trimmed
        }
    }
}
