import Testing
import Foundation
@testable import TypelessLike

private let sample = AppConfig(
    baseURL: URL(string: "http://localhost:11434/v1")!,
    model: "qwen3:8b",
    apiKey: "sk-test",
    hotkey: .rightCommand,
    toggleEnabled: false
)

private func temporaryFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("TypelessLikeTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("config.json", isDirectory: false)
}

@Test func encodeDecodeRoundTrip() throws {
    let data = try JSONEncoder().encode(sample)
    #expect(try JSONDecoder().decode(AppConfig.self, from: data) == sample)
}

@Test func encodedKeysAreSnakeCase() throws {
    let data = try JSONEncoder().encode(sample)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == ["base_url", "model", "api_key", "hotkey", "toggle_enabled"])
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
    // 설정 창에서 저장하면 이미 있는 파일을 덮어쓴다. 그때도 0600이어야 한다.
    let url = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try AppConfig.save(AppConfig.defaultConfig, to: url)

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
