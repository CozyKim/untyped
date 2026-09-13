import AppKit
import ApplicationServices

/// 완성된 문자열의 전달을 직렬화한다. 이벤트 게시는 수신 완료가 아니다.
enum TextInserter {
    enum Result: Equatable, Sendable {
        case inserted
        case notReady
        case clipboardChanged
        case writeFailed
        case eventFailed
        case unconfirmed
        case cancelled
    }

    static let pasteSettleTimeout: Duration = .seconds(3)
    @MainActor private static var busy = false

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    static func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// 준비(앱 활성화)부터 수신 확인·클립보드 복원까지 한 트랜잭션으로 실행한다.
    @MainActor
    @discardableResult
    static func insert(
        _ text: String, pressReturn: Bool = false,
        prepare: () async -> Bool = { true },
        hasFocus: (() -> Bool?)? = nil,
        onDiagnostic: (String) -> Void = { _ in }
    ) async -> Result {
        guard hasAccessibilityPermission else {
            onDiagnostic("게시 전 중단 · 접근성 권한 없음")
            return .notReady
        }
        var recipient: pid_t?
        var focused: AXUIElement?
        var focusFailure: String?
        return await insert(
            text, into: .general,
            prepare: {
                guard await prepare() else { return false }
                recipient = NSWorkspace.shared.frontmostApplication?.processIdentifier
                focused = focusedElement()
                return recipient != nil
            },
            hasFocus: {
                guard let recipient else { return false }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == recipient else {
                    focusFailure = "앞 앱 변경"
                    return false
                }
                if let focused {
                    guard let current = focusedElement() else {
                        focusFailure = "현재 입력 요소 조회 실패"
                        return nil
                    }
                    guard CFEqual(focused, current) else {
                        focusFailure = "입력 요소 변경"
                        return false
                    }
                }
                let state = TargetApp.keyboardFocusState(pid: recipient)
                guard state == true else {
                    focusFailure = state == nil ? "키보드 포커스 조회 실패" : "키보드 포커스 변경"
                    return state
                }
                if let hasFocus {
                    let additional = hasFocus()
                    guard additional == true else {
                        focusFailure = additional == nil ? "대상 앱 포커스 조회 실패" : "대상 앱 포커스 조건 불일치"
                        return additional
                    }
                }
                focusFailure = nil
                return true
            },
            targetValue: {
                // 활성화 직후 AX 트리가 아직 준비되지 않았으면 다음 기준값 조회에서 다시 찾는다.
                if focused == nil { focused = focusedElement() }
                return focused.flatMap(elementValue)
            },
            onDiagnostic: { message in
                onDiagnostic(message + (focusFailure.map { " · " + $0 } ?? ""))
            },
            paste: { postKey(vKeyV, flags: .maskCommand) },
            submit: pressReturn ? { postKey(vKeyReturn) } : nil
        )
    }

    /// 이름 있는 실제 pasteboard와 수신 앱 경계를 주입할 수 있다. 본문은 로그에 남기지 않는다.
    /// timeout은 성공을 뜻하지 않는다. 수신을 확인하지 못하면 새 텍스트를 유지하고 재전송하지 않는다.
    @MainActor
    @discardableResult
    static func insert(
        _ text: String, into pasteboard: NSPasteboard,
        timeout: Duration = pasteSettleTimeout,
        prepare: () async -> Bool = { true },
        hasFocus: () -> Bool? = { true },
        targetValue: () -> String? = { nil },
        onDiagnostic: (String) -> Void = { _ in },
        paste: () -> Bool,
        submit: (() -> Bool)? = nil
    ) async -> Result {
        var posted = false
        // 모든 종료 경로의 진단을 호출자에게 넘긴다. 저장 위치·설정은 Coordinator가 결정한다.
        func report(_ result: Result, detail: String? = nil) -> Result {
            let summary: String
            switch result {
            case .inserted: summary = "수신 확인"
            case .notReady: summary = "게시 전 중단 · 텍스트 또는 활성화·포커스 확인 실패"
            case .clipboardChanged: summary = "클립보드 소유권 변경"
            case .writeFailed: summary = "클립보드 읽기·쓰기 검증 실패"
            case .eventFailed: summary = "키 이벤트 생성 실패"
            case .unconfirmed: summary = "수신 미확인"
            case .cancelled: summary = "취소됨"
            }
            onDiagnostic((detail ?? summary) + (posted ? " · ⌘V 게시 후" : " · ⌘V 게시 전"))
            return result
        }
        // nil일 때만 기다린다. false(다른 앱/요소)는 즉시 거부하며 추측해서 게시하지 않는다.
        func waitForFocus(until deadline: ContinuousClock.Instant) async -> Bool? {
            while !Task.isCancelled {
                if let state = hasFocus() { return state }
                guard ContinuousClock.now < deadline else { return nil }
                do { try await Task.sleep(for: .milliseconds(10)) }
                catch { return nil }
            }
            return nil
        }
        guard !text.isEmpty else { return report(.notReady) }
        // MainActor는 await 사이의 재진입을 막지 않는다. 대기자가 잠금을 얻은 뒤에만 활성화한다.
        while busy {
            do { try await Task.sleep(for: .milliseconds(10)) }
            catch { return report(.cancelled) }
        }
        guard !Task.isCancelled else { return report(.cancelled) }
        busy = true
        defer { busy = false }
        guard await prepare() else { return report(.notReady) }
        let preparationDeadline = ContinuousClock.now + timeout
        guard await waitForFocus(until: preparationDeadline) == true else {
            return report(Task.isCancelled ? .cancelled : .notReady)
        }
        guard !Task.isCancelled else { return report(.cancelled) }
        var before: String?

        // 소유권을 넘기기 전에 모든 표현을 materialize한다. 읽지 못한 표현이 있으면 손실 없이 중단한다.
        let originalCount = pasteboard.changeCount
        var savedItems: [NSPasteboardItem] = []
        for item in pasteboard.pasteboardItems ?? [] {
            let saved = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type), saved.setData(data, forType: type) else {
                    return report(.writeFailed)
                }
            }
            savedItems.append(saved)
        }
        guard await waitForFocus(until: preparationDeadline) == true else {
            return report(Task.isCancelled ? .cancelled : .notReady)
        }
        // 재조회가 await를 거쳤으므로 스냅샷 이후 외부 복사가 없었는지 다시 검사한다.
        guard pasteboard.changeCount == originalCount else { return report(.clipboardChanged) }

        let ownedCount = pasteboard.clearContents()
        let wrote = pasteboard.setString(text, forType: .string)
        // clearContents가 소유권 세대를 바꾼다. setString은 같은 세대에 데이터를 채운다.
        // readback과 changeCount를 함께 확인해야 외부 소유자가 쓴 같은 문자열도 구분된다.
        guard pasteboard.changeCount == ownedCount else { return report(.clipboardChanged) }
        guard wrote, pasteboard.string(forType: .string) == text else {
            restore(savedItems, to: pasteboard, ifOwned: ownedCount)
            return report(.writeFailed)
        }
        guard pasteboard.changeCount == ownedCount else { return report(.clipboardChanged) }
        // 마지막 대기 뒤의 값을 기준으로 삼는다. 앞서 읽은 값을 보관하면 대기 중 사용자가
        // 입력한 문장을 이번 붙여넣기의 결과로 오인할 수 있다. 기준값 이후 await가 생기면 다시 읽는다.
        let baselineDeadline = min(preparationDeadline, ContinuousClock.now + .milliseconds(300))
        while true {
            guard await waitForFocus(until: preparationDeadline) == true else {
                restore(savedItems, to: pasteboard, ifOwned: ownedCount)
                return report(Task.isCancelled ? .cancelled : .notReady)
            }
            guard pasteboard.changeCount == ownedCount else { return report(.clipboardChanged) }
            before = targetValue()
            let focus = hasFocus()
            if focus == false {
                restore(savedItems, to: pasteboard, ifOwned: ownedCount)
                return report(.notReady)
            }
            guard pasteboard.changeCount == ownedCount else { return report(.clipboardChanged) }
            if focus == true, before != nil || ContinuousClock.now >= baselineDeadline { break }
            guard ContinuousClock.now < preparationDeadline else {
                restore(savedItems, to: pasteboard, ifOwned: ownedCount)
                return report(.notReady)
            }
            do { try await Task.sleep(for: .milliseconds(10)) }
            catch {
                restore(savedItems, to: pasteboard, ifOwned: ownedCount)
                return report(.cancelled)
            }
        }
        guard paste() else {
            restore(savedItems, to: pasteboard, ifOwned: ownedCount)
            return report(.eventFailed)
        }

        posted = true
        let deadline = ContinuousClock.now + timeout
        while true {
            guard !Task.isCancelled else { return report(.cancelled) }
            let focus = hasFocus()
            if focus == false {
                return report(.unconfirmed, detail: "포커스 변경으로 수신 미확인")
            }
            guard pasteboard.changeCount == ownedCount else { return report(.clipboardChanged) }
            var focusUnavailable = focus == nil
            let after = focus == true ? targetValue() : nil
            if focus == true, received(text, before: before, after: after) {
                let finalFocus = hasFocus()
                if finalFocus == false {
                    return report(.unconfirmed, detail: "수신 관측 중 포커스 변경")
                }
                guard pasteboard.changeCount == ownedCount else { return report(.clipboardChanged) }
                focusUnavailable = finalFocus == nil
                if finalFocus == true {
                    if let submit, !submit() {
                        restore(savedItems, to: pasteboard, ifOwned: ownedCount)
                        return report(.eventFailed)
                    }
                    restore(savedItems, to: pasteboard, ifOwned: ownedCount)
                    return report(.inserted)
                }
            }
            guard ContinuousClock.now < deadline else {
                let baseline = before == nil ? "읽기 불가" : "읽기 가능"
                let current = after == nil ? "읽기 불가" : "읽기 가능"
                let focusDetail = focusUnavailable ? " · 포커스 조회 불가" : ""
                return report(.unconfirmed, detail: "확인 시간 초과 · 사전 값 \(baseline) · 현재 값 \(current)\(focusDetail)")
            }
            do { try await Task.sleep(for: .milliseconds(10)) }
            catch { return report(.cancelled) }
        }
    }

    /// 과거 내용이나 동일한 끝 20글자는 수신 증거가 아니다. 전체 텍스트가 새로 나타나야 한다.
    /// 이미 같은 문장이 있으면 개수가 증가해야 한다. 동일 선택 영역 치환은 보수적으로 미확인 처리한다.
    static func received(_ text: String, before: String?, after: String?) -> Bool {
        guard let before, let after, before != after, !text.isEmpty else { return false }
        return after.components(separatedBy: text).count > before.components(separatedBy: text).count
    }

    @MainActor
    private static func restore(_ items: [NSPasteboardItem], to board: NSPasteboard, ifOwned count: Int) {
        guard board.changeCount == count else { return }
        board.clearContents()
        if !items.isEmpty { board.writeObjects(items) }
    }

    private static let vKeyV: CGKeyCode = 9
    private static let vKeyReturn: CGKeyCode = 36

    private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// 관측 대상 요소를 게시 전에 고정한다. 뒤늦게 바뀐 다른 앱/입력창을 성공 증거로 쓰지 않는다.
    private static func focusedElement() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var element: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &element) == .success,
              let element else { return nil }
        let focused = element as! AXUIElement
        AXUIElementSetMessagingTimeout(focused, 0.1)
        return focused
    }

    private static func elementValue(_ focused: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
