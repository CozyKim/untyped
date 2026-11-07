import Foundation
import Testing
@testable import Untyped

@MainActor
struct VoiceCommandInputTests {
    @Test func waitsForDelayedAccessibilitySelectionConfirmation() async {
        var selected = false
        let update = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            selected = true
        }
        let confirmed = await VoiceCommandInput.waitForSelection(
            timeout: .milliseconds(200), isCurrent: { true }, hasExpectedText: { true },
            matchesSelection: { selected }
        )
        await update.value
        #expect(confirmed)
    }

    @Test func selectionWaitStopsIfContentOrFocusChanges() async {
        for focused in [true, false] {
            #expect(!(await VoiceCommandInput.waitForSelection(
                timeout: .milliseconds(200), isCurrent: { focused }, hasExpectedText: { false },
                matchesSelection: { Issue.record("바뀐 입력창에서 선택을 기다리면 안 된다"); return true }
            )))
        }
    }

    @Test func normalizationChangeCannotShiftTheReplacementRange() async throws {
        let original = "é ab"
        var value: String? = original
        var writes = 0
        let input = VoiceCommandInput(text: original, isCurrent: { true }, read: { value }, writeRange: { _, _, _ in
            writes += 1; return .completed
        }, postReturn: { false })
        value = "e\u{301} ab"
        #expect(await input.apply(try plan(original, old: "ab", new: "xy")) == .changed)
        #expect(writes == 0)
    }

    private func plan(_ original: String, old: String, new: String) throws -> VoiceEditPlan {
        let data = try JSONSerialization.data(withJSONObject: ["edits": [["old": old, "new": new]]])
        return try VoiceEditPlan.decode(String(decoding: data, as: UTF8.self), original: original)
    }

    @Test func editsOnlyTheRequestedRangeAndPreservesContext() async throws {
        let original = "내일 회의합니다. 발표는 제가 합니다."
        var value: String? = original
        var writes: [(NSRange, String)] = []
        let input = VoiceCommandInput(text: value, isCurrent: { true }, read: { value }, writeRange: { range, replacement, expected in
            #expect(value == expected)
            writes.append((range, replacement))
            value = (expected as NSString).replacingCharacters(in: range, with: replacement)
            return .completed
        }, postReturn: { Issue.record("수정은 전송하지 않는다"); return true })
        #expect(await input.apply(try plan(original, old: "내일 회의합니다.", new: "오늘 회의합니다.")) == .completed)
        #expect(value == "오늘 회의합니다. 발표는 제가 합니다.")
        #expect(writes.count == 1)
        #expect(writes[0].0 == NSRange(location: 0, length: 2))
        #expect(writes[0].1 == "오늘")
    }

    @Test func manualChangesDuringInferenceAreNeverOverwritten() async throws {
        var value: String? = "내일 회의"
        var writes = 0
        let input = VoiceCommandInput(text: value, isCurrent: { true }, read: { value }, writeRange: { _, _, _ in
            writes += 1; return .completed
        }, postReturn: { true })
        value = "내일 회의, 직접 수정"
        #expect(await input.apply(try plan("내일 회의", old: "내일", new: "오늘")) == .changed)
        #expect(writes == 0)
    }

    @Test func changedFocusPreventsBothCommands() async throws {
        var focused = true
        var events = 0
        let input = VoiceCommandInput(text: "원문", isCurrent: { focused }, read: { "원문" }, writeRange: { _, _, _ in
            events += 1; return .completed
        }, postReturn: { events += 1; return true })
        focused = false
        #expect(await input.apply(try plan("원문", old: "원문", new: "수정문")) == .changed)
        #expect(input.submit() == .changed)
        #expect(events == 0)
    }

    @Test func explicitSubmitNeedsNoReadableTextAndPostsOnce() async throws {
        var returns = 0
        let input = VoiceCommandInput(text: nil, isCurrent: { true }, read: { nil }, writeRange: { _, _, _ in
            Issue.record("전송은 텍스트를 쓰지 않는다"); return .unavailable
        }, postReturn: { returns += 1; return true })
        #expect(input.submit() == .completed)
        #expect(returns == 1)
        #expect(await input.apply(try plan("원문", old: "원문", new: "문장")) == .unavailable)
    }

    @Test func unsupportedOrUnconfirmedWritesReportFailure() async throws {
        let input = VoiceCommandInput(text: "원문", isCurrent: { true }, read: { "원문" }, writeRange: { _, _, _ in .unavailable }, postReturn: { false })
        let edit = try plan("원문", old: "원문", new: "수정문")
        #expect(await input.apply(edit) == .unavailable)
        #expect(input.submit() == .unavailable)
        let unconfirmed = VoiceCommandInput(text: "원문", isCurrent: { true }, read: { "원문" }, writeRange: { _, _, _ in .completed }, postReturn: { true })
        #expect(await unconfirmed.apply(edit) == .unconfirmed)
    }

    @Test func cancelledCommandsHaveNoSideEffects() async throws {
        var events = 0
        let input = VoiceCommandInput(text: "원문", isCurrent: { true }, read: { "원문" }, writeRange: { _, _, _ in
            events += 1; return .completed
        }, postReturn: { events += 1; return true })
        let edit = try plan("원문", old: "원문", new: "수정문")
        let task = Task { @MainActor in
            #expect(await input.apply(edit) == .cancelled)
            #expect(input.submit() == .cancelled)
        }
        task.cancel()
        await task.value
        #expect(events == 0)
    }

    @Test func multipleRangeWritesUseOriginalOffsetsFromTheEnd() async throws {
        let original = "내일 회의. 발표는 김 대리."
        var value: String? = original
        var locations: [Int] = []
        let input = VoiceCommandInput(text: value, isCurrent: { true }, read: { value }, writeRange: { range, replacement, expected in
            #expect(value == expected)
            locations.append(range.location)
            value = (expected as NSString).replacingCharacters(in: range, with: replacement)
            return .completed
        }, postReturn: { false })
        let edit = try VoiceEditPlan.decode(#"{"edits":[{"old":"내일","new":"오늘 저녁"},{"old":"김 대리","new":"이 과장"}]}"#, original: original)
        #expect(await input.apply(edit) == .completed)
        #expect(value == "오늘 저녁 회의. 발표는 이 과장.")
        #expect(locations == [11, 0])
    }

    @Test func interferenceBetweenPatchesStopsWithoutOverwritingUserEdits() async throws {
        let original = "내일 회의. 발표는 김 대리."
        var value: String? = original
        var writes = 0
        let input = VoiceCommandInput(text: value, isCurrent: { true }, read: { value }, writeRange: { range, replacement, expected in
            writes += 1
            value = (expected as NSString).replacingCharacters(in: range, with: replacement) + " 직접 편집"
            return .completed
        }, postReturn: { false })
        let edit = try VoiceEditPlan.decode(#"{"edits":[{"old":"내일","new":"오늘"},{"old":"김 대리","new":"이 과장"}]}"#, original: original)
        #expect(await input.apply(edit) == .unconfirmed)
        #expect(writes == 1)
        #expect(value == "내일 회의. 발표는 이 과장. 직접 편집")
    }
}
