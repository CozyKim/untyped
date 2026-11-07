import Foundation

/// Standalone modifier strings remain compatible with existing config files.
enum KeyboardShortcut: Codable, Hashable, Sendable {
    case modifier(HotkeyKey)
    case chord(ShortcutChord)
    case modifierChord(ModifierChord)

    static let rightOption = Self.modifier(.rightOption)
    static let rightCommand = Self.modifier(.rightCommand)
    static let rightControl = Self.modifier(.rightControl)
    static let rightShift = Self.modifier(.rightShift)
    static let leftOption = Self.modifier(.leftOption)
    static let leftCommand = Self.modifier(.leftCommand)
    static let leftControl = Self.modifier(.leftControl)
    static let leftShift = Self.modifier(.leftShift)

    var displayName: String {
        switch self {
        case .modifier(let key): key.displayName
        case .chord(let chord): chord.modifiers.displayName + chord.key.displayName
        case .modifierChord(let chord): chord.displayName
        }
    }

    var isValid: Bool {
        switch self {
        case .modifier: true
        case .modifierChord(let chord): chord.keys.count >= 2
        case .chord(let chord):
            !chord.modifiers.isEmpty && chord.modifiers.subtracting(.supportedMask).isEmpty
        }
    }

    /// A bare modifier fires before the key part of any chord using that family.
    /// Both sides of the family conflict because chord modifiers are side agnostic.
    func conflicts(with other: Self) -> Bool {
        if self == other { return true }
        return switch (self, other) {
        case (.modifier(let key), .chord(let chord)), (.chord(let chord), .modifier(let key)):
            chord.modifiers.contains(ShortcutModifiers(familyOf: key))
        case (.modifierChord(let modifierChord), .chord(let chord)), (.chord(let chord), .modifierChord(let modifierChord)):
            chord.modifiers.isSuperset(of: modifierChord.modifiers)
        default: false
        }
    }

    /// 수식키 조합이 완성되면 먼저 시작한 단독 키의 녹음을 이어받는다.
    func canPromote(from other: Self) -> Bool {
        guard case .modifierChord(let chord) = self else { return false }
        switch other {
        case .modifier(let key): return chord.keys.contains(key)
        case .modifierChord(let previous): return chord.keys.isStrictSuperset(of: previous.keys)
        case .chord: return false
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let legacy = try? container.decode(HotkeyKey.self) {
            self = .modifier(legacy)
        } else if let chord = try? container.decode(ModifierChord.self) {
            self = .modifierChord(chord)
        } else {
            self = .chord(try container.decode(ShortcutChord.self))
        }
        guard isValid else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "A shortcut chord requires supported modifiers.")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .modifier(let key): try container.encode(key)
        case .chord(let chord): try container.encode(chord)
        case .modifierChord(let chord): try container.encode(chord)
        }
    }
}

struct ModifierChord: Codable, Hashable, Sendable {
    let keys: Set<HotkeyKey>

    init(keys: Set<HotkeyKey>) { self.keys = keys }

    private enum CodingKeys: String, CodingKey { case keys = "modifier_keys" }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keys = Set(try container.decode([HotkeyKey].self, forKey: .keys))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(HotkeyKey.allCases.filter(keys.contains), forKey: .keys)
    }

    var modifiers: ShortcutModifiers {
        keys.reduce(into: ShortcutModifiers()) { $0.insert(ShortcutModifiers(familyOf: $1)) }
    }

    var displayName: String { HotkeyKey.allCases.filter(keys.contains).map(\.displayName).joined(separator: " + ") }

    func isHeld(modifierFlags: UInt) -> Bool { keys.allSatisfy { modifierFlags & $0.deviceMask != 0 } }

    static func pressedKeys(in flags: UInt) -> Set<HotkeyKey> {
        Set(HotkeyKey.allCases.filter { flags & $0.deviceMask != 0 })
    }
}

struct ShortcutChord: Codable, Hashable, Sendable {
    var key: ShortcutKey
    var modifiers: ShortcutModifiers
}

/// Generic NSEvent modifier bits. Device-specific, Caps Lock and Fn bits do not
/// participate in chord matching, but are rejected in saved chord definitions.
struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    var rawValue: UInt

    init(rawValue: UInt) { self.rawValue = rawValue }

    static let command = Self(rawValue: 1 << 20)
    static let control = Self(rawValue: 1 << 18)
    static let option = Self(rawValue: 1 << 19)
    static let shift = Self(rawValue: 1 << 17)
    static let supportedMask: Self = [.command, .control, .option, .shift]

    var displayName: String {
        [(Self.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { contains($0.0) }.map(\.1).joined()
    }

    init(familyOf key: HotkeyKey) {
        switch key {
        case .leftOption, .rightOption: self = .option
        case .leftCommand, .rightCommand: self = .command
        case .leftControl, .rightControl: self = .control
        case .leftShift, .rightShift: self = .shift
        }
    }

    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Physical macOS virtual keys; labels intentionally do not depend on layout.
enum ShortcutKey: UInt16, Codable, CaseIterable, Sendable {
    case a = 0, b = 11, c = 8, d = 2, e = 14, f = 3, g = 5, h = 4
    case i = 34, j = 38, k = 40, l = 37, m = 46, n = 45, o = 31, p = 35
    case q = 12, r = 15, s = 1, t = 17, u = 32, v = 9, w = 13, x = 7, y = 16, z = 6
    case zero = 29, one = 18, two = 19, three = 20, four = 21
    case five = 23, six = 22, seven = 26, eight = 28, nine = 25
    case space = 49
    case f1 = 122, f2 = 120, f3 = 99, f4 = 118, f5 = 96, f6 = 97
    case f7 = 98, f8 = 100, f9 = 101, f10 = 109, f11 = 103, f12 = 111

    var keyCode: UInt16 { rawValue }

    var displayName: String {
        switch self {
        case .zero: "0"
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .four: "4"
        case .five: "5"
        case .six: "6"
        case .seven: "7"
        case .eight: "8"
        case .nine: "9"
        case .space: "Space"
        default: String(describing: self).uppercased()
        }
    }
}

/// Pure event state: suppression survives an early modifier release until the
/// consumed physical key is released, while the recording ends exactly once.
struct ShortcutChordTracker: Sendable {
    enum Input {
        case keyDown(UInt16, isRepeat: Bool)
        case keyUp(UInt16)
        case modifiersChanged
        case tapResumed(keyIsDown: Bool)
    }

    enum Transition: Equatable { case pressed, released }
    struct Result: Equatable {
        var consume: Bool
        var transition: Transition?
    }

    let chord: ShortcutChord
    private var keyIsSuppressed = false
    private var active = false

    init(chord: ShortcutChord) { self.chord = chord }

    mutating func handle(_ input: Input, modifiers: ShortcutModifiers, isOwnEvent: Bool = false) -> Result {
        let pass = Result(consume: false, transition: nil)
        guard !isOwnEvent else { return pass }
        switch input {
        case .keyDown(let code, let isRepeat):
            guard code == chord.key.keyCode else { return pass }
            if keyIsSuppressed { return Result(consume: true, transition: nil) }
            guard !isRepeat, modifiers.intersection(.supportedMask) == chord.modifiers,
                  !chord.modifiers.isEmpty else { return pass }
            keyIsSuppressed = true
            active = true
            return Result(consume: true, transition: .pressed)
        case .keyUp(let code):
            guard code == chord.key.keyCode, keyIsSuppressed else { return pass }
            keyIsSuppressed = false
            let transition: Transition? = active ? .released : nil
            active = false
            return Result(consume: true, transition: transition)
        case .modifiersChanged:
            guard active, !modifiers.isSuperset(of: chord.modifiers) else { return pass }
            active = false
            return Result(consume: false, transition: .released)
        case .tapResumed(let keyIsDown):
            keyIsSuppressed = keyIsSuppressed && keyIsDown
            guard active, !keyIsDown || !modifiers.isSuperset(of: chord.modifiers) else { return pass }
            active = false
            return Result(consume: false, transition: .released)
        }
    }
}
