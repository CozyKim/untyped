import Foundation

/// 사용자 설정. ~/Library/Application Support/TypelessLike/config.json에서 읽고 쓴다.
///
/// GUI 앱은 셸 환경변수를 물려받지 않으므로 API 키 같은 값은 환경변수로 전달할
/// 수 없다. 사용자가 직접 편집할 수 있는 파일로 대신하고, 설정 창은 이 파일의
/// 편집기다.
///
/// 다른 애플리케이션의 설정 파일(예: oMLX 자신의 ~/.omlx/settings.json)은 절대
/// 읽지 않는다 — 다듬기는 특정 서버가 아니라 OpenAI 호환 API를 쓰는 어떤 서버에도
/// 붙을 수 있어야 하기 때문이다.
struct AppConfig: Codable, Equatable, Sendable {
    var baseURL: URL
    var model: String
    var apiKey: String
    var hotkey: HotkeyKey
    var toggleEnabled: Bool
    /// nil이면 앱의 기본 프롬프트를 쓴다. 기본값과 같은 텍스트는 저장하지 않는다 —
    /// 파일에 박아 두면 나중에 기본 프롬프트가 개선돼도 한 번도 손대지 않은 사용자가
    /// 옛 프롬프트에 묶인다.
    var systemPrompt: String? = nil
    /// few-shot 예시를 프롬프트 뒤에 붙일지. 성격이 다른 프롬프트(예: 번역)는
    /// 예시가 지시보다 세게 작용해 무시되므로 끌 수 있어야 한다.
    var includeExamples: Bool = true
    /// 다듬기 응답의 최대 토큰. 결과가 이보다 길면 잘린 문장 대신 원본 전사를 넣는다.
    var maxTokens: Int = 900
    /// 받아쓰기마다 원문과 결과를 로그 파일에 남길지. 말한 내용이 전부 남으므로 끌 수 있다.
    var logEnabled: Bool = true

    private enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case model
        case apiKey = "api_key"
        case hotkey
        case toggleEnabled = "toggle_enabled"
        case systemPrompt = "system_prompt"
        case includeExamples = "include_examples"
        case maxTokens = "max_tokens"
        case logEnabled = "log_enabled"
    }

    static let defaultConfig = AppConfig(
        baseURL: URL(string: "http://127.0.0.1:8081/v1")!,
        model: "gemma-4-e2b-it-8bit",
        apiKey: "",
        hotkey: .rightOption,
        toggleEnabled: true
    )

    /// 빈 문자열은 "키 없음"으로 취급한다. 키를 요구하지 않는 서버에서는
    /// Authorization 헤더를 안 보내는 것이 유효한 상태다.
    var apiKeyOrNil: String? { apiKey.isEmpty ? nil : apiKey }

    /// 설정 파일의 실제 경로. 읽기·쓰기와 설정 창의 Finder 열기가 함께 쓴다.
    static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TypelessLike", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    /// 설정 파일을 읽는다. 파일이 없으면 이 기기를 위한 기본값으로 새로 만든다.
    /// 파일이 있지만 권한이 없거나 JSON이 잘못됐으면 기본값으로 대체한다 —
    /// 앱이 멈추거나 다듬기가 조용히 깨진 채로 남는 일은 없어야 한다.
    static func loadOrCreateDefault() -> AppConfig {
        guard let fileURL else { return defaultConfig }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            do {
                try save(defaultConfig, to: fileURL)
            } catch {
                // 기본 파일 생성에 실패해도 메모리 상의 기본값으로 계속 동작한다.
                NSLog("[AppConfig] 기본 설정 파일 생성 실패: %@", String(describing: error))
            }
            return defaultConfig
        }
        return load(from: fileURL) ?? defaultConfig
    }

    /// 파일이 없거나 읽을 수 없거나 JSON이 잘못됐으면 nil.
    static func load(from url: URL) -> AppConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    static func save(_ config: AppConfig) throws {
        guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
        try save(config, to: fileURL)
    }

    /// 디렉터리는 0700, 파일은 0600으로 만든다. API 키가 담기므로 소유자 외에는
    /// 읽을 수 없어야 한다. 호출자가 오류를 로그에 남길 때는 error만 남기고
    /// 설정값은 넣지 않는다.
    static func save(_ config: AppConfig, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        guard FileManager.default.createFile(
            atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

extension AppConfig {
    /// base_url·model·api_key 뒤에 추가된 필드들은 기존 파일에 없을 수 있다.
    /// hotkey가 모르는 문자열이어도 기본값으로 읽는다 — 이 필드 하나 때문에 파일
    /// 전체가 거부되어 API 키까지 기본값으로 대체되면 안 된다.
    ///
    /// 구조체 본문 안에 init을 쓰면 멤버별 init이 합성되지 않아 extension에 둔다.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decode(URL.self, forKey: .baseURL)
        model = try container.decode(String.self, forKey: .model)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        let rawHotkey = try container.decodeIfPresent(String.self, forKey: .hotkey)
        hotkey = rawHotkey.flatMap(HotkeyKey.init(rawValue:)) ?? Self.defaultConfig.hotkey
        toggleEnabled = try container.decodeIfPresent(Bool.self, forKey: .toggleEnabled)
            ?? Self.defaultConfig.toggleEnabled
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt)
        includeExamples = try container.decodeIfPresent(Bool.self, forKey: .includeExamples)
            ?? Self.defaultConfig.includeExamples
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
            ?? Self.defaultConfig.maxTokens
        logEnabled = try container.decodeIfPresent(Bool.self, forKey: .logEnabled)
            ?? Self.defaultConfig.logEnabled
    }
}
