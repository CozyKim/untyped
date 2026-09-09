import AppKit
import Foundation
import ApplicationServices

enum HotkeySpike {
    /// 오른쪽 Option 키의 가상 키코드
    static let rightOption: UInt16 = 61

    @MainActor
    private static var monitor: Any?
    @MainActor
    private static var isDown = false

    @MainActor
    private static let logPath = "/tmp/typeless-hotkey-spike.log"

    @MainActor
    private static var trustCheckTimer: Timer?
    @MainActor
    private static var trustCheckCount = 0

    @MainActor
    static func start() {
        do {
            try "".write(toFile: logPath, atomically: true, encoding: .utf8)
        } catch {
        }

        let trusted = AXIsProcessTrusted()
        let trustStatus = trusted ? "있음" : "없음"
        appendLog("[HotkeySpike] 손쉬운 사용 권한: \(trustStatus)")

        startTrustStatusPolling()

        appendLog("[HotkeySpike] 감시 시작")

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            MainActor.assumeIsolated {
                handleFlagsEvent(event)
            }
        }
    }

    @MainActor
    private static func startTrustStatusPolling() {
        trustCheckCount = 0

        trustCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                trustCheckCount += 1
                let trusted = AXIsProcessTrusted()
                let trustStatus = trusted ? "있음" : "없음"
                appendLog("[HotkeySpike] 손쉬운 사용 권한: \(trustStatus)")

                if trustCheckCount >= 20 {
                    trustCheckTimer?.invalidate()
                    trustCheckTimer = nil
                }
            }
        }
    }

    @MainActor
    private static func handleFlagsEvent(_ event: NSEvent) {
        let timestamp = ISO8601DateFormatter().string(from: Date())

        if event.keyCode != rightOption {
            appendLog("[\(timestamp)] [HotkeySpike] 키코드 \(event.keyCode) (무시됨)")
            return
        }

        let down = event.modifierFlags.contains(.option)
        guard down != isDown else { return }
        isDown = down

        let message = down ? "오른쪽 Option 눌림" : "오른쪽 Option 뗌"
        appendLog("[\(timestamp)] [HotkeySpike] \(message)")
    }

    @MainActor
    private static func appendLog(_ line: String) {
        let lineWithNewline = line + "\n"
        if let data = lineWithNewline.data(using: .utf8) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        }
    }
}
