import AppKit
import ApplicationServices

/// 녹음 시작 시 고정한 입력 요소. 최종 검사와 쓰기 사이에는 await가 없다.
@MainActor
struct VoiceCommandInput {
    enum Result: Equatable {
        case completed, changed, unavailable, unconfirmed, cancelled

        var notice: String {
            switch self {
            case .completed: "명령 처리 완료"
            case .changed: "입력창 또는 내용이 바뀜 — 명령 중단"
            case .unavailable: "이 입력창에서는 명령을 처리할 수 없음"
            case .unconfirmed: "수정이 일부만 적용됐을 수 있음 — 입력창을 확인하세요"
            case .cancelled: "명령 취소됨"
            }
        }
    }

    let text: String?
    let isCurrent: () -> Bool
    let read: () -> String?
    let writeRange: (NSRange, String, String) async -> Result
    let postReturn: () -> Bool
    var failureReason: () -> String? = { nil }

    /// Electron 등은 선택을 적용한 뒤 AX 캐시가 늦게 갱신될 수 있다.
    static func waitForSelection(
        timeout: Duration = .milliseconds(500), isCurrent: () -> Bool,
        hasExpectedText: () -> Bool, matchesSelection: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !Task.isCancelled {
            guard isCurrent(), hasExpectedText() else { return false }
            if matchesSelection() { return isCurrent() && hasExpectedText() }
            guard ContinuousClock.now < deadline else { return false }
            do { try await Task.sleep(for: .milliseconds(10)) }
            catch { return false }
        }
        return false
    }

    func apply(_ plan: VoiceEditPlan) async -> Result {
        guard !Task.isCancelled else { return .cancelled }
        guard isCurrent() else { return .changed }
        guard let text else { return .unavailable }
        guard TextInserter.exactlyMatches(plan.original, text), TextInserter.exactlyMatches(read(), text), isCurrent() else { return .changed }
        var expected = text
        var applied = false
        for patch in plan.patches {
            guard !Task.isCancelled else { return applied ? .unconfirmed : .cancelled }
            guard isCurrent(), TextInserter.exactlyMatches(read(), expected) else { return applied ? .unconfirmed : .changed }
            let result = await writeRange(patch.range, patch.replacement, expected)
            guard result == .completed else { return applied ? .unconfirmed : result }
            applied = true
            expected = (expected as NSString).replacingCharacters(in: patch.range, with: patch.replacement)
            guard isCurrent(), TextInserter.exactlyMatches(read(), expected) else { return .unconfirmed }
        }
        return .completed
    }

    func submit() -> Result {
        guard !Task.isCancelled else { return .cancelled }
        guard isCurrent() else { return .changed }
        // 읽을 수 있는 입력창은 전사 대기 중 다른 내용으로 바뀐 경우에도 전송하지 않는다.
        if let text, !TextInserter.exactlyMatches(read(), text) { return .changed }
        guard isCurrent() else { return .changed }
        return postReturn() ? .completed : .unavailable
    }

    /// 버튼이나 웹페이지도 원래 포커스의 기준으로 보존한다. 텍스트 접근은 하지 않는다.
    static func captureFocus() -> (() -> Bool)? {
        guard TextInserter.hasAccessibilityPermission,
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let element = focusedElement(pid: pid) else { return nil }
        return { matchesFocus(pid: pid, element: element) }
    }

    private static func matchesFocus(pid: pid_t, element: AXUIElement) -> Bool {
        guard TargetApp.keyboardFocusState(pid: pid) == true,
              let current = focusedElement(pid: pid) else { return false }
        return CFEqual(element, current)
    }

    static func capture(pid: pid_t? = nil) -> Self? {
        guard TextInserter.hasAccessibilityPermission,
              let pid = pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let element = focusedElement(pid: pid)
        else { return nil }
        let role = attribute(element, kAXRoleAttribute) as? String
        // 보안 입력창 및 임의의 버튼/웹 영역에는 Return도 보내지 않는다.
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? ""),
              attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole
        else { return nil }
        let transient = TextInserter.isTransientInput(
            role: role, domClasses: attribute(element, "AXDOMClassList") as? [String] ?? []
        )
        func value() -> String? { attribute(element, kAXValueAttribute) as? String }
        var diagnostic: String?
        return Self(
            text: transient ? nil : value(),
            isCurrent: { matchesFocus(pid: pid, element: element) },
            read: { transient ? nil : value() },
            writeRange: { range, replacement, expected in
                guard !transient else { return .unavailable }
                var posted = false
                var stage = "범위 선택 전"
                let after = (expected as NSString).replacingCharacters(in: range, with: replacement)
                let result = await TextInserter.insert(
                    replacement, into: .general,
                    expectedReplacement: (before: expected, after: after),
                    prepare: {
                        var settable = DarwinBoolean(false)
                        let capability = AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &settable)
                        stage = "선택 지원 \(capability.rawValue)/\(settable.boolValue)"
                        guard capability == .success,
                              settable.boolValue, TextInserter.exactlyMatches(value(), expected),
                              matchesFocus(pid: pid, element: element) else { return false }
                        var selection = CFRange(location: range.location, length: range.length)
                        guard let selectionValue = AXValueCreate(.cfRange, &selection) else { return false }
                        let changed = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, selectionValue)
                        stage = "선택 설정 \(changed.rawValue) · 요청 \(range.location),\(range.length)"
                        guard changed == .success else { return false }
                        let startedAt = ContinuousClock.now
                        let ready = await waitForSelection(
                            isCurrent: { matchesFocus(pid: pid, element: element) },
                            hasExpectedText: { TextInserter.exactlyMatches(value(), expected) },
                            matchesSelection: { selectionMatches(element, range: range) }
                        )
                        stage = "선택 확인 \(ready) · \((ContinuousClock.now - startedAt).tenths)초"
                        return ready
                    },
                    hasFocus: {
                        guard matchesFocus(pid: pid, element: element) else { stage = "선택 뒤 포커스 불일치"; return false }
                        if posted { return true }
                        guard TextInserter.exactlyMatches(value(), expected) else { stage = "선택 뒤 본문 변경"; return false }
                        guard selectionMatches(element, range: range) else { stage = "선택 뒤 범위 변경"; return false }
                        return true
                    },
                    targetValue: { value() },
                    onDiagnostic: { diagnostic = "부분 수정 · \($0) · \(stage)" },
                    paste: {
                        stage = "붙여넣기 직전 검사"
                        guard matchesFocus(pid: pid, element: element), TextInserter.exactlyMatches(value(), expected),
                              selectionMatches(element, range: range) else { return false }
                        posted = TextInserter.postReplacement(deleting: replacement.isEmpty)
                        stage = "키 게시 \(posted)"
                        return posted
                    }
                )
                switch result {
                case .inserted: return .completed
                case .notReady, .writeFailed, .eventFailed: return .unavailable
                case .cancelled: return posted ? .unconfirmed : .cancelled
                case .unconfirmed, .postedWithoutVerification, .clipboardChanged: return .unconfirmed
                }
            },
            postReturn: {
                let source = CGEventSource(stateID: .combinedSessionState)
                guard let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
                else { return false }
                down.flags = []; up.flags = []
                down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
                return true
            },
            failureReason: { diagnostic }
        )
    }

    private static func selectionMatches(_ element: AXUIElement, range: NSRange) -> Bool {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return false }
        var selected = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &selected)
            && selected.location == range.location && selected.length == range.length
    }

    private static func focusedElement(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let value = attribute(app, kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.1)
        return element
    }

    private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
}
