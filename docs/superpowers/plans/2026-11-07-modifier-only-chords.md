# Modifier-only Shortcut Fix

User reports Shift + right Command cannot register. Current chord representation requires an ordinary key, while recorder discards sequences containing multiple modifiers. Add a physical modifier-key set (two or more) with backward-compatible JSON. Recorder waits for all releases and can upgrade a provisional modifier chord into an ordinary key chord when a letter follows.

Allow modifier-only chords to coexist with standalone keys contained in them. When a second modifier completes a more specific configured chord during a provisional hold, switch that recording's route/policy without starting another microphone or processing the provisional audio. Retain the rule snapshot, and ignore the old route's release. Keep ordinary-key chord conflict validation.

- [x] RED: representation, capture, side matching, config coexistence and recording promotion tests.
- [x] Implement model, recorder, flags monitor and recording-intent promotion.
- [x] Update earlier recorder expectations for supported modifier sets; full suite and review.
- [x] Build/sign/relaunch and verify the requested physical combination where UI automation permits.

Verification: representation/capture/strict-physical-side/promotion tests RED→GREEN. Corrected two earlier recorder fixture assertions to reflect newly supported modifier sets while preserving held ordinary-key draining. Reviewer found failed target promotion could leave a provisional frontmost recording alive; added promotionAllowed/discardCapture state effect and lifecycle-safe discard awaiting captureSetup, stopping capture, finalizing sinks and restoring audio with session guards. Regression refusedTargetPromotionDiscardsTheProvisionalRecording failed before implementation. Final full suite passed 299 tests in 14 suites; git diff --check passed. No original-checkout changes.

Build/sign completed; relaunched worktree executable verified as PID 1621. Post-relaunch CUA could not attach because Settings was no longer open (getAXState timed out); no live physical modifier-only registration was claimed. User can open Settings and press the actual pair; assignment remains unsaved until Save.
