# Voice Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Edit text already in an input field and submit it using spoken commands.

**Architecture:** Parse commands before refinement, read an Accessibility snapshot, request a dedicated contextual edit and guard the final write/Return against changed focus or text. Coordinator routes both Apple and audio backends.

**Tech Stack:** Swift 6, macOS 26 Accessibility, existing local chat completions.

**Spec:** `docs/superpowers/specs/2026-11-07-voice-commands-design.md`

## Global Constraints

- Swift 6, macOS 26, no new dependencies.
- Preserve ordinary dictation and existing automatic Return preferences.
- Failed commands do not insert instruction text or post Return.

## Review Focus

- Normal prose containing command words remains dictation.
- Input changes during inference prevent overwrites.
- Another field/app receiving focus prevents commands.
- Audio-only recognition preserves the command prefix.
- Old configs work and disabling commands allows literal dictation.

### Task 1: Command routing and contextual edits

Files: create `Core/VoiceCommand.swift`, `Refine/VoiceEditPrompt.swift`, tests `VoiceCommandTests.swift`; modify `OpenAICompatibleRefiner.swift`.
Interface: `VoiceCommand.parse(_:) -> VoiceCommand?`, `.edit(String)`, `.submit`; `VoiceEditPrompt.messages(text:instruction:) -> [ChatMessage]`; client `edit(_:instruction:) async throws -> String`.

- [x] Add failing parser and contextual payload tests; run `swift test --filter VoiceCommandTests`.
- [x] Implement strict parsing and isolated editing prompt; run the same tests.

### Task 2: Guarded input mutation

Files: create `Output/VoiceCommandInput.swift`, tests `VoiceCommandInputTests.swift`.
Interface: MainActor snapshot with optional `text`, `isCurrent`, `replace(with:)`, `submit()`; production capture from focused AX element, injectable boundaries for tests.

- [x] Add failing tests for focus/content changes, unsupported writes, cancellation and explicit Return.
- [x] Implement synchronous final checks, direct AXValue writes and Return event posting; run targeted tests.

### Task 3: End-to-end routing and settings

Files: modify `Core/Coordinator.swift`, `Core/AppConfig.swift`, `App/SettingsView.swift`, audio prompt and both READMEs; add config/audio tests.

- [x] Test enabled default, disabled round trip and command-preserving audio payload.
- [x] Capture target at recording start; route raw commands before refinement; handle command failures with notices/logging, never fallback insertion.
- [x] Add setting and usage examples, run `swift test` and `swift build`, review diff.

## Execution record

User approved the concrete behavior and requested proceeding; execute inline, leaving changes available for review. Final working location is `/Users/kjh/coding/untyped/.worktrees/voice-edit-and-submit` on `feat/voice-edit-and-submit`, as the user explicitly requested `.worktrees`. All 19 modified/new files were hash-verified when moving; original checkout restored clean. `.worktrees/` is ignored locally through `.git/info/exclude`. No commit, merge or publishing is required. A reviewer checked the implementation under the requesting-code-review skill. Its P2 origin-focus issue is covered by `targetActivationRequiresCapturedOriginFocus`: missing/generic changed focus must not activate a target app. Generic AX focus capture now covers buttons and web pages too.

Verification record: initial command tests failed for missing implementation; parser test caught trailing punctuation loss and passed after a targeted fix. Original workspace full suite passed 228 tests, targeted HTTP and command checks passed 22. The final review regression failed for missing preparation guard before the fix. Structured edit JSON preserves whitespace and allows explicit whole-field deletion while malformed, empty or truncated server responses are rejected. No unresolved confirmed important review findings. GUI interoperability with individual third-party apps remains a manual check.

Final verification in `.worktrees/voice-edit-and-submit`: `swift test` passed 233 tests in 7 suites; `swift build` passed; `git diff --check` passed. Added parser regressions first demonstrated loss of negative signs and opening quotes; the command delimiter now preserves those instruction characters. The main checkout remains clean. No merge or publish performed; feature worktree retained.
