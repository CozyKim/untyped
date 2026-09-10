import Foundation

/// 다듬기 백엔드(oMLX 등 OpenAI 호환 서버)에 접속하기 위한 사용자 설정.
/// ~/Library/Application Support/TypelessLike/config.json에서 읽는다.
///
/// GUI 앱은 셸 환경변수를 물려받지 않으므로 API 키 같은 값은 환경변수로 전달할
/// 수 없다. 사용자가 직접 편집할 수 있는 파일로 대신한다.
///
/// 이 타입은 baseURL/model/apiKey 세 값 — OpenAICompatibleRefiner의 생성 인자 —
/// 를 만드는 것 외에는 아무것도 모른다. 다른 애플리케이션의 설정 파일(예: oMLX
/// 자신의 ~/.omlx/settings.json)은 절대 읽지 않는다 — 다듬기는 특정 서버가 아니라
/// OpenAI 호환 API를 쓰는 어떤 서버에도 붙을 수 있어야 하기 때문이다. AppKit이나
/// SwiftUI를 몰라도 되므로 Refine/ 아래 둔다.
struct RefinerConfig: Codable {
    var baseURL: URL
    var model: String
    var apiKey: String

    private enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case model
        case apiKey = "api_key"
    }

    static let defaultConfig = RefinerConfig(
        baseURL: URL(string: "http://127.0.0.1:8081/v1")!,
        model: "gemma-4-e2b-it-8bit",
        apiKey: ""
    )

    /// 빈 문자열은 "키 없음"으로 취급한다. 키를 요구하지 않는 서버에서는
    /// Authorization 헤더를 안 보내는 것이 유효한 상태다.
    var apiKeyOrNil: String? { apiKey.isEmpty ? nil : apiKey }

    private static var configDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TypelessLike", isDirectory: true)
    }

    /// 메뉴에서 안내하거나 Finder로 열 때 쓰는 실제 파일 경로.
    static var fileURL: URL? {
        configDirectory?.appendingPathComponent("config.json", isDirectory: false)
    }

    /// 설정 파일을 읽는다. 파일이 없으면 이 기기를 위한 기본값으로 새로 만든다.
    /// 파일이 있지만 권한이 없거나 JSON이 잘못됐으면 기본값으로 대체한다 —
    /// 앱이 멈추거나 다듬기가 조용히 깨진 채로 남는 일은 없어야 한다.
    static func loadOrCreateDefault() -> RefinerConfig {
        guard let fileURL, let configDirectory else { return defaultConfig }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            writeDefaultFile(to: fileURL, in: configDirectory)
            return defaultConfig
        }

        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(RefinerConfig.self, from: data)
        else {
            return defaultConfig
        }
        return config
    }

    /// 디렉터리는 0700, 파일은 0600으로 만든다. API 키가 담기므로 소유자 외에는
    /// 읽을 수 없어야 한다.
    private static func writeDefaultFile(to fileURL: URL, in directory: URL) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(defaultConfig)
            guard FileManager.default.createFile(
                atPath: fileURL.path, contents: data, attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            // 기본 파일 생성에 실패해도 메모리 상의 기본값으로 계속 동작한다.
            // 키가 담긴 파일이므로 오류 메시지에는 error 자체만 남기고 설정값은 넣지 않는다.
            NSLog("[RefinerConfig] 기본 설정 파일 생성 실패: %@", String(describing: error))
        }
    }
}
