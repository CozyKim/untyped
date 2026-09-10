import AppKit
import ApplicationServices
import Darwin

/// 완성된 문자열만 받는다. 전사도 다듬기도 모른다.
enum TextInserter {
    /// 붙여넣기가 클립보드를 읽기 전에 복원하면 옛 내용이 들어간다.
    /// 여러 앱에서 실측해 실패하지 않은 가장 작은 값이다.
    static let restoreDelay: Duration = .milliseconds(150)

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        // Swift 6 strict concurrency에서 C global 접근을 위해 helper 함수 사용.
        // kAXTrustedCheckOptionPrompt는 불변 프레임워크 상수이며 안전하다.
        let key = _accessibilityPromptKeyUnsafe()
        let options = [key: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func _accessibilityPromptKeyUnsafe() -> String {
        // dlsym으로 동적으로 symbol을 조회하여 Swift 6 concurrency 체크 우회.
        // kAXTrustedCheckOptionPrompt는 ApplicationServices framework의 불변 상수이다.
        let handle = dlopen(nil, RTLD_LAZY)
        defer { if handle != nil { dlclose(handle) } }

        if let sym = dlsym(handle, "kAXTrustedCheckOptionPrompt") {
            let cfString = unsafeBitCast(sym, to: CFString.self)
            return cfString as String
        }
        // Fallback: 알려진 상수값으로 대체
        return "AXTrustedCheckOptionPrompt"
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
