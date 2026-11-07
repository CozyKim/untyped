# Contextual Partial Edit Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan inline with test-first verification.

**Goal:** Use full input context while applying only validated fragment replacements.
**Architecture:** Parse model anchor patches, resolve/minimize UTF-16 ranges locally, apply with Accessibility selected text under snapshot guards. Keep command and timeout infrastructure.
**Tech Stack:** Swift 6, Foundation, macOS Accessibility, existing local LLM.
**Spec:** `docs/superpowers/specs/2026-11-07-contextual-partial-edit-design.md`

## Global Constraints

- Work in `.worktrees/voice-edit-and-submit`; no new dependencies.
- No whole-field AXValue setter or fallback insertion of an editing instruction.
- Preserve untouched characters exactly and reject all invalid patch sets before writing.

## Review Focus

- Repeated anchors must be rejected unless neighboring text makes them unique.
- Unicode and newline preservation use locally computed UTF-16 ranges.
- Multiple edits must not shift pending ranges or overwrite intervening user edits.
- Unsupported Accessibility writes must report failure rather than rewrite the field.
- Malformed/empty/truncated model responses must not erase text.

### Task 1: Validated patch plan

Create `Refine/VoiceEditPlan.swift` and `VoiceEditPlanTests.swift`. Expose `VoiceEditPlan.decode(_:original:)`, original text, minimized descending patches and locally computed result.

- [x] Write/run failing tests for unique, ambiguous, missing, overlapping, Unicode and multiple patches.
- [x] Implement exact anchor validation, range minimization and deterministic result construction; run targeted tests.

### Task 2: Partial output and input

Change `VoiceEditPrompt`, client `edit`, `VoiceCommandProcessor`, `VoiceCommandInput` and corresponding tests.

- [x] Write failing partial-write tests, update HTTP fixtures to anchor JSON.
- [x] Return structured patch JSON from the client; parse/validate in processor. Replace the whole-field input writer with a guarded async `(NSRange, String, expectedText) -> Result` boundary and production AX selection plus paste/Delete writer.
- [x] Test invalid patches produce zero mutations and mid-edit interference stops subsequent patches.

### Task 3: Verification and running app

- [x] Update docs; run full `swift test`, review changes, fix concrete review findings and run `swift build`.
- [x] Bundle and relaunch the existing worktree app; verify its executable path.

## Execution record

User explicitly requested this refinement after inspecting the earlier implementation. Continue the authorized implementation without another behavior confirmation; keep changes uncommitted on the feature branch.

Verification record: anchor-plan tests RED→GREEN, partial writer tests RED→GREEN. Regressions cover colliding insertion points, exact UTF-16 guards and clipboard-backed replacement/deletion. Reviewer identified canonical String equality shifting UTF-16 offsets; fixed with exact code-unit matching and regression `normalizationChangeCannotShiftTheReplacementRange`. SDK AXAttributeConstants.h documents AXSelectedText as read-only; final implementation selects the writable range and pastes/deletes under the existing transaction instead. Targeted tests: 37 passed. Final full suite and relaunch follow.

Final verification: `swift test` passed 247 tests in 9 suites; `Scripts/bundle.sh` built and signed successfully; relaunched worktree executable `/Users/kjh/coding/untyped/.worktrees/voice-edit-and-submit/build/Untyped.app/Contents/MacOS/Untyped` verified running as PID 9732. Main checkout remains clean; branch and worktree retained. App-specific Accessibility behavior remains a manual interoperability check; no real user text was used for testing.

Live debugging follow-up: user reported that a range was highlighted but text was not replaced. Existing command logs confirmed recognition/refinement succeeded and application returned unavailable. Immediate AX selection readback could reject a delayed cache update. Added bounded selection confirmation (500 ms) under unchanged focus/content guards, detailed failure-stage diagnostics and processor passthrough. Tests were RED for missing wait/diagnostic interfaces, then GREEN; full suite passed 250 tests in 9 suites. Rebuilt/signed and relaunched worktree app as PID 22515. A real subsequent dictation at 2026-11-07 17:01:56 logged `입력: 음성 수정 · 입력창 수정 완료`; that success path requires exact post-replacement field-value receipt and final snapshot validation. No user transcript or edited text is copied into this plan.
