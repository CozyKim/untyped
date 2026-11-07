# Pressed Shortcut Recording Plan

**Goal:** Let the user press an actual shortcut instead of manually selecting modifier checkboxes and a key.

**Design:** Each shortcut row shows its current binding, a key-input button and optional clear. Local key monitoring identifies modifier+key on key-down and completes only after all held keys/modifiers are released; a single left/right modifier completes on release. Escape cancels, unsupported/unmodified keys show a message while listening continues, and capture never edits the saved config until Save. Suspend runtime hotkey monitors before recording keys; refuse to suspend an in-progress dictation. Resume on completion, cancellation, window/app deactivation or view disappearance. Saving while capturing does not reinstall runtime monitors.

**Approaches:** Manual selectors are the current behavior the user wants replaced. An app-local recorder is sufficient while Settings has focus and avoids adding another global key tap.

- [x] Add failing pure recorder-state tests and Coordinator suspension tests.
- [x] Implement key-event state and lifecycle-managed local recorder.
- [x] Replace ShortcutPicker UI and connect Coordinator suspension/restoration.
- [x] Run targeted/full tests, review, build and relaunch the worktree app.

Keep `.worktrees/voice-edit-and-submit`, existing backward-compatible shortcut encoding, conflict validation, no submit shortcut and all dictation behavior.

Review: captured chords must keep consuming autorepeats through physical release. Added pending/draining state, cancellation draining and tests for held Cmd+V, Escape during a held chord, dual physical modifiers and all-key release. Coordinator suspension and restoration remain active throughout draining.

Final verification: full Swift suite passed 291 tests in 13 suites; bundle build/sign succeeded and worktree executable verified running as PID 81239. CUA initially timed out because the menu-bar app had no Settings window; after the user opened Settings, live verification succeeded. Clicked the edit shortcut's key-input button and observed Save disabled; pressed actual super+shift+e and observed `수정 전용: ⇧⌘E` with Save enabled. Started input again and pressed Escape; the existing chord was preserved and Save re-enabled. Cleared only that test binding back to its original unset state. Never clicked Save or modified any other draft preferences. Settings window remains open for the user.
