import Testing
@testable import Untyped

struct ShortcutRecordingTests {
    @Test func holdingARecordedChordDoesNotFinishBeforeRelease() {
        var recorder = ShortcutRecordingState()
        let flags = ShortcutModifiers.command.rawValue
        #expect(recorder.handle(.keyDown(9, modifiers: flags, isRepeat: false)) == .pending(.chord(.init(key: .v, modifiers: .command))))
        for _ in 0..<5 {
            #expect(recorder.handle(.keyDown(9, modifiers: flags, isRepeat: true)) == .waiting)
        }
        #expect(recorder.handle(.flagsChanged(HotkeyKey.leftCommand.keyCode, modifiers: 0)) == .waiting)
        #expect(recorder.handle(.keyUp(9, modifiers: 0)) == .captured(.chord(.init(key: .v, modifiers: .command))))
    }

    @Test func escapeAndCancelDrainHeldKeysWithoutChangingTheBinding() {
        var recorder = ShortcutRecordingState()
        let flags = ShortcutModifiers.command.rawValue
        _ = recorder.handle(.keyDown(9, modifiers: flags, isRepeat: false))
        #expect(recorder.requestCancellation() == .waiting)
        #expect(recorder.handle(.keyDown(9, modifiers: flags, isRepeat: true)) == .waiting)
        #expect(recorder.handle(.keyUp(9, modifiers: 0)) == .cancelled)
        var escape = ShortcutRecordingState()
        _ = escape.handle(.keyDown(9, modifiers: flags, isRepeat: false))
        _ = escape.handle(.keyDown(53, modifiers: flags, isRepeat: false))
        #expect(escape.handle(.keyUp(53, modifiers: flags)) == .waiting)
        #expect(escape.handle(.keyUp(9, modifiers: 0)) == .cancelled)
    }

    @Test func twoPhysicalModifiersRetainBothSidesInAModifierChord() {
        var recorder = ShortcutRecordingState()
        let left = HotkeyKey.leftCommand
        let right = HotkeyKey.rightCommand
        _ = recorder.handle(.flagsChanged(left.keyCode, modifiers: left.deviceMask))
        _ = recorder.handle(.flagsChanged(right.keyCode, modifiers: left.deviceMask | right.deviceMask))
        #expect(recorder.handle(.flagsChanged(left.keyCode, modifiers: right.deviceMask)) == .waiting)
        #expect(recorder.handle(.flagsChanged(right.keyCode, modifiers: 0)) == .captured(.modifierChord(.init(keys: [left, right]))))
    }

    @Test func recordsThePhysicalKeyAndAllModifiers() {
        var recorder = ShortcutRecordingState()
        #expect(recorder.handle(.keyDown(14, modifiers: ShortcutModifiers([.command, .shift]).rawValue, isRepeat: false))
            == .pending(.chord(.init(key: .e, modifiers: [.command, .shift]))))
        #expect(recorder.handle(.keyUp(14, modifiers: ShortcutModifiers([.command, .shift]).rawValue)) == .waiting)
        #expect(recorder.handle(.flagsChanged(HotkeyKey.leftShift.keyCode, modifiers: 0))
            == .captured(.chord(.init(key: .e, modifiers: [.command, .shift]))))
    }

    @Test func preservesLeftRightStandaloneModifiers() {
        for key in HotkeyKey.allCases {
            var recorder = ShortcutRecordingState()
            #expect(recorder.handle(.flagsChanged(key.keyCode, modifiers: key.deviceMask)) == .waiting)
            #expect(recorder.handle(.flagsChanged(key.keyCode, modifiers: 0)) == .captured(.modifier(key)))
        }
    }

    @Test func recordsModifierChordRatherThanItsLastReleasedStandaloneKey() {
        var recorder = ShortcutRecordingState()
        _ = recorder.handle(.flagsChanged(HotkeyKey.leftCommand.keyCode, modifiers: HotkeyKey.leftCommand.deviceMask))
        _ = recorder.handle(.flagsChanged(HotkeyKey.leftShift.keyCode, modifiers: HotkeyKey.leftCommand.deviceMask | HotkeyKey.leftShift.deviceMask))
        #expect(recorder.handle(.flagsChanged(HotkeyKey.leftShift.keyCode, modifiers: HotkeyKey.leftCommand.deviceMask)) == .waiting)
        #expect(recorder.handle(.flagsChanged(HotkeyKey.leftCommand.keyCode, modifiers: 0)) == .captured(.modifierChord(.init(keys: [.leftCommand, .leftShift]))))
    }

    @Test func invalidKeyDoesNotBecomeABareModifierOnRelease() {
        var recorder = ShortcutRecordingState()
        _ = recorder.handle(.flagsChanged(HotkeyKey.leftCommand.keyCode, modifiers: HotkeyKey.leftCommand.deviceMask))
        #expect(recorder.handle(.keyDown(53, modifiers: ShortcutModifiers.command.rawValue, isRepeat: false)) == .waiting)
        #expect(recorder.handle(.keyUp(53, modifiers: 0)) == .cancelled)
        var invalid = ShortcutRecordingState()
        _ = invalid.handle(.flagsChanged(HotkeyKey.leftCommand.keyCode, modifiers: HotkeyKey.leftCommand.deviceMask))
        if case .invalid = invalid.handle(.keyDown(123, modifiers: ShortcutModifiers.command.rawValue, isRepeat: false)) {}
        else { Issue.record("지원하지 않는 키 안내가 필요하다") }
        #expect(invalid.handle(.flagsChanged(HotkeyKey.leftCommand.keyCode, modifiers: 0)) == .waiting)
    }

    @Test func rejectsPlainTypingAndIgnoresAutorepeat() {
        var recorder = ShortcutRecordingState()
        if case .invalid = recorder.handle(.keyDown(14, modifiers: 0, isRepeat: false)) {}
        else { Issue.record("일반 글자는 단축키로 등록하면 안 된다") }
        #expect(recorder.handle(.keyDown(14, modifiers: ShortcutModifiers.command.rawValue, isRepeat: true)) == .waiting)
        #expect(recorder.handle(.keyDown(53, modifiers: 0, isRepeat: false)) == .waiting)
        #expect(recorder.handle(.keyUp(53, modifiers: 0)) == .waiting)
        #expect(recorder.handle(.keyUp(14, modifiers: 0)) == .cancelled)
    }

    @Test func capsLockAndDeviceBitsDoNotBecomeChordModifiers() {
        var recorder = ShortcutRecordingState()
        let flags = ShortcutModifiers.command.rawValue | HotkeyKey.leftCommand.deviceMask | (1 << 16)
        #expect(recorder.handle(.keyDown(2, modifiers: flags, isRepeat: false)) == .pending(.chord(.init(key: .d, modifiers: .command))))
        #expect(recorder.handle(.keyUp(2, modifiers: 1 << 16)) == .captured(.chord(.init(key: .d, modifiers: .command))))
    }

    @Test @MainActor func coordinatorAllowsOnlyOneCaptureAndRestoresAfterCancel() {
        let coordinator = Coordinator(config: .defaultConfig)
        #expect(coordinator.beginShortcutCapture())
        #expect(!coordinator.beginShortcutCapture())
        coordinator.endShortcutCapture()
        #expect(coordinator.beginShortcutCapture())
        coordinator.endShortcutCapture()
        #expect(coordinator.config == .defaultConfig)
    }
}
