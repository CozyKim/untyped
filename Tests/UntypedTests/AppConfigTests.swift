import Testing
import Foundation
@testable import Untyped

private let sample = AppConfig(
    baseURL: URL(string: "http://localhost:11434/v1")!,
    model: "qwen3:8b",
    apiKey: "sk-test",
    hotkey: .rightCommand,
    toggleEnabled: false
)

private func temporaryFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("UntypedTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("config.json", isDirectory: false)
}

@Test func encodeDecodeRoundTrip() throws {
    let data = try JSONEncoder().encode(sample)
    #expect(try JSONDecoder().decode(AppConfig.self, from: data) == sample)
}

@Test func encodedKeysAreSnakeCase() throws {
    let data = try JSONEncoder().encode(sample)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == [
        "base_url", "model", "api_key", "hotkey", "toggle_enabled", "include_examples",
        "max_tokens", "log_enabled", "refine_timeout_seconds",
    ])
    #expect(object["base_url"] as? String == "http://localhost:11434/v1")
    #expect(object["hotkey"] as? String == "right_command")
    #expect(object["toggle_enabled"] as? Bool == false)
}

@Test func legacyFileWithoutNewFieldsUsesDefaultsAndKeepsOthers() throws {
    // hotkey와 toggle_enabled가 생기기 전에 만들어진 파일.
    let json = """
    {"api_key":"sk-legacy","base_url":"http://127.0.0.1:8081/v1","model":"gemma-4-e2b-it-8bit"}
    """
    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(decoded.apiKey == "sk-legacy")
    #expect(decoded.baseURL == URL(string: "http://127.0.0.1:8081/v1"))
    #expect(decoded.model == "gemma-4-e2b-it-8bit")
    #expect(decoded.hotkey == .rightOption)
    #expect(decoded.toggleEnabled == true)
}

@Test func unknownHotkeyFallsBackAndKeepsOtherFields() throws {
    let json = """
    {"api_key":"sk-keep","base_url":"http://127.0.0.1:8081/v1","model":"m","hotkey":"banana","toggle_enabled":false}
    """
    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(decoded.apiKey == "sk-keep")
    #expect(decoded.hotkey == .rightOption)
    #expect(decoded.toggleEnabled == false)
}

@Test func emptyAPIKeyMeansNoKey() {
    #expect(AppConfig.defaultConfig.apiKeyOrNil == nil)
    #expect(sample.apiKeyOrNil == "sk-test")
}

@Test func saveThenLoadRoundTripsAndFileIsOwnerOnly() throws {
    let url = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try AppConfig.save(sample, to: url)

    #expect(AppConfig.load(from: url) == sample)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect(attributes[.posixPermissions] as? Int == 0o600)
    let directoryAttributes = try FileManager.default.attributesOfItem(
        atPath: url.deletingLastPathComponent().path
    )
    #expect(directoryAttributes[.posixPermissions] as? Int == 0o700)
}

@Test func secondSaveOverwritesAndStaysOwnerOnly() throws {
    // 설정 창에서 저장하면 이미 있는 파일을 덮어쓴다. 기존 파일을 일부러 0644로
    // 만들어 두면, save가 실제로 0600을 다시 적용하는지 — 기존 권한을 그대로
    // 두는 게 아니라 — 확인할 수 있다.
    let url = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

    try AppConfig.save(sample, to: url)

    #expect(AppConfig.load(from: url) == sample)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect(attributes[.posixPermissions] as? Int == 0o600)
}

@Test func loadFromMissingFileIsNil() {
    #expect(AppConfig.load(from: temporaryFileURL()) == nil)
}

@Test func loadFromMalformedJSONIsNil() throws {
    let url = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data("{not json".utf8).write(to: url)

    #expect(AppConfig.load(from: url) == nil)
}

// system_prompt는 기본값과 다를 때만 저장한다. 기본값을 파일에 박아 두면 나중에 앱의
// 기본 프롬프트가 개선돼도 한 번도 손대지 않은 사용자가 옛 프롬프트에 묶인다.
@Test func defaultSystemPromptIsNotWrittenToFile() throws {
    let data = try JSONEncoder().encode(sample)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["system_prompt"] == nil)
    #expect(object["include_examples"] as? Bool == true)
}

@Test func customSystemPromptAndExampleFlagRoundTrip() throws {
    var custom = sample
    custom.systemPrompt = "받아쓰기 원문을 영어로 번역한다."
    custom.includeExamples = false

    let data = try JSONEncoder().encode(custom)

    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["system_prompt"] as? String == "받아쓰기 원문을 영어로 번역한다.")
    #expect(object["include_examples"] as? Bool == false)
    #expect(try JSONDecoder().decode(AppConfig.self, from: data) == custom)
}

@Test func fileWithoutPromptFieldsUsesDefaultPromptAndExamples() throws {
    let json = """
    {"api_key":"k","base_url":"http://127.0.0.1:8081/v1","model":"m","hotkey":"right_option","toggle_enabled":true}
    """
    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(decoded.systemPrompt == nil)
    #expect(decoded.includeExamples == true)
}

@Test func fileWithoutMaxTokensAndLogFlagUsesDefaults() throws {
    let json = """
    {"api_key":"k","base_url":"http://127.0.0.1:8081/v1","model":"m"}
    """
    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(decoded.maxTokens == 900)
    #expect(decoded.logEnabled == true)
}

@Test func maxTokensAndLogFlagRoundTrip() throws {
    var custom = sample
    custom.maxTokens = 2000
    custom.logEnabled = false

    let data = try JSONEncoder().encode(custom)

    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["max_tokens"] as? Int == 2000)
    #expect(object["log_enabled"] as? Bool == false)
    #expect(try JSONDecoder().decode(AppConfig.self, from: data) == custom)
}

@Test func fileWithoutRefineTimeoutUsesFourSeconds() throws {
    let json = """
    {"api_key":"k","base_url":"http://127.0.0.1:8081/v1","model":"m"}
    """
    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(decoded.refineTimeoutSeconds == 4)
}

@Test func refineTimeoutRoundTrips() throws {
    var custom = sample
    custom.refineTimeoutSeconds = 10
    let data = try JSONEncoder().encode(custom)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["refine_timeout_seconds"] as? Int == 10)
    #expect(try JSONDecoder().decode(AppConfig.self, from: data) == custom)
}

private let sampleWithTargetApp: AppConfig = {
    var config = sample
    config.targetAppHotkey = .rightControl
    config.targetAppBundleID = "com.apple.TextEdit"
    return config
}()

@Test func targetAppFieldsRoundTripAndUseSnakeCaseKeys() throws {
    let data = try JSONEncoder().encode(sampleWithTargetApp)
    #expect(try JSONDecoder().decode(AppConfig.self, from: data) == sampleWithTargetApp)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["target_app_hotkey"] as? String == "right_control")
    #expect(object["target_app_bundle_id"] as? String == "com.apple.TextEdit")
}

@Test func targetAppFieldsAreOmittedWhenUnset() throws {
    // 기능을 쓰지 않는 사용자의 파일에 새 키가 생기면 안 된다.
    let data = try JSONEncoder().encode(sample)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["target_app_hotkey"] == nil)
    #expect(object["target_app_bundle_id"] == nil)
}

@Test func legacyFileWithoutTargetAppFieldsReadsNil() throws {
    let json = """
    {"api_key":"sk-legacy","base_url":"http://127.0.0.1:8081/v1","model":"m","hotkey":"right_option"}
    """
    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(decoded.targetAppHotkey == nil)
    #expect(decoded.targetAppBundleID == nil)
    #expect(decoded.apiKey == "sk-legacy")
}

@Test func unknownTargetAppHotkeyReadsNilAndKeepsBundleID() throws {
    let json = """
    {"api_key":"k","base_url":"http://127.0.0.1:8081/v1","model":"m","target_app_hotkey":"banana","target_app_bundle_id":"com.apple.TextEdit"}
    """
    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(decoded.targetAppHotkey == nil)
    #expect(decoded.targetAppBundleID == "com.apple.TextEdit")
}

@Test func targetAppHotkeySameAsPrimaryReadsNil() throws {
    // 파일을 손으로 고쳐 두 단축키를 같게 만든 경우. 같은 키에 모니터 두 개가 붙으면
    // 한 번의 눌림이 두 이벤트로 들어오므로 앱으로 보내기 쪽을 꺼 버린다.
    let json = """
    {"api_key":"k","base_url":"http://127.0.0.1:8081/v1","model":"m","hotkey":"right_command","target_app_hotkey":"right_command","target_app_bundle_id":"com.apple.TextEdit"}
    """
    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(decoded.hotkey == .rightCommand)
    #expect(decoded.targetAppHotkey == nil)
    #expect(decoded.targetAppBundleID == "com.apple.TextEdit")
}

@Test func emptyTargetAppBundleIDReadsNil() throws {
    let json = """
    {"api_key":"k","base_url":"http://127.0.0.1:8081/v1","model":"m","target_app_bundle_id":""}
    """
    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(decoded.targetAppBundleID == nil)
}
