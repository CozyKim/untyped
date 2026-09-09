import AppKit
import SwiftUI

@main
struct MenuBarApp: App {
    var body: some Scene {
        MenuBarExtra("TypelessLike", systemImage: "mic") {
            Button("종료") { NSApplication.shared.terminate(nil) }
        }
    }
}
