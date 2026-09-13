import Foundation

/// 받아쓰기 한 번에서 STT와 LLM이 걸린 시간. 녹음 길이는 헤더에 있으므로 여기엔 없다.
/// 경로마다 단계가 달라 한 줄의 모양도 다르다 — 어느 단계가 느렸는지 로그만 보고 가려야 한다.
enum DictationTiming: Equatable, Sendable {
    /// 2단계 — 키를 뗀 뒤 최종 전사가 나오기까지(STT)와 LLM 텍스트 다듬기 요청. 다듬기가 시간 초과·
    /// 실패로 끝났으면 그때까지 기다린 시간이다.
    case apple(transcription: Duration, refinement: Duration)
    /// 1단계 — 오디오를 보낸 LLM 요청 하나. 전사와 다듬기가 한 요청이라 나눌 수 없다.
    case llmAudio(request: Duration)

    var line: String {
        switch self {
        case .apple(let transcription, let refinement):
            "STT \(transcription.tenths)초 · 다듬기 \(refinement.tenths)초"
        case .llmAudio(let request):
            "오디오 다듬기 \(request.tenths)초"
        }
    }
}

extension Duration {
    /// 로그용 소수 첫째 자리 초("7.2"). 초 단위 이하는 로그를 읽는 사람에게 의미가 없다.
    var tenths: String {
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return String(format: "%.1f", seconds)
    }
}

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

    /// raw가 nil이면 오디오를 LLM에 한 요청으로 보낸 경우다 — 원문이 없으므로 STT 줄을 쓰지 않고
    /// 헤더에 그 사실을 남긴다.
    static func entry(
        raw: String?, outcome: RefineOutcome, recorded: Duration,
        at date: Date, timeZone: TimeZone = .current, cause: String? = nil,
        timing: DictationTiming? = nil, insertion: String? = nil
    ) -> String {
        let status = switch outcome {
        case .refined: raw == nil ? "오디오에서 바로 다듬음" : "다듬음"
        case .fallback(_, let reason): "원본 (\(reason.label))"
        }
        let insertionLine = insertion.map { "입력: \($0)\n" } ?? ""
        let sttLine = raw.map { "STT : \($0)\n" } ?? ""
        return """
        \(header(status: status, recorded: recorded, at: date, timeZone: timeZone))
        \(timingLine(timing))\(causeLine(cause))\(insertionLine)\(sttLine)결과: \(outcome.text)

        """
    }

    /// 아무것도 넣지 않은 받아쓰기 — 오디오를 한 요청으로 다듬다 실패해 원문도 결과도 없다.
    static func failureEntry(
        label: String, recorded: Duration,
        at date: Date, timeZone: TimeZone = .current, cause: String? = nil,
        timing: DictationTiming? = nil
    ) -> String {
        header(status: "삽입 안 함 (\(label))", recorded: recorded, at: date, timeZone: timeZone)
            + "\n" + timingLine(timing) + causeLine(cause)
    }

    private static func header(
        status: String, recorded: Duration, at date: Date, timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "[\(formatter.string(from: date))] 녹음 \(recorded.tenths)초 · \(status)"
    }

    /// 소요 시간은 헤더 바로 아래, 원인보다 먼저 둔다 — 헤더의 녹음 길이와 나란히 읽히고, 원인 줄이
    /// 말하는 "응답 없음"이 몇 초를 기다린 것인지가 바로 위에 있다. 없으면 줄을 만들지 않아
    /// 이전 형식과 같다.
    private static func timingLine(_ timing: DictationTiming?) -> String {
        timing.map { "소요: \($0.line)\n" } ?? ""
    }

    /// 원인은 무슨 일이 있었는지를 본문(STT·결과)보다 먼저 읽게 한다.
    private static func causeLine(_ cause: String?) -> String {
        cause.map { "원인: \($0)\n" } ?? ""
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
