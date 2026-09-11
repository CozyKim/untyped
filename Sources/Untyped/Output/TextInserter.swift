import AppKit
import ApplicationServices

/// 완성된 문자열만 받는다. 전사도 다듬기도 모른다.
enum TextInserter {
    /// 붙여넣기가 클립보드를 읽기 전에 복원하면 옛 내용이 대신 붙여넣어진다.
    /// 옛 내용은 직전 받아쓰기 후 복원해 둔 사용자의 클립보드이므로, 이 실패는
    /// "다시 녹음해도 직전에 삽입된 문장이 그대로 들어가는" 증상으로 나타난다.
    ///
    /// 150ms는 TextEdit 같은 가벼운 앱에서는 충분했지만, Obsidian 등 Chromium·Electron
    /// 계열은 붙여넣기가 렌더러↔브라우저 프로세스 IPC를 거치고 다듬기 서버가 GPU를
    /// 막 쓰고 난 직후엔 더 느려져 150ms를 넘길 수 있다.
    ///
    /// macOS는 붙여넣기가 클립보드를 읽었는지 알려주지 않는다. NSPasteboardItemDataProvider로
    /// "읽힘" 시점을 잡는 방법은 Raycast 같은 클립보드 히스토리가 대상 앱보다 먼저 읽어 가면
    /// 오히려 더 일찍 복원되므로 쓸 수 없다. 남는 선택은 넉넉한 고정 지연이다.
    /// 복원은 호출자를 기다리게 하지 않으므로(아래 `pendingRestore`) 지연을 늘려도 오버레이나
    /// 다음 받아쓰기 시작이 늦어지지 않는다. 너무 짧으면 잘못된 텍스트가 조용히 들어가고,
    /// 너무 길면 그 사이 사용자가 직접 Cmd+V를 눌렀을 때 받아쓰기 텍스트가 나오는 정도이므로
    /// 긴 쪽으로 여유 있게 잡는다.
    static let restoreDelay: Duration = .seconds(1)

    /// ⌘V 뒤 붙여넣은 텍스트가 실제로 입력창에 나타날 때까지 기다리는 상한. 그 전에 Return을
    /// 보내면 빈 입력창에 눌려 아무 일도 안 일어나고 그 뒤에 텍스트만 들어온다. 나타나는
    /// 시점은 한가할 때도 TextEdit 220ms, Chromium 입력창 126ms로 앱과 부하에 따라 달라
    /// 고정 지연으로는 맞출 수 없다. 값을 노출하지 않는 앱을 위해 상한 뒤에는 그냥 보낸다.
    static let pasteSettleTimeout: Duration = .seconds(1)

    /// 직전 삽입의 복원 작업. 다음 삽입은 스냅샷을 뜨기 전에 이 작업을 기다린다.
    @MainActor
    private static var pendingRestore: Task<Void, Never>?

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        // Swift 6 strict concurrency에서 C global kAXTrustedCheckOptionPrompt 직접 참조 불가.
        // 이 상수의 문서된 문자열 값은 "AXTrustedCheckOptionPrompt"이므로 리터럴로 사용한다.
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// 완료된 텍스트를 클립보드 경유로 삽입한다. 붙여넣기 이벤트를 보낸 직후 반환하며
    /// 클립보드 복원은 `restoreDelay` 뒤에 따로 이루어진다.
    /// 동시 호출은 인정되지 않는다. 두 호출이 겹치면 각 호출이 자신의 변경 수 검사로만
    /// 보호되므로 첫 번째 호출의 받아쓰기 내용이 남거나 클립보드가 완전히 비게 된다.
    /// 호출자는 이 함수의 동시성을 직렬화해야 한다.
    @MainActor
    static func insert(_ text: String, pressReturn: Bool = false) async {
        guard !text.isEmpty else { return }

        // Accessibility 권한이 없으면 CGEventPost가 무음으로 실패하고 클립보드만 손상된다.
        // 사전에 검사하여 변경 없이 반환하는 것이 낫다.
        guard hasAccessibilityPermission else { return }

        await insert(text, into: .general, paste: postCommandV)
        if pressReturn {
            await waitUntilPasted(text)
            postKey(vKeyReturn)
        }
    }

    /// 클립보드와 붙여넣기 동작을 주입받는 핵심 경로. 테스트는 이름 있는 pasteboard와
    /// 아무것도 하지 않는 `paste`를 넘겨, 테스트 자신이 "클립보드를 읽는 앱" 역할을 한다.
    @MainActor
    static func insert(_ text: String, into pasteboard: NSPasteboard, paste: () -> Void) async {
        // 직전 삽입의 복원이 아직 남아 있으면 먼저 끝낸다. 지금 스냅샷을 뜨면 원래 클립보드가
        // 아니라 직전 받아쓰기 텍스트를 담게 되고, 직전 복원은 변경 수 불일치로 건너뛰어져
        // 사용자의 원래 클립보드가 영영 사라진다.
        await pendingRestore?.value

        // 클립보드 전체 스냅샷 생성. lazy file promise는 clearContents()로 소유권을 잃으면
        // 콜백을 다시 호출할 수 없으므로 복원 불가능하다. 손실은 불가피하다.
        var savedItems: [NSPasteboardItem] = []
        if let items = pasteboard.pasteboardItems {
            for item in items {
                let newItem = NSPasteboardItem()
                for typeStr in item.types {
                    if let data = item.data(forType: typeStr) {
                        newItem.setData(data, forType: typeStr)
                    }
                }
                savedItems.append(newItem)
            }
        }

        let myChangeCount = pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        paste()

        // 복원을 호출자와 분리한다. 호출자는 삽입이 끝나면 곧바로 오버레이를 내리고
        // 다음 받아쓰기를 받을 수 있어야 하므로 복원 지연이 그 경로를 막아서는 안 된다.
        pendingRestore = Task { @MainActor in
            try? await Task.sleep(for: restoreDelay)

            // 다른 프로세스가 클립보드에 개입하지 않았으면 원래 내용으로 복원한다.
            guard pasteboard.changeCount == myChangeCount else { return }
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                pasteboard.writeObjects(savedItems)
            }
        }
    }

    /// HIToolbox/Events.h의 kVK_* 값.
    private static let vKeyV: CGKeyCode = 9
    private static let vKeyReturn: CGKeyCode = 36

    private static func postCommandV() {
        postKey(vKeyV, flags: .maskCommand)
    }

    private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// 붙여넣은 텍스트의 끝부분이 포커스된 요소의 값에 나타날 때까지 기다린다.
    /// 끝부분만 비교하는 이유: 입력창에 이미 다른 내용이 있을 수 있고, 앱이 줄바꿈을
    /// 문단으로 바꾸는 등 앞부분을 다르게 표현할 수 있다.
    @MainActor
    private static func waitUntilPasted(_ text: String) async {
        let tail = String(text.trimmingCharacters(in: .whitespacesAndNewlines).suffix(20))
        guard !tail.isEmpty else { return }
        let deadline = ContinuousClock.now + pasteSettleTimeout
        while ContinuousClock.now < deadline {
            if focusedElementValue()?.contains(tail) == true { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// 앞에 있는 앱의 포커스된 요소가 노출하는 문자열 값. 텍스트 입력창이 아니거나 앱이
    /// 접근성 값을 제공하지 않으면 nil.
    private static func focusedElementValue() -> String? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var element: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &element) == .success,
              let element
        else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXValueAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
