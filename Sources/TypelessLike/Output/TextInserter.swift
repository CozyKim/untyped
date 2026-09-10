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

    static func insert(_ text: String) async {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postCommandV()

        try? await Task.sleep(for: restoreDelay)
        pasteboard.clearContents()
        if let saved {
            pasteboard.setString(saved, forType: .string)
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
