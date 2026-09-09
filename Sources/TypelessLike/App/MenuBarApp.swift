import AppKit
import SwiftUI

@main
struct MenuBarApp: App {
    init() {
        HotkeySpike.start()
    }

    var body: some Scene {
        MenuBarExtra("TypelessLike", systemImage: "mic") {
            Button("스파이크 50ms") { InsertionSpike.run(restoreDelayMs: 50) }
            Button("스파이크 150ms") { InsertionSpike.run(restoreDelayMs: 150) }
            Button("스파이크 400ms") { InsertionSpike.run(restoreDelayMs: 400) }
            Divider()
            Button("종료") { NSApplication.shared.terminate(nil) }
        }
    }
}
