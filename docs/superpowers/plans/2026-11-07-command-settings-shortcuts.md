# Command Settings and Shortcuts Implementation Plan

> **For agentic workers:** Use test-first implementation; keyboard and voice-rule modules are independent and may be delegated under dispatching-parallel-agents, with integration in this session.

**Goal:** Configurable command phrases and modifier combinations for edit/literal recording, without a submit shortcut.
**Architecture:** KeyboardShortcut represents backward-compatible modifier/chord bindings; VoiceCommandRules parses configurable phrases. RecordingRoute pins mode and destination. Coordinator snapshots settings and safely updates monitors. SettingsView exposes rules, toggles and reusable shortcut controls.
**Tech Stack:** Swift 6, AppKit/CoreGraphics, Codable; no dependencies.
**Spec:** `docs/superpowers/specs/2026-11-07-command-settings-shortcuts-design.md`

## Global Constraints

- Keep `.worktrees/voice-edit-and-submit` and existing contextual partial-edit implementation.
- No submit shortcut; Enter remains available.
- Preserve legacy configs, default phrases and disabled optional bindings.

## Review Focus

- Chord keys must not type into another app or respond to autorepeat/self-generated paste events.
- Releasing modifiers before the chord key must stop a hold exactly once.
- A saved setting must not switch a live recording's mode or strand a release event.
- Literal speech must not execute edit/submit or automatic Return.
- Duplicate/overlapping shortcuts and indistinguishable phrases must fail validation.

### Task 1: Keyboard shortcuts (independent)

Create KeyboardShortcut model/tracker and tests; update HotkeyMonitor to consume chord events while preserving standalone behavior. Interface: KeyboardShortcut.modifier(HotkeyKey), .chord(ShortcutChord), Codable/displayName/conflicts; ShortcutChord(key: ShortcutKey, modifiers: ShortcutModifiers). Expose existing modifier conveniences for compatibility.

- [x] Write/run failing model/event tests, implement, verify targeted tests.

### Task 2: Voice rules (independent)

Create VoiceCommandRules with separate toggles/phrase arrays; extend VoiceCommand.parse(_:enabled:rules:) while keeping defaults. Expose normalized rules and validationError.

- [x] Write/run failing phrase/disabled/ambiguous tests, implement, verify targeted tests.

### Task 3: Integration and settings

Modify AppConfig, DictationState/RecordingRoute, Coordinator and SettingsView; add ShortcutPicker; update tests/docs.

- [x] Write config migration, recording route and explicit literal/edit tests; watch failures.
- [x] Wire settings, immutable session rules/mode, deferred monitor reconfiguration, conflict validation and no automatic Return on literal route.
- [x] Add controls and help text; verify targeted tests and full suite.

### Task 4: Review and running app

- [x] Review integration, fix confirmed issues, build/sign/relaunch and verify executable path.
- [x] Record verification results and remaining live checks.

Implementation record: keyboard and voice-rule domains were delegated with disjoint files and integrated here. Legacy modifier JSON remains unchanged; optional edit/literal keys default to nil. Mode and normalized command rules are captured at recording start. Deferred binding refresh preserves the starting key's release. Literal routes disable command recognition and automatic Return. No submit binding was added.

Review findings addressed: command normalization now removes terminal sentence punctuation and rejects active submit phrases matching edit prefixes at the same parser boundary, with fail-closed parsing for bypassed validation. Tests demonstrated the ambiguity before the fix. Failed chord taps expose installation state/error, retry on application activation and can be retried by saving unchanged settings. Chord callbacks are queued off the event-tap callback with generation guards; physical HID state reconciles missed releases after tap timeout.

Verification: final `swift test` passed 281 tests in 12 suites, no warnings or failures; `git diff --check` passed. The real macOS chord interception path requires a shortcut assigned in settings for a live check; new optional assignments are deliberately unset. Original checkout remains clean. Build/relaunch confirmation follows.

Build/relaunch: `Scripts/bundle.sh` completed with the local code-signing identity. Verified running PID 54634 at `/Users/kjh/coding/untyped/.worktrees/voice-edit-and-submit/build/Untyped.app/Contents/MacOS/Untyped`. No preference file was changed to assign optional shortcuts. Main checkout clean; no commit/merge/push performed.
