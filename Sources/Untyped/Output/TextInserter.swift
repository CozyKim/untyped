import AppKit
import ApplicationServices

/// 앱 종류와 관계없이 키 이벤트 게시를 전송 완료로 처리한다. 수신 값은 조회하지 않는다.
enum TextInserter {
    enum Result: Equatable, Sendable {
        case posted
        case notReady
        case clipboardChanged
        case writeFailed
        case eventFailed
        case cancelled
    }

    static let focusTimeout: Duration = .seconds(3)
    /// 수신 검증이 아닌 이벤트 처리 여유. 다음 전송이 클립보드를 즉시 덮어쓰지 않게 한다.
    static let pasteSettleDelay: Duration = .milliseconds(200)
    @MainActor private static var busy = false

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    static func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

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
            onDiagnostic: { message in
                onDiagnostic(message + (focusFailure.map { " · " + $0 } ?? ""))
            },
            paste: { postKey(vKeyV, flags: .maskCommand) },
            submit: pressReturn ? { postKey(vKeyReturn) } : nil
        )
    }

    /// 게시 전 실패만 원래 클립보드를 복원한다. 게시 뒤에는 대상 앱의 늦은 읽기를 위해
    /// 보낸 문자열을 남긴다. 이벤트 게시를 신뢰하며 수신 확인이나 자동 재전송은 하지 않는다.
    @MainActor
    @discardableResult
    static func insert(
        _ text: String, into pasteboard: NSPasteboard,
        timeout: Duration = focusTimeout,
        settleDelay: Duration = pasteSettleDelay,
        prepare: () async -> Bool = { true },
        hasFocus: () -> Bool? = { true },
        onDiagnostic: (String) -> Void = { _ in },
        paste: () -> Bool,
        submit: (() -> Bool)? = nil
    ) async -> Result {
        var posted = false
        func report(_ result: Result, detail: String? = nil) -> Result {
            let summary: String
            switch result {
            case .posted: summary = "전송 완료"
            case .notReady: summary = "게시 전 중단 · 텍스트 또는 활성화·포커스 확인 실패"
            case .clipboardChanged: summary = "클립보드 소유권 변경"
            case .writeFailed: summary = "클립보드 읽기·쓰기 검증 실패"
            case .eventFailed: summary = "키 이벤트 전송 실패"
            case .cancelled: summary = "취소됨"
            }
            onDiagnostic((detail ?? summary) + (posted ? " · ⌘V 게시 후" : " · ⌘V 게시 전"))
            return result
        }
        // 포커스 조회 실패만 잠시 기다린다. 다른 앱이 명시적으로 확인되면 즉시 중단한다.
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

        // 게시 전 중단 때 손실 없이 돌려놓을 수 있도록 모든 표현을 읽어 둔다.
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
        guard pasteboard.changeCount == originalCount else { return report(.clipboardChanged) }

        let ownedCount = pasteboard.clearContents()
        let wrote = pasteboard.setString(text, forType: .string)
        guard pasteboard.changeCount == ownedCount else { return report(.clipboardChanged) }
        guard wrote, pasteboard.string(forType: .string) == text else {
            restore(savedItems, to: pasteboard, ifOwned: ownedCount)
            return report(.writeFailed)
        }
        guard await waitForFocus(until: preparationDeadline) == true else {
            restore(savedItems, to: pasteboard, ifOwned: ownedCount)
            return report(Task.isCancelled ? .cancelled : .notReady)
        }
        guard pasteboard.changeCount == ownedCount else { return report(.clipboardChanged) }
        guard paste() else {
            restore(savedItems, to: pasteboard, ifOwned: ownedCount)
            return report(.eventFailed)
        }
        posted = true

        // ⌘V와 Return의 순서 및 대상 앱 복귀를 위한 여유만 둔다. AXValue는 읽지 않는다.
        do { try await Task.sleep(for: settleDelay) }
        catch { return report(.cancelled) }
        guard !Task.isCancelled else { return report(.cancelled) }
        guard pasteboard.changeCount == ownedCount else { return report(.clipboardChanged) }
        if let submit {
            guard hasFocus() == true else {
                return report(.eventFailed, detail: "붙여넣기 전송됨 · 포커스 확인 실패로 Return 생략")
            }
            guard submit() else {
                return report(.eventFailed, detail: "붙여넣기 전송됨 · Return 키 이벤트 전송 실패")
            }
        }
        return report(.posted)
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

    /// 입력값의 수신 검증과 별개로, 처음 선택한 입력창에 보내는지는 확인한다.
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
}
