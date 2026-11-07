# Voice editing and submission

Partial editing is refined by `2026-11-07-contextual-partial-edit-design.md`: the model returns anchored fragments, the app computes minimal ranges and pastes only into those selections. The full-field output/replacement implementation has been removed.

Approved behavior: use the current input field, including earlier dictation and manual edits. “수정, 내일을 오늘로 바꿔” edits that field; standalone “보내” posts Return without inserting the command. Existing recording shortcuts still delimit recordings.

Approaches: retaining only previous dictation loses manual edits; buffering drafts in Untyped changes the existing workflow. The user selected reading the actual input field through macOS Accessibility.

Keep Swift 6, macOS 26, local OpenAI-compatible inference and no new dependencies. Recognize commands before ordinary text refinement. Use a dedicated edit prompt containing field text and the instruction, preserving all unrelated text. Failed edits never fall back to inserting the instruction.

Capture the intended app and focused element when recording starts. Before editing/submitting, require that element to retain focus; before writing an edit also require unchanged field contents. Accessible, writable text fields support edits; unreadable, secure, transient terminal inputs and unsupported setters report a notice. Explicit submission may post Return to a focused terminal. A bare “수정” requests an instruction rather than replacing content.

Implementation choices: strict command boundaries avoid treating ordinary words such as “수정사항” or “자료를 보내 주세요” as commands. An enabled-by-default setting allows literal dictation instead. Existing automatic Return settings remain independent; users who want to review before sending should turn them off. Audio-only transcription must preserve command words before routing.

No automatic editing of arbitrary historical fields, continuous always-on listening, or implicit submission after an edit. Verify routing, prompt isolation, focus/content guards, failures, old config compatibility and the full Swift test suite. GUI interoperability requires a separate manual check with Accessibility permission.
