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
    @State private var errorMessage: String?

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        _draft = State(initialValue: coordinator.config)
        _baseURLText = State(initialValue: coordinator.config.baseURL.absoluteString)
    }

    var body: some View {
        Form {
            Section("다듬기 서버") {
                TextField("서버 주소", text: $baseURLText)
                TextField("모델", text: $draft.model)
                SecureField("API 키", text: $draft.apiKey)
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
            Section {
                HStack {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                    Spacer()
                    Button("설정 파일 보기…") {
                        if let url = AppConfig.fileURL {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    Button("저장", action: save)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
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
