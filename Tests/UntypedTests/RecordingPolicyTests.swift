import Foundation
import Testing
@testable import Untyped

struct RecordingPolicyTests {
    @Test func literalRouteNeverRecognizesCommandsOrSubmits() {
        let policy = RecordingPolicy(route: .literal, commandsEnabled: true, rules: .init())
        #expect(policy.command(for: "보내") == nil)
        #expect(policy.command(for: "수정, 내일을 오늘로") == nil)
        #expect(!policy.needsRawAudio)
        #expect(!policy.permitsAutomaticReturn)
        #expect(RecordingRoute.literal.destination == .frontmost)
    }

    @Test func editRouteRequiresNoCommandAndCannotSubmit() {
        let policy = RecordingPolicy(route: .edit, commandsEnabled: false, rules: .init())
        #expect(policy.command(for: "내일을 오늘로 바꿔") == .edit("내일을 오늘로 바꿔"))
        #expect(policy.command(for: "보내") == .edit("보내"))
        #expect(policy.needsRawAudio)
        #expect(!policy.permitsAutomaticReturn)
        #expect(RecordingRoute.edit.destination == .frontmost)
    }

    @Test func automaticRulesAreSnapshottedPerRecording() {
        var rules = VoiceCommandRules()
        rules.editPhrases = ["고쳐"]
        let policy = RecordingPolicy(route: .frontmost, commandsEnabled: true, rules: rules)
        rules.editPhrases = ["수정"]
        #expect(policy.command(for: "고쳐, 마지막 문장을 지워") == .edit("마지막 문장을 지워"))
        #expect(policy.command(for: "수정, 마지막 문장을 지워") == nil)
        #expect(policy.command(for: "보내") == .submit)
        #expect(policy.permitsAutomaticReturn)
    }

    @Test func disabledRecognitionKeepsWordsAsDictation() {
        let policy = RecordingPolicy(route: .targetApp, commandsEnabled: false, rules: .init())
        #expect(policy.command(for: "보내") == nil)
        #expect(!policy.needsRawAudio)
        #expect(RecordingRoute.targetApp.destination == .targetApp)
    }

    @Test func unrelatedRecordingKeysCannotEndAnEditSession() {
        let now = ContinuousClock.now
        let (state, _) = reduce(.idle, .keyDown, from: .edit, now: now, threshold: .zero)
        let (unchanged, effect) = reduce(state, .keyUp, from: .literal, now: now, threshold: .zero)
        #expect(unchanged == state)
        #expect(effect == .none)
        let (processing, stop) = reduce(state, .keyUp, from: .edit, now: now, threshold: .zero)
        #expect(processing == .processing)
        #expect(stop == .stopCaptureAndProcess(.edit))
    }
}
