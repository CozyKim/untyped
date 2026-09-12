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
        "press_return", "target_app_press_return", "press_return_on_fallback",
        "transcription_backend", "warm_up_enabled", "keep_alive_enabled", "keep_alive_interval_minutes",
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

@Test func pressReturnFieldsRoundTripAndDefaultToFalse() throws {
    var config = sample
    config.pressReturn = true
    config.targetAppPressReturn = true
    config.pressReturnOnFallback = true
    let data = try JSONEncoder().encode(config)
    #expect(try JSONDecoder().decode(AppConfig.self, from: data) == config)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["press_return"] as? Bool == true)
    #expect(object["target_app_press_return"] as? Bool == true)
    #expect(object["press_return_on_fallback"] as? Bool == true)

    // 필드가 없는 기존 파일은 셋 다 꺼진 것으로 읽는다.
    let legacy = """
    {"api_key":"k","base_url":"http://127.0.0.1:8081/v1","model":"m"}
    """
    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(legacy.utf8))
    #expect(decoded.pressReturn == false)
    #expect(decoded.targetAppPressReturn == false)
    #expect(decoded.pressReturnOnFallback == false)
}

@Test func pressesReturnOnlyWhenPathToggleIsOn() {
    var config = sample
    let refined = RefineOutcome.refined("x")
    #expect(config.pressesReturn(for: .frontmost, outcome: refined) == false)
    #expect(config.pressesReturn(for: .targetApp, outcome: refined) == false)

    config.pressReturn = true
    #expect(config.pressesReturn(for: .frontmost, outcome: refined) == true)
    // 경로별 토글은 서로 독립이다.
    #expect(config.pressesReturn(for: .targetApp, outcome: refined) == false)

    config.pressReturn = false
    config.targetAppPressReturn = true
    #expect(config.pressesReturn(for: .frontmost, outcome: refined) == false)
    #expect(config.pressesReturn(for: .targetApp, outcome: refined) == true)
}

@Test func fallbackPressesReturnOnlyWithFallbackToggle() {
    var config = sample
    config.pressReturn = true
    config.targetAppPressReturn = true
    let fallback = RefineOutcome.fallback("x", .timeout)
    // 원본 전사에는 군말·정정이 남아 있을 수 있어 기본으로는 보내지 않는다.
    #expect(config.pressesReturn(for: .frontmost, outcome: fallback) == false)
    #expect(config.pressesReturn(for: .targetApp, outcome: fallback) == false)

    config.pressReturnOnFallback = true
    #expect(config.pressesReturn(for: .frontmost, outcome: fallback) == true)
    #expect(config.pressesReturn(for: .targetApp, outcome: fallback) == true)

    // 원본-삽입 토글만으로는 Return을 누르지 않는다. 경로별 토글이 먼저다.
    config.pressReturn = false
    config.targetAppPressReturn = false
    #expect(config.pressesReturn(for: .frontmost, outcome: fallback) == false)
    #expect(config.pressesReturn(for: .targetApp, outcome: fallback) == false)
}

@Test func transcriptionBackendDefaultsToAppleAndRoundTrips() throws {
    // 기본은 Apple — 기존 사용자의 동작이 바뀌면 안 된다.
    #expect(AppConfig.defaultConfig.transcriptionBackend == .apple)
    let data = try JSONEncoder().encode(sample)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["transcription_backend"] as? String == "apple")

    var custom = sample
    custom.transcriptionBackend = .llmAudio
    let customData = try JSONEncoder().encode(custom)
    let customObject = try #require(JSONSerialization.jsonObject(with: customData) as? [String: Any])
    #expect(customObject["transcription_backend"] as? String == "llm_audio")
    #expect(try JSONDecoder().decode(AppConfig.self, from: customData) == custom)
}

@Test func legacyFileWithoutTranscriptionBackendReadsApple() throws {
    let json = """
    {"api_key":"sk-legacy","base_url":"http://127.0.0.1:8081/v1","model":"m"}
    """
    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(decoded.transcriptionBackend == .apple)
    #expect(decoded.apiKey == "sk-legacy")
}

@Test func unknownTranscriptionBackendFallsBackToAppleAndKeepsOtherFields() throws {
    // hotkey와 같은 규칙 — 이 필드 하나 때문에 파일 전체가 거부되면 안 된다.
    let json = """
    {"api_key":"sk-keep","base_url":"http://127.0.0.1:8081/v1","model":"m","transcription_backend":"whisper","toggle_enabled":false}
    """
    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(decoded.transcriptionBackend == .apple)
    #expect(decoded.apiKey == "sk-keep")
    #expect(decoded.toggleEnabled == false)
}

// MARK: - Keep Alive

@Test func keepAliveDefaultsToOffAndFiveMinutes() throws {
    // 기본은 꺼짐 — 기존 사용자의 서버에 갑자기 주기적인 요청이 가면 안 된다.
    #expect(AppConfig.defaultConfig.keepAliveEnabled == false)
    #expect(AppConfig.defaultConfig.keepAliveInterval == .fiveMinutes)
    let data = try JSONEncoder().encode(sample)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["keep_alive_enabled"] as? Bool == false)
    #expect(object["keep_alive_interval_minutes"] as? Int == 5)
}

@Test func keepAliveFieldsRoundTrip() throws {
    var custom = sample
    custom.keepAliveEnabled = true
    custom.keepAliveInterval = .twoMinutes
    let data = try JSONEncoder().encode(custom)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["keep_alive_enabled"] as? Bool == true)
    #expect(object["keep_alive_interval_minutes"] as? Int == 2)
    #expect(try JSONDecoder().decode(AppConfig.self, from: data) == custom)
}

@Test func legacyFileWithoutKeepAliveFieldsReadsOffAndFiveMinutes() throws {
    let json = """
    {"api_key":"sk-legacy","base_url":"http://127.0.0.1:8081/v1","model":"m"}
    """
    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(decoded.keepAliveEnabled == false)
    #expect(decoded.keepAliveInterval == .fiveMinutes)
    #expect(decoded.apiKey == "sk-legacy")
}

@Test func unknownKeepAliveIntervalFallsBackToFiveMinutesAndKeepsOtherFields() throws {
    // 선택지에 없는 분 값(손으로 고친 파일)은 기본값으로 읽는다 — hotkey와 같은 규칙. 켜짐 상태는 유지한다.
    let json = """
    {"api_key":"sk-keep","base_url":"http://127.0.0.1:8081/v1","model":"m","keep_alive_enabled":true,"keep_alive_interval_minutes":7}
    """
    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(decoded.keepAliveEnabled == true)
    #expect(decoded.keepAliveInterval == .fiveMinutes)
    #expect(decoded.apiKey == "sk-keep")
}

@Test func keepAlivePeriodIsNilWhenOffAndTheIntervalWhenOn() {
    // Coordinator는 이 값 하나만 본다 — nil이면 루프를 돌리지 않는다.
    var config = sample
    #expect(config.keepAlivePeriod == nil)
    config.keepAliveEnabled = true
    #expect(config.keepAlivePeriod == .seconds(300))
    config.keepAliveInterval = .oneMinute
    #expect(config.keepAlivePeriod == .seconds(60))
}

// MARK: - 예열

@Test func warmUpDefaultsToOnAndRoundTrips() throws {
    // 기본은 켜짐 — 설정이 생기기 전과 같은 동작이어야 한다.
    #expect(AppConfig.defaultConfig.warmUpEnabled == true)
    var custom = sample
    custom.warmUpEnabled = false
    let data = try JSONEncoder().encode(custom)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["warm_up_enabled"] as? Bool == false)
    #expect(try JSONDecoder().decode(AppConfig.self, from: data) == custom)
}

@Test func legacyFileWithoutWarmUpFieldReadsOn() throws {
    let json = """
    {"api_key":"sk-legacy","base_url":"http://127.0.0.1:8081/v1","model":"m"}
    """
    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(decoded.warmUpEnabled == true)
    #expect(decoded.apiKey == "sk-legacy")
}
