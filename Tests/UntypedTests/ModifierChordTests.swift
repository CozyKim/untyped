import Foundation
import Testing
@testable import Untyped

struct ModifierChordTests {
    @Test func refusedTargetPromotionDiscardsTheProvisionalRecording() {
        let now = ContinuousClock.now
        let (cancelled, effect) = reduce(
            .holding(since: now, route: .frontmost), .keyDown, from: .targetApp,
            now: now, threshold: .zero, promoting: true, promotionAllowed: false
        )
        #expect(cancelled == .processing)
        #expect(effect == .discardCapture)
        let (stillCancelled, ignored) = reduce(cancelled, .keyUp, from: .frontmost, now: now, threshold: .zero)
        #expect(stillCancelled == .processing)
        #expect(ignored == .none)
    }

    private let pair = ModifierChord(keys: [.leftShift, .rightCommand])

    @Test func retainsPhysicalSidesAndRoundTrips() throws {
        let shortcut = KeyboardShortcut.modifierChord(pair)
        let data = try JSONEncoder().encode(shortcut)
        #expect(try JSONDecoder().decode(KeyboardShortcut.self, from: data) == shortcut)
        #expect(shortcut.isValid)
        #expect(shortcut.displayName.contains("오른쪽 ⌘"))
        #expect(shortcut.displayName.contains("왼쪽 ⇧"))
        #expect(!KeyboardShortcut.modifierChord(.init(keys: [.rightCommand])).isValid)
    }

    @Test func onlyMatchingPhysicalModifiersActivateTheChord() {
        let correct = HotkeyKey.leftShift.deviceMask | HotkeyKey.rightCommand.deviceMask
        #expect(pair.isHeld(modifierFlags: correct))
        #expect(!pair.isHeld(modifierFlags: HotkeyKey.leftShift.deviceMask | HotkeyKey.leftCommand.deviceMask))
        #expect(!pair.isHeld(modifierFlags: HotkeyKey.rightCommand.deviceMask))
        #expect(pair.isHeld(modifierFlags: correct | HotkeyKey.leftOption.deviceMask))
    }

    @Test func recordingUpgradesFromModifierPairToOrdinaryChord() {
        var recorder = ShortcutRecordingState()
        let flags = HotkeyKey.leftShift.deviceMask | HotkeyKey.rightCommand.deviceMask
        _ = recorder.handle(.flagsChanged(HotkeyKey.leftShift.keyCode, modifiers: HotkeyKey.leftShift.deviceMask))
        #expect(recorder.handle(.flagsChanged(HotkeyKey.rightCommand.keyCode, modifiers: flags)) == .pending(.modifierChord(pair)))
        #expect(recorder.handle(.keyDown(14, modifiers: flags, isRepeat: false)) == .pending(.chord(.init(key: .e, modifiers: [.command, .shift]))))
        _ = recorder.handle(.keyUp(14, modifiers: flags))
        #expect(recorder.handle(.flagsChanged(HotkeyKey.leftShift.keyCode, modifiers: 0)) == .captured(.chord(.init(key: .e, modifiers: [.command, .shift]))))
    }

    @Test func capturesModifierOnlyChordWhenAllKeysAreReleased() {
        var recorder = ShortcutRecordingState()
        let flags = HotkeyKey.leftShift.deviceMask | HotkeyKey.rightCommand.deviceMask
        _ = recorder.handle(.flagsChanged(HotkeyKey.rightCommand.keyCode, modifiers: HotkeyKey.rightCommand.deviceMask))
        _ = recorder.handle(.flagsChanged(HotkeyKey.leftShift.keyCode, modifiers: flags))
        #expect(recorder.handle(.flagsChanged(HotkeyKey.leftShift.keyCode, modifiers: HotkeyKey.rightCommand.deviceMask)) == .waiting)
        #expect(recorder.handle(.flagsChanged(HotkeyKey.rightCommand.keyCode, modifiers: 0)) == .captured(.modifierChord(pair)))
    }

    @Test func tracksAThirdModifierAndAllowsCancellation() {
        var recorder = ShortcutRecordingState()
        let first = HotkeyKey.rightCommand.deviceMask
        let second = first | HotkeyKey.leftShift.deviceMask
        let third = second | HotkeyKey.leftControl.deviceMask
        _ = recorder.handle(.flagsChanged(HotkeyKey.rightCommand.keyCode, modifiers: first))
        _ = recorder.handle(.flagsChanged(HotkeyKey.leftShift.keyCode, modifiers: second))
        #expect(recorder.handle(.flagsChanged(HotkeyKey.leftControl.keyCode, modifiers: third))
            == .pending(.modifierChord(.init(keys: [.rightCommand, .leftShift, .leftControl]))))
        #expect(recorder.requestCancellation() == .waiting)
        #expect(recorder.handle(.flagsChanged(HotkeyKey.rightCommand.keyCode, modifiers: 0)) == .cancelled)
    }

    @Test func modifierChordMayCoexistWithItsStandaloneKeys() {
        let chord = KeyboardShortcut.modifierChord(pair)
        #expect(!chord.conflicts(with: .rightCommand))
        #expect(!chord.conflicts(with: .leftShift))
        #expect(chord.conflicts(with: chord))
        #expect(chord.canPromote(from: .rightCommand))
        #expect(!chord.canPromote(from: .leftCommand))
        #expect(!KeyboardShortcut.rightCommand.canPromote(from: chord))
        var config = AppConfig.defaultConfig
        config.hotkey = .rightCommand
        config.targetAppHotkey = .rightShift
        config.editHotkey = .modifierChord(.init(keys: [.rightShift, .rightCommand]))
        #expect(config.inputValidationError == nil)
        #expect(config.recordingShortcuts[.edit] == config.editHotkey)
    }

    @Test func moreSpecificModifierChordPromotesAProvisionalRecording() {
        let now = ContinuousClock.now
        let initial = DictationState.holding(since: now, route: .frontmost)
        let (promoted, effect) = reduce(initial, .keyDown, from: .edit, now: now, threshold: .zero, promoting: true)
        #expect(promoted == .holding(since: now, route: .edit))
        #expect(effect == .changeCaptureIntent)
        let (unchanged, ignored) = reduce(promoted, .keyUp, from: .frontmost, now: now, threshold: .zero)
        #expect(unchanged == promoted)
        #expect(ignored == .none)
        let (finished, stop) = reduce(promoted, .keyUp, from: .edit, now: now, threshold: .zero)
        #expect(finished == .processing)
        #expect(stop == .stopCaptureAndProcess(.edit))
    }
}
