# Settings close confirmation implementation plan

Goal: Ask whether to save changed settings when closing the settings window.
Architecture: Keep an editable SettingsDraft with a saved baseline. Attach a
window delegate proxy that presents a native three-button sheet and forwards
SwiftUI's existing delegate methods. Reuse the existing save validation.
Tech stack: Swift 6, SwiftUI, AppKit, Swift Testing; macOS 26+.

Requirements:
- Unchanged settings or changes reverted to saved values close without a prompt.
- Save persists and applies settings, then closes only on success.
- Don't Save closes without persisting; Cancel retains the current draft.
- Invalid URL/prompt text and login-item changes count as edits.
- Successful manual Save resets the baseline; failures retain the draft.
- Keep the earlier focus fix and preserve the original checkout's changes.
- Reopening the menu while settings are visible must not reset the draft.

Steps:
- [x] Run the existing suite in the isolated worktree.
- [x] Add failing dirty-state and close-decision tests.
- [x] Implement SettingsDraft and the native close confirmation bridge.
- [x] Wire the draft and Bool-returning save into SettingsView.
- [x] Run the full test suite, review, build, and verify the app if GUI access works.

Review focus: save failure, repeated close attempts, delegate restoration,
reopening an already-visible window, and shortcut-capture cancellation.

Validation: baseline 288 tests passed. Dirty-state/close-policy tests first failed
before implementation. The attachment lifecycle regression reproduced stale
proxy restoration before the generation guard. Final suite: 298 tests in 16
suites passed; app bundle built and signed successfully.

Review: an independent read-only reviewer found validation mutating a failed
draft and pending attachment installing stale delegates. Both are fixed and
covered by regression tests. Already-visible settings explicitly regain focus.
GUI inspection is unavailable: native Computer Use pipe startup failed.

Scope retained: existing partial-save behavior if login-item registration
fails, app termination, and external config-file synchronization are unchanged.
