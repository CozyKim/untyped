import Foundation
import Testing
@testable import Untyped

struct VoiceCommandRulesTests {
    @Test func submitCannotAlsoMatchAnEditPrefix() {
        let rules = VoiceCommandRules(editPhrases: ["고쳐", "fix"], submitPhrases: ["고쳐 제목을 바꿔", "FIX THIS"])
        #expect(rules.validationError != nil)
        #expect(VoiceCommand.parse("고쳐 제목을 바꿔!", rules: rules) == nil)
        #expect(VoiceCommand.parse("fix this", rules: rules) == nil)
        let distinct = VoiceCommandRules(editPhrases: ["고쳐"], submitPhrases: ["고쳐줘"])
        #expect(distinct.validationError == nil)
        #expect(VoiceCommand.parse("고쳐줘", rules: distinct) == .submit)
    }

    @Test func normalizesWhitespaceAndCaseDuplicatesWithoutChangingPhrases() {
        let rules = VoiceCommandRules(
            editPhrases: ["  ReWrite this \n", "rewrite THIS", "", " \n", "수정"],
            submitPhrases: [" SEND ", "send", "보내"]
        ).normalized
        #expect(rules.editPhrases == ["ReWrite this", "수정"])
        #expect(rules.submitPhrases == ["SEND", "보내"])
        #expect(rules.validationError == nil)
    }

    @Test func rejectsOnlyEmptyActiveLists() {
        #expect(VoiceCommandRules(editPhrases: [" \n"]).validationError != nil)
        #expect(VoiceCommandRules(submitPhrases: []).validationError != nil)
        #expect(VoiceCommandRules(editEnabled: false, editPhrases: []).validationError == nil)
        #expect(VoiceCommandRules(submitEnabled: false, submitPhrases: []).validationError == nil)
    }

    @Test func rejectsSharedActivePhraseCaseInsensitively() {
        #expect(VoiceCommandRules(editPhrases: [" Go "], submitPhrases: ["go"]).validationError != nil)
        #expect(VoiceCommandRules(editEnabled: false, editPhrases: ["go"], submitPhrases: ["GO"]).validationError == nil)
        #expect(VoiceCommandRules(submitEnabled: false, editPhrases: ["go"], submitPhrases: ["GO"]).validationError == nil)
    }

    @Test func sentencePunctuationDoesNotDistinguishActiveRoutes() {
        let rules = VoiceCommandRules(editPhrases: ["수정"], submitPhrases: ["수정!"])
        #expect(rules.validationError != nil)
        for text in ["수정", "수정!", "수정。", "수정 제목을 바꿔"] {
            #expect(VoiceCommand.parse(text, rules: rules) == nil)
        }
    }

    @Test func punctuationOnlyActivePhrasesAreEmptyAndCannotRouteCommands() {
        let editRules = VoiceCommandRules(editPhrases: [" .!?。！？ \n"])
        let submitRules = VoiceCommandRules(submitPhrases: ["!?", "。"])
        #expect(editRules.normalized.editPhrases.isEmpty)
        #expect(submitRules.normalized.submitPhrases.isEmpty)
        #expect(editRules.validationError != nil)
        #expect(submitRules.validationError != nil)
        #expect(VoiceCommand.parse(".!?。！？", rules: editRules) == nil)
        #expect(VoiceCommand.parse("!?", rules: submitRules) == nil)
    }

    @Test func trimsSentencePunctuationButPreservesInternalPunctuationAndInstructions() {
        let rules = VoiceCommandRules(
            editPhrases: [" !? Fix. THIS！？ ", "fix. this", "fix-this!"],
            submitPhrases: ["。SEND!?", "send"]
        )
        #expect(rules.normalized.editPhrases == ["Fix. THIS", "fix-this"])
        #expect(rules.normalized.submitPhrases == ["SEND"])
        #expect(VoiceCommand.parse("FIX. THIS, -1을 ‘1!’로 바꿔.", rules: rules) == .edit("-1을 ‘1!’로 바꿔."))
        #expect(VoiceCommand.parse("fix-this: \"내일?\"을 지워!", rules: rules) == .edit("\"내일?\"을 지워!"))
        #expect(VoiceCommand.parse("send", rules: rules) == .submit)
    }

    @Test func decodesPartialRulesWithDefaultsAndRoundTripsSnakeCase() throws {
        let data = Data(#"{"edit_phrases":["고쳐"]}"#.utf8)
        let rules = try JSONDecoder().decode(VoiceCommandRules.self, from: data)
        #expect(VoiceCommand.parse("고쳐 마지막 문장을 지워", rules: rules) == .edit("마지막 문장을 지워"))
        #expect(VoiceCommand.parse("보내", rules: rules) == .submit)
        let disabled = VoiceCommandRules(editEnabled: false, submitEnabled: false, editPhrases: ["fix"], submitPhrases: ["send"])
        let encoded = try JSONEncoder().encode(disabled)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["edit_enabled"] as? Bool == false)
        #expect(object["submit_enabled"] as? Bool == false)
        #expect(object["edit_phrases"] as? [String] == ["fix"])
        #expect(object["submit_phrases"] as? [String] == ["send"])
        #expect(try JSONDecoder().decode(VoiceCommandRules.self, from: encoded) == disabled)
    }

    @Test func recognizesMultipleStandaloneSubmitPhrases() {
        let rules = VoiceCommandRules(submitPhrases: ["send now", "전송", " SEND "])
        for text in [" send NOW!\n", "전송。", "send", "!?SEND！？"] {
            #expect(VoiceCommand.parse(text, rules: rules) == .submit)
        }
        for text in ["보내", "send now please", "전송해", "자료를 전송", "send,", "send now\nmore"] {
            #expect(VoiceCommand.parse(text, rules: rules) == nil)
        }
    }

    @Test func selectsLongestEditPrefixAndPreservesInstruction() {
        let rules = VoiceCommandRules(editPhrases: ["fix", "fix this", "고쳐"])
        #expect(VoiceCommand.parse(" FIX THIS: -1을 ‘1’로 바꿔. ", rules: rules) == .edit("-1을 ‘1’로 바꿔."))
        #expect(VoiceCommand.parse("고쳐, \"내일\"을 \"오늘\"로!", rules: rules) == .edit("\"내일\"을 \"오늘\"로!"))
        #expect(VoiceCommand.parse("fix this", rules: rules) == .edit(""))
        #expect(VoiceCommand.parse("fix that sentence.", rules: rules) == .edit("that sentence."))
        for text in ["수정 문장", "fixed text", "고쳐줘", "fix-this", "we fix this"] {
            #expect(VoiceCommand.parse(text, rules: rules) == nil)
        }
    }

    @Test func separatelyDisabledCommandsRemainDictation() {
        let noEdit = VoiceCommandRules(editEnabled: false)
        #expect(VoiceCommand.parse("수정 제목을 바꿔", rules: noEdit) == nil)
        #expect(VoiceCommand.parse("보내", rules: noEdit) == .submit)
        let noSubmit = VoiceCommandRules(submitEnabled: false)
        #expect(VoiceCommand.parse("보내!", rules: noSubmit) == nil)
        #expect(VoiceCommand.parse("수정 제목을 바꿔", rules: noSubmit) == .edit("제목을 바꿔"))
        #expect(VoiceCommand.parse("수정 제목을 바꿔", enabled: false, rules: noSubmit) == nil)
        #expect(VoiceCommand.parse("보내", enabled: false, rules: noEdit) == nil)
    }

    @Test func ambiguousActivePhraseNeverSubmitsEvenWhenValidationIsBypassed() {
        let rules = VoiceCommandRules(editPhrases: [" Go "], submitPhrases: ["go", "send"])
        #expect(VoiceCommand.parse("GO!", rules: rules) == nil)
        #expect(VoiceCommand.parse("go change this", rules: rules) == nil)
        #expect(VoiceCommand.parse("send", rules: rules) == .submit)
        #expect(VoiceCommand.parse("go", rules: VoiceCommandRules(editEnabled: false, editPhrases: ["GO"], submitPhrases: ["go"])) == .submit)
    }
}
