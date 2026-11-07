import Foundation

/// 파일에 바로 반영하지 않는 설정 초안과 마지막으로 저장한 편집값.
/// URL·프롬프트의 파싱 전 문자열과 파일 밖의 로그인 항목도 변경 감지에 포함한다.
struct SettingsDraft {
    var config: AppConfig
    var baseURLText: String
    var promptText: String
    var launchAtLogin: Bool
    private var savedValues: Values

    init(config: AppConfig, launchAtLogin: Bool) {
        self.config = config
        baseURLText = config.baseURL.absoluteString
        promptText = config.systemPrompt ?? RefinementPrompt.defaultSystemPrompt
        self.launchAtLogin = launchAtLogin
        savedValues = Values(
            config: config, baseURLText: baseURLText,
            promptText: promptText, launchAtLogin: launchAtLogin
        )
    }

    var hasUnsavedChanges: Bool { values != savedValues }

    /// 파일 저장·적용과 로그인 항목 갱신이 모두 성공한 뒤에만 호출한다.
    mutating func markSaved() { savedValues = values }

    struct ValidationError: Error {
        let message: String
    }

    /// 검증 실패가 초안의 숨은 config 값까지 바꾸지 않도록 복사본을 정규화한다.
    func validatedConfig() throws(ValidationError) -> AppConfig {
        var config = config
        let text = baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text),
              let scheme = url.scheme, !scheme.isEmpty,
              let host = url.host(), !host.isEmpty
        else {
            throw ValidationError(message: "서버 주소가 올바르지 않습니다")
        }
        config.baseURL = url
        guard config.maxTokens >= 1 else {
            throw ValidationError(message: "최대 출력 토큰은 1 이상이어야 합니다")
        }
        guard config.refineTimeoutSeconds >= 1 else {
            throw ValidationError(message: "다듬기 대기 시간은 1초 이상이어야 합니다")
        }
        let prompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw ValidationError(message: "프롬프트가 비어 있습니다")
        }
        config.voiceCommandRules = config.voiceCommandRules.normalized
        if let validationError = config.inputValidationError {
            throw ValidationError(message: validationError)
        }
        if config.targetAppHotkey != nil, config.targetAppBundleID == nil {
            throw ValidationError(message: "대상 앱을 선택하세요")
        }
        config.systemPrompt = prompt == RefinementPrompt.defaultSystemPrompt ? nil : prompt
        return config
    }

    private var values: Values {
        Values(config: config, baseURLText: baseURLText, promptText: promptText, launchAtLogin: launchAtLogin)
    }

    private struct Values: Equatable {
        let config: AppConfig
        let baseURLText: String
        let promptText: String
        let launchAtLogin: Bool
    }
}
