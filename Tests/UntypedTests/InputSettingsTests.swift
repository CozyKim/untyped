import Foundation
import Testing
@testable import Untyped

struct InputSettingsTests {
    @Test func legacySettingsRetainModifiersAndDefaultSpeechRules() throws {
        let json = #"{"base_url":"http://localhost/v1","model":"m","api_key":"key","hotkey":"right_option","target_app_hotkey":"right_control"}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.hotkey == .modifier(.rightOption))
        #expect(config.targetAppHotkey == .modifier(.rightControl))
        #expect(config.editHotkey == nil)
        #expect(config.literalHotkey == nil)
        #expect(config.voiceCommandRules.editPhrases == ["수정"])
        #expect(config.voiceCommandRules.submitPhrases == ["보내"])
    }

    @Test func chordsAndSeparateVoiceRulesRoundTrip() throws {
        var config = AppConfig.defaultConfig
        config.editHotkey = .chord(ShortcutChord(key: .e, modifiers: [.command, .shift]))
        config.literalHotkey = .chord(ShortcutChord(key: .d, modifiers: [.command, .shift]))
        config.voiceCommandRules.editPhrases = ["고쳐", "수정해"]
        config.voiceCommandRules.submitEnabled = false
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(AppConfig.self, from: data) == config)
        #expect(config.inputValidationError == nil)
        #expect(config.recordingShortcuts[.edit] == config.editHotkey)
        #expect(config.recordingShortcuts[.literal] == config.literalHotkey)
    }

    @Test func conflictingBindingsCannotBeSavedOrInstalledTwice() {
        var config = AppConfig.defaultConfig
        config.editHotkey = config.hotkey
        #expect(config.inputValidationError != nil)
        #expect(config.recordingShortcuts[.edit] == nil)
        config.editHotkey = .chord(ShortcutChord(key: .e, modifiers: [.option, .command]))
        #expect(config.inputValidationError != nil)
        #expect(config.recordingShortcuts[.edit] == nil)
    }

    @Test func invalidOptionalShortcutDoesNotDiscardOtherSettings() throws {
        let json = #"{"base_url":"http://localhost/v1","model":"m","api_key":"keep","edit_hotkey":{"unknown":true},"literal_hotkey":"right_option"}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.apiKey == "keep")
        #expect(config.editHotkey == nil)
        #expect(config.literalHotkey == nil)
    }
}
