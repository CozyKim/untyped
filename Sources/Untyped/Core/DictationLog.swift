import Foundation

/// 받아쓰기 한 번의 원문과 결과를 사람이 읽을 수 있는 텍스트로 파일에 남긴다.
/// 말한 내용이 전부 남으므로 설정 파일과 같은 소유자 전용 폴더에 0600으로 둔다.
/// 오디오도 UI도 모른다 — 문자열과 파일 경로만 다룬다.
enum DictationLog {
    /// 이보다 커지면 `.1`로 밀어내고 새로 시작한다. 무한히 자라지 않게 하는 것이
    /// 목적이라 세대는 하나만 둔다.
    static let maxBytes = 5_000_000

    static var fileURL: URL? {
        AppConfig.fileURL?.deletingLastPathComponent()
            .appendingPathComponent("dictation.log", isDirectory: false)
    }

    static func entry(
        raw: String, outcome: RefineOutcome, recorded: Duration,
        at date: Date, timeZone: TimeZone = .current, cause: String? = nil
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let seconds = Double(recorded.components.seconds)
            + Double(recorded.components.attoseconds) / 1e18
        let status = switch outcome {
        case .refined: "다듬음"
        case .fallback(_, let reason): "원본 (\(reason.label))"
        }
        // 원인은 헤더 바로 아래에 둔다. 무슨 일이 있었는지를 본문(STT·결과)보다 먼저 읽게 한다.
        let causeLine = cause.map { "원인: \($0)\n" } ?? ""
        return """
        [\(formatter.string(from: date))] 녹음 \(String(format: "%.1f", seconds))초 · \(status)
        \(causeLine)STT : \(raw)
        결과: \(outcome.text)

        """
    }

    static func append(_ entry: String, to url: URL, maxBytes: Int = maxBytes) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if let size = try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int,
           size >= maxBytes {
            let rotated = url.appendingPathExtension("1")
            try? fileManager.removeItem(at: rotated)
            try fileManager.moveItem(at: url, to: rotated)
        }
        if !fileManager.fileExists(atPath: url.path) {
            guard fileManager.createFile(
                atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(entry.utf8))
    }
}
