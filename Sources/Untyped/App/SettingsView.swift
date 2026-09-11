import AppKit
import SwiftUI

/// config.json의 편집기. 초안을 편집하다 저장을 누르면 파일에 쓰고 Coordinator에
/// 즉시 적용한다. 필드를 바꿀 때마다 저장하지 않는다 — API 키 한 글자마다 파일을
/// 쓰거나 Picker를 바꾸는 순간 핫키 모니터가 교체되면 안 된다.
struct SettingsView: View {
    let coordinator: Coordinator

    @State private var draft: AppConfig
    /// baseURL은 URL 타입이라 편집 중에는 문자열로 들고 저장 시점에 파싱한다.
    @State private var baseURLText: String
    /// systemPrompt는 nil이 "기본값"이라 편집 중에는 실제 텍스트로 들고 저장 시점에
    /// 기본값과 비교한다.
    @State private var promptText: String
    @State private var errorMessage: String?

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        _draft = State(initialValue: coordinator.config)
        _baseURLText = State(initialValue: coordinator.config.baseURL.absoluteString)
        _promptText = State(
            initialValue: coordinator.config.systemPrompt ?? RefinementPrompt.defaultSystemPrompt
        )
    }

    var body: some View {
        Form {
            Section("다듬기 서버") {
                TextField("서버 주소", text: $baseURLText)
                TextField("모델", text: $draft.model)
                SecureField("API 키", text: $draft.apiKey)
                TextField("최대 출력 토큰", value: $draft.maxTokens, format: .number)
                Text("다듬은 결과가 이보다 길면 다듬지 않고 원본 전사를 넣습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("다듬기 대기 시간 (초)", value: $draft.refineTimeoutSeconds, format: .number)
                Text("여기에 녹음 길이의 40%가 더해집니다. 그 안에 응답이 없으면 원본 전사를 넣습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("다듬기 프롬프트") {
                TextEditor(text: $promptText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                Toggle("기본 예시 포함", isOn: $draft.includeExamples)
                Text("예시는 기본 규칙(정정 삭제, 군말 제거, 용어 복원)을 보여줍니다. 번역처럼 성격이 다른 지시를 쓸 때는 끄세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DisclosureGroup("기본 예시 보기") {
                    ForEach(Array(RefinementPrompt.examples.enumerated()), id: \.offset) { index, example in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(index + 1). \(example.input)")
                            Text("→ \(example.output)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .textSelection(.enabled)
                        .padding(.vertical, 2)
                    }
                }
                HStack {
                    Spacer()
                    Button("기본값으로 되돌리기") {
                        promptText = RefinementPrompt.defaultSystemPrompt
                    }
                }
            }
            Section("받아쓰기") {
                Picker("단축키", selection: $draft.hotkey) {
                    ForEach(HotkeyKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                Text("다른 앱의 단축키에 자주 쓰이는 키(왼쪽 ⌘ 등)를 고르면 그 조합키를 누를 때마다 녹음이 시작됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("짧게 눌렀다 떼면 토글 녹음", isOn: $draft.toggleEnabled)
                Text("끄면 키를 누르는 동안만 녹음합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("기록") {
                Toggle("받아쓰기 기록 남기기", isOn: $draft.logEnabled)
                Text("말한 내용과 다듬은 결과가 로그 파일에 남습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                    Spacer()
                    Button("로그 파일 보기…") {
                        if let url = DictationLog.fileURL,
                           FileManager.default.fileExists(atPath: url.path) {
                            NSWorkspace.shared.open(url)
                        } else {
                            errorMessage = "아직 기록이 없습니다"
                        }
                    }
                    Button("설정 파일 보기…") {
                        if let url = AppConfig.fileURL {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    Button("저장", action: save)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
    }

    private func save() {
        let text = baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text),
              let scheme = url.scheme, !scheme.isEmpty,
              let host = url.host(), !host.isEmpty
        else {
            errorMessage = "서버 주소가 올바르지 않습니다"
            return
        }
        draft.baseURL = url
        guard draft.maxTokens >= 1 else {
            errorMessage = "최대 출력 토큰은 1 이상이어야 합니다"
            return
        }
        guard draft.refineTimeoutSeconds >= 1 else {
            errorMessage = "다듬기 대기 시간은 1초 이상이어야 합니다"
            return
        }
        let prompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            errorMessage = "프롬프트가 비어 있습니다"
            return
        }
        draft.systemPrompt = prompt == RefinementPrompt.defaultSystemPrompt ? nil : prompt
        do {
            try AppConfig.save(draft)
        } catch {
            // 키가 담긴 설정이므로 로그에는 error만 남긴다.
            NSLog("[SettingsView] 설정 저장 실패: %@", String(describing: error))
            errorMessage = "설정을 저장하지 못했습니다"
            return
        }
        coordinator.apply(draft)
        errorMessage = nil
    }
}
