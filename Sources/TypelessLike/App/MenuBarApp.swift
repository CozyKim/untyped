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
            Button("전사 15초") {
                Task {
                    let format = try await Transcriber.targetAudioFormat()
                    let capture = AudioCapture(targetFormat: format) { level in
                        // 레벨은 Task 11에서 오버레이에 연결한다. 지금은 확인용으로만 찍는다.
                        if level > 0.05 {
                            appendTranscriptLog("[level] \(String(format: "%.3f", level))")
                        }
                    }
                    let transcriber = Transcriber()
                    let stream = try await capture.start()
                    try await transcriber.begin(inputSequence: stream)
                    try await Task.sleep(for: .seconds(15))
                    await capture.stop()
                    let text = try await transcriber.finish()
                    appendTranscriptLog("[전사] \(text)")
                }
            }
            Divider()
            Button("종료") { NSApplication.shared.terminate(nil) }
        }
    }
}

private func appendTranscriptLog(_ line: String) {
    let logPath = "/tmp/typeless-transcribe.log"
    let lineWithNewline = line + "\n"
    if let data = lineWithNewline.data(using: .utf8) {
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
        }
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }
}
