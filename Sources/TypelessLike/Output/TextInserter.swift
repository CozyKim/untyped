import AppKit
import ApplicationServices

/// 완성된 문자열만 받는다. 전사도 다듬기도 모른다.
enum TextInserter {
    /// 붙여넣기가 클립보드를 읽기 전에 복원하면 옛 내용이 들어간다.
    /// 세 가지 지연값(50, 150, 400ms)을 여러 앱에서 실측한 결과 모두 성공했다.
    /// 150ms를 택한 이유는 복원이 너무 빠르면 붙여넣기가 옛 내용을 집어가는 무언의 실패를
    /// 피하기 위함이다. 지연을 늘려도 사용자가 인지할 수 있는 비용이 없으므로 여유 있는 값을 선택했다.
    static let restoreDelay: Duration = .milliseconds(150)

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        // Swift 6 strict concurrency에서 C global kAXTrustedCheckOptionPrompt 직접 참조 불가.
        // 이 상수의 문서된 문자열 값은 "AXTrustedCheckOptionPrompt"이므로 리터럴로 사용한다.
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// 완료된 텍스트를 클립보드 경유로 삽입한다. 동시 호출은 인정되지 않는다.
    /// 두 호출이 겹치면 각 호출이 자신의 변경 수 검사로만 보호되므로
    /// 첫 번째 호출의 받아쓰기 내용이 남거나 클립보드가 완전히 비게 된다.
    /// 호출자는 이 함수의 동시성을 직렬화해야 한다.
    @MainActor
    static func insert(_ text: String) async {
        guard !text.isEmpty else { return }

        // Accessibility 권한이 없으면 CGEventPost가 무음으로 실패하고 클립보드만 손상된다.
        // 사전에 검사하여 변경 없이 반환하는 것이 낫다.
        guard hasAccessibilityPermission else { return }

        let pasteboard = NSPasteboard.general

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

        postCommandV()

        try? await Task.sleep(for: restoreDelay)

        // 다른 프로세스가 클립보드에 개입하지 않았으면 원래 내용으로 복원한다.
        guard pasteboard.changeCount == myChangeCount else { return }
        pasteboard.clearContents()
        if !savedItems.isEmpty {
            pasteboard.writeObjects(savedItems)
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyV: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyV, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
