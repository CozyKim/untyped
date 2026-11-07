import Foundation

/// 설정 창에서 실제로 누른 키를 하나의 단축키로 바꾼다.
struct ShortcutRecordingState {
    enum Input {
        case keyDown(UInt16, modifiers: UInt, isRepeat: Bool)
        case keyUp(UInt16, modifiers: UInt)
        case flagsChanged(UInt16, modifiers: UInt)
    }

    enum Outcome: Equatable {
        case waiting, pending(KeyboardShortcut), captured(KeyboardShortcut), cancelled, invalid(String)
    }

    private var bareModifier: HotkeyKey?
    private var sawOtherKey = false
    private var heldKeys: Set<UInt16> = []
    private var currentModifiers: ShortcutModifiers = []
    private var pendingShortcut: KeyboardShortcut?
    private var cancelling = false

    mutating func requestCancellation() -> Outcome {
        cancelling = true
        return completeIfReleased()
    }

    mutating func handle(_ input: Input) -> Outcome {
        let flags: UInt
        switch input {
        case .keyDown(let code, let value, _): heldKeys.insert(code); flags = value
        case .keyUp(let code, let value): heldKeys.remove(code); flags = value
        case .flagsChanged(_, let value): flags = value
        }
        currentModifiers = Self.modifiers(flags)
        if pendingShortcut != nil || cancelling {
            if case .keyDown(53, _, _) = input { cancelling = true }
            if !cancelling, case .modifierChord(let previous) = pendingShortcut {
                if case .keyDown(_, _, false) = input {
                    // ⌘⇧ 이후 E가 오면 수식키 전용 후보를 일반 조합키로 바꾼다.
                    pendingShortcut = nil
                } else {
                    let keys = ModifierChord.pressedKeys(in: flags)
                    if keys.isStrictSuperset(of: previous.keys) {
                        let shortcut = KeyboardShortcut.modifierChord(.init(keys: keys))
                        pendingShortcut = shortcut
                        return .pending(shortcut)
                    }
                    return completeIfReleased()
                }
            } else { return completeIfReleased() }
        }
        switch input {
        case .keyDown(let code, let flags, let isRepeat):
            if code == 53 { return requestCancellation() }
            guard !isRepeat else { return .waiting }
            bareModifier = nil
            sawOtherKey = true
            let modifiers = Self.modifiers(flags)
            guard !modifiers.isEmpty else { return .invalid("⌘, ⌥, ⌃, ⇧ 중 하나와 함께 눌러주세요.") }
            guard let key = ShortcutKey(rawValue: code) else { return .invalid("지원하지 않는 키입니다. 다른 조합키를 눌러주세요.") }
            let shortcut = KeyboardShortcut.chord(.init(key: key, modifiers: modifiers))
            pendingShortcut = shortcut
            return .pending(shortcut)
        case .keyUp(_, let flags):
            if Self.modifiers(flags).isEmpty, heldKeys.isEmpty { sawOtherKey = false; bareModifier = nil }
            return .waiting
        case .flagsChanged(let code, let flags):
            let modifiers = Self.modifiers(flags)
            guard let key = HotkeyKey.allCases.first(where: { $0.keyCode == code }) else {
                bareModifier = nil
                sawOtherKey = true
                return .waiting
            }
            if modifiers.isEmpty {
                let captured = bareModifier == key && !sawOtherKey
                bareModifier = nil
                sawOtherKey = false
                return captured ? .captured(.modifier(key)) : .waiting
            }
            let physicalCount = HotkeyKey.allCases.filter { flags & $0.deviceMask != 0 }.count
            if physicalCount >= 2, heldKeys.isEmpty, !sawOtherKey {
                bareModifier = nil
                let shortcut = KeyboardShortcut.modifierChord(.init(keys: ModifierChord.pressedKeys(in: flags)))
                pendingShortcut = shortcut
                return .pending(shortcut)
            }
            guard modifiers.rawValue.nonzeroBitCount == 1, physicalCount <= 1, heldKeys.isEmpty, !sawOtherKey else {
                bareModifier = nil
                sawOtherKey = true
                return .waiting
            }
            if key.transition(keyCode: code, modifierFlags: flags) == true { bareModifier = key }
            return .waiting
        }
    }

    private mutating func completeIfReleased() -> Outcome {
        guard heldKeys.isEmpty, currentModifiers.isEmpty else { return .waiting }
        let outcome: Outcome = cancelling ? .cancelled : pendingShortcut.map(Outcome.captured) ?? .waiting
        self = Self()
        return outcome
    }

    private static func modifiers(_ flags: UInt) -> ShortcutModifiers {
        var result = ShortcutModifiers(rawValue: flags).intersection(.supportedMask)
        for key in HotkeyKey.allCases where flags & key.deviceMask != 0 {
            result.insert(ShortcutModifiers(familyOf: key))
        }
        return result
    }
}
