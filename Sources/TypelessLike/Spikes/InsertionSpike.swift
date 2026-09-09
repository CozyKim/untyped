import AppKit

final class SpikePanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

enum InsertionSpike {
    static func makePanel() -> SpikePanel {
        let panel = SpikePanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 56),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        let label = NSTextField(labelWithString: "오버레이 표시 중")
        label.frame = NSRect(x: 16, y: 16, width: 190, height: 24)
        panel.contentView?.addSubview(label)
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 110, y: f.minY + 120))
        }
        return panel
    }

    static func insert(_ text: String, restoreDelayMs: Int) {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        let vKeyV: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKeyV, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKeyV, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(restoreDelayMs)) {
            pb.clearContents()
            if let saved { pb.setString(saved, forType: .string) }
        }
    }

    static func run(restoreDelayMs: Int) {
        let panel = makePanel()
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            insert("삽입 테스트 \(restoreDelayMs)ms", restoreDelayMs: restoreDelayMs)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { panel.orderOut(nil) }
        }
    }
}
