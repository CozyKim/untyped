import AppKit

enum HotkeySpike {
    /// 오른쪽 Option 키의 가상 키코드
    static let rightOption: UInt16 = 61

    @MainActor
    private static var monitor: Any?
    @MainActor
    private static var isDown = false

    @MainActor
    static func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            guard event.keyCode == rightOption else { return }
            let down = event.modifierFlags.contains(.option)
            guard down != isDown else { return }
            isDown = down
            NSLog("[HotkeySpike] 오른쪽 Option %@", down ? "눌림" : "뗌")
        }
        NSLog("[HotkeySpike] 감시 시작")
    }
}
