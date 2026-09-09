import AppKit
import Foundation
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
                        // 오디오 레벨을 로깅하여 마이크 동작 여부를 확인한다.
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
    guard let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
        return
    }
    let typelesLogDir = logsDir.appendingPathComponent("Logs/TypelessLike", isDirectory: true)
    let logFile = typelesLogDir.appendingPathComponent("transcribe.log", isDirectory: false)

    do {
        try FileManager.default.createDirectory(at: typelesLogDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let lineWithNewline = line + "\n"
        guard let data = lineWithNewline.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = FileHandle(forWritingAtPath: logFile.path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try data.write(to: logFile)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logFile.path)
        }
    } catch {
    }
}
