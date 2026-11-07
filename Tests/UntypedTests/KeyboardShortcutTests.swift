import Foundation
import Testing
@testable import Untyped

@Test func standaloneShortcutsRetainLegacyJSON() throws {
    for key in HotkeyKey.allCases {
        let data = try JSONEncoder().encode(KeyboardShortcut.modifier(key))
        #expect(String(decoding: data, as: UTF8.self) == "\"\(key.rawValue)\"")
        #expect(try JSONDecoder().decode(KeyboardShortcut.self, from: data) == .modifier(key))
    }
}

@Test func chordJSONUsesKeyAndModifiersAndRoundTrips() throws {
    let shortcut = KeyboardShortcut.chord(ShortcutChord(key: .space, modifiers: [.control, .option]))
    let data = try JSONEncoder().encode(shortcut)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Int])
    #expect(object["key"] == 49)
    #expect(object["modifiers"] == 786432)
    #expect(try JSONDecoder().decode(KeyboardShortcut.self, from: data) == shortcut)
}

@Test(arguments: [
    #"{"key":49,"modifiers":0}"#,
    #"{"key":65535,"modifiers":262144}"#,
    #"{"key":49,"modifiers":1}"#,
    #"{"key":49,"modifiers":589824}"#,
    #""unknown_modifier""#,
])
func invalidShortcutJSONIsRejected(json: String) {
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(KeyboardShortcut.self, from: Data(json.utf8))
    }
}

@Test func shortcutValidityAndDisplayNames() {
    #expect(!KeyboardShortcut.chord(.init(key: .a, modifiers: [])).isValid)
    #expect(!KeyboardShortcut.chord(.init(key: .a, modifiers: .init(rawValue: 1))).isValid)
    #expect(KeyboardShortcut.chord(.init(key: .a, modifiers: [.control, .option])).displayName == "⌃⌥A")
    #expect(KeyboardShortcut.rightOption.displayName == "오른쪽 ⌥ Option")
    #expect(ShortcutKey.f12.displayName == "F12")
    #expect(ShortcutKey.zero.displayName == "0")
}

@Test func conflictsRejectDuplicatesAndEagerModifierOverlap() {
    let chord = KeyboardShortcut.chord(.init(key: .space, modifiers: [.control, .option]))
    #expect(chord.conflicts(with: chord))
    #expect(chord.conflicts(with: .rightOption))
    #expect(KeyboardShortcut.leftControl.conflicts(with: chord))
    #expect(!chord.conflicts(with: .rightCommand))
    #expect(!KeyboardShortcut.rightOption.conflicts(with: .leftOption))
    #expect(!chord.conflicts(with: .chord(.init(key: .a, modifiers: [.control, .option]))))
}

@Test func chordTrackerConsumesPressRepeatsAndReleaseOnce() {
    var tracker = ShortcutChordTracker(chord: .init(key: .space, modifiers: [.control, .option]))
    #expect(tracker.handle(.keyDown(49, isRepeat: false), modifiers: [.control, .option]) == .init(consume: true, transition: .pressed))
    #expect(tracker.handle(.keyDown(49, isRepeat: true), modifiers: [.control, .option]) == .init(consume: true, transition: nil))
    #expect(tracker.handle(.keyDown(49, isRepeat: false), modifiers: [.control, .option]) == .init(consume: true, transition: nil))
    #expect(tracker.handle(.keyUp(49), modifiers: [.control, .option]) == .init(consume: true, transition: .released))
    #expect(tracker.handle(.keyUp(49), modifiers: [.control, .option]) == .init(consume: false, transition: nil))
}

@Test func chordTrackerEndsOnModifierReleaseButStillConsumesKeyUpAndRepeats() {
    var tracker = ShortcutChordTracker(chord: .init(key: .a, modifiers: .command))
    _ = tracker.handle(.keyDown(0, isRepeat: false), modifiers: .command)
    #expect(tracker.handle(.modifiersChanged, modifiers: []) == .init(consume: false, transition: .released))
    #expect(tracker.handle(.modifiersChanged, modifiers: []) == .init(consume: false, transition: nil))
    #expect(tracker.handle(.keyDown(0, isRepeat: true), modifiers: []) == .init(consume: true, transition: nil))
    #expect(tracker.handle(.keyUp(0), modifiers: []) == .init(consume: true, transition: nil))
    #expect(tracker.handle(.keyDown(0, isRepeat: false), modifiers: .command).transition == .pressed)
}

@Test func chordTrackerPassesUnrelatedExtraModifiersAndOwnSyntheticEvents() {
    var tracker = ShortcutChordTracker(chord: .init(key: .a, modifiers: .command))
    let pass = ShortcutChordTracker.Result(consume: false, transition: nil)
    #expect(tracker.handle(.keyDown(1, isRepeat: false), modifiers: .command) == pass)
    #expect(tracker.handle(.keyDown(0, isRepeat: false), modifiers: [.command, .shift]) == pass)
    #expect(tracker.handle(.keyDown(0, isRepeat: true), modifiers: .command) == pass)
    #expect(tracker.handle(.keyDown(0, isRepeat: false), modifiers: .command, isOwnEvent: true) == pass)
    #expect(tracker.handle(.keyDown(0, isRepeat: false), modifiers: .command).transition == .pressed)
    #expect(tracker.handle(.keyUp(0), modifiers: .command, isOwnEvent: true) == pass)
    #expect(tracker.handle(.modifiersChanged, modifiers: [.command, .shift]) == pass)
    #expect(tracker.handle(.keyUp(0), modifiers: .command).transition == .released)
}

@Test func chordTrackerRecoversAReleaseMissedWhileTapWasDisabled() {
    var tracker = ShortcutChordTracker(chord: .init(key: .a, modifiers: .command))
    _ = tracker.handle(.keyDown(0, isRepeat: false), modifiers: .command)
    #expect(tracker.handle(.tapResumed(keyIsDown: false), modifiers: []) == .init(consume: false, transition: .released))
    #expect(tracker.handle(.tapResumed(keyIsDown: false), modifiers: []) == .init(consume: false, transition: nil))
    #expect(tracker.handle(.keyDown(0, isRepeat: false), modifiers: .command).transition == .pressed)
}

@Test func chordTrackerRetainsHeldKeysWhenTapResumes() {
    var tracker = ShortcutChordTracker(chord: .init(key: .a, modifiers: .command))
    _ = tracker.handle(.keyDown(0, isRepeat: false), modifiers: .command)
    #expect(tracker.handle(.tapResumed(keyIsDown: true), modifiers: .command) == .init(consume: false, transition: nil))
    #expect(tracker.handle(.tapResumed(keyIsDown: true), modifiers: []) == .init(consume: false, transition: .released))
    #expect(tracker.handle(.keyDown(0, isRepeat: true), modifiers: []) == .init(consume: true, transition: nil))
    #expect(tracker.handle(.keyUp(0), modifiers: []) == .init(consume: true, transition: nil))
}
