import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// config.json의 편집기. 초안을 편집하다 저장을 누르면 파일에 쓰고 Coordinator에
/// 즉시 적용한다. 필드를 바꿀 때마다 저장하지 않는다 — API 키 한 글자마다 파일을
/// 쓰거나 Picker를 바꾸는 순간 핫키 모니터가 교체되면 안 된다.
struct SettingsView: View {
    let coordinator: Coordinator

    @State private var draft: SettingsDraft
    @State private var errorMessage: String?

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        _draft = State(initialValue: SettingsDraft(config: coordinator.config, launchAtLogin: LoginItem.isEnabled))
    }

    var body: some View {
        Form {
            Section("앱 정보") {
                LabeledContent("버전", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "개발 빌드")
                LabeledContent("커밋") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "UntypedGitCommit") as? String ?? "정보 없음")
                        .monospaced()
                }
            }
            .textSelection(.enabled)
            Section("다듬기 서버") {
                TextField("서버 주소", text: $draft.baseURLText)
                TextField("모델", text: $draft.config.model)
                SecureField("API 키", text: $draft.config.apiKey)
                TextField("최대 출력 토큰", value: $draft.config.maxTokens, format: .number)
                Text("다듬은 결과가 이보다 길면 다듬지 않고 원본 전사를 넣습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("다듬기 대기 시간 (초)", value: $draft.config.refineTimeoutSeconds, format: .number)
                Text("여기에 녹음 길이의 40%가 더해집니다. 그 안에 응답이 없으면 원본 전사를 넣습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("키를 누를 때 예열", isOn: $draft.config.warmUpEnabled)
                Text("녹음을 시작하는 순간 서버에 모델이 올라와 있는지 묻고, 없으면 1토큰 요청으로 미리 올립니다. 모델이 항상 올라와 있는 서버라면 꺼서 녹음 시작과 겹치는 요청을 없앨 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("모델 유지 (Keep Alive)", isOn: $draft.config.keepAliveEnabled)
                Picker("유지 요청 간격", selection: $draft.config.keepAliveInterval) {
                    ForEach(KeepAliveInterval.allCases, id: \.self) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .disabled(!draft.config.keepAliveEnabled)
                Text("서버가 모델을 고정할 수 없을 때 켭니다. 이 간격마다 1토큰 요청을 보내 모델이 유휴 시간 초과로 내려가지 않게 합니다. 서버의 유휴 언로드 시간보다 짧게 잡으세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("다듬기 프롬프트") {
                TextEditor(text: $draft.promptText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                Toggle("기본 예시 포함", isOn: $draft.config.includeExamples)
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
                        draft.promptText = RefinementPrompt.defaultSystemPrompt
                    }
                }
            }
            Section("받아쓰기") {
                Picker("전사 방식", selection: $draft.config.transcriptionBackend) {
                    Text("2단계 — Apple 음성 인식 후 LLM이 다듬기").tag(TranscriptionBackend.apple)
                    Text("1단계 — 오디오를 LLM에 보내 한 번에 다듬기").tag(TranscriptionBackend.llmAudio)
                    Text("Apple 음성 인식만 — 다듬기 없음").tag(TranscriptionBackend.appleOnly)
                }
                Text("1단계는 위 서버의 모델이 오디오 입력을 받아야 합니다(예: gemma-4-e2b-it). 같은 프롬프트와 예시 뒤에 녹음을 붙여 한 요청으로 보냅니다. 원본 전사가 없으므로 실패하면 아무것도 넣지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Apple 음성 인식만 쓰면 서버 없이 동작하고 전사를 그대로 넣습니다. 다듬기 프롬프트와 \"원본 삽입 때도 Return 누르기\"는 영향을 주지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ShortcutPicker(
                    "기본 단축키", shortcut: Binding(get: { draft.config.hotkey }, set: { if let key = $0 { draft.config.hotkey = key } }),
                    allowsNone: false, onBeginCapture: coordinator.beginShortcutCapture, onEndCapture: coordinator.endShortcutCapture
                )
                Text("‘키 입력’을 누른 뒤 원하는 단독 수식키나 조합키를 직접 눌러 지정합니다. 다른 앱이나 시스템 단축키와 겹치지 않게 골라 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("짧게 눌렀다 떼면 토글 녹음", isOn: $draft.config.toggleEnabled)
                Text("끄면 키를 누르는 동안만 녹음합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("넣은 뒤 Return 누르기", isOn: $draft.config.pressReturn)
                Text("채팅 앱에서 바로 전송할 때 씁니다. 터미널에서는 명령이 실행됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("원본 삽입 때도 Return 누르기", isOn: $draft.config.pressReturnOnFallback)
                Text("다듬기 시간 초과·서버 오류로 원본 전사가 들어간 경우에도 Return을 누릅니다. 앱으로 보내기에도 적용됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("음성 명령") {
                Toggle("기본 단축키에서 음성 명령 구분", isOn: $draft.config.voiceCommandsEnabled)
                Text("끄면 기본 단축키와 앱으로 보내기 단축키로 말한 내용은 모두 본문으로 입력합니다. 수정 전용 단축키는 별도로 사용할 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Group {
                    Toggle("말로 수정하기", isOn: $draft.config.voiceCommandRules.editEnabled)
                    Text("수정 명령어 — 한 줄에 하나").font(.caption)
                    TextEditor(text: phraseBinding(\.editPhrases))
                        .frame(height: 56)
                        .accessibilityLabel("수정 명령어 — 한 줄에 하나")
                        .disabled(!draft.config.voiceCommandRules.editEnabled)
                    Text("예: ‘수정’, ‘고쳐’. 문장 첫머리에서 인식하고, 뒤에 말한 내용을 수정 지시로 사용합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("말로 전송하기", isOn: $draft.config.voiceCommandRules.submitEnabled)
                    Text("전송 명령어 — 한 줄에 하나").font(.caption)
                    TextEditor(text: phraseBinding(\.submitPhrases))
                        .frame(height: 56)
                        .accessibilityLabel("전송 명령어 — 한 줄에 하나")
                        .disabled(!draft.config.voiceCommandRules.submitEnabled)
                    Text("예: ‘보내’, ‘전송’. 명령어만 말했을 때 Enter를 누릅니다. 다른 말과 함께 나오면 본문으로 입력합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(!draft.config.voiceCommandsEnabled)
            }
            Section("전용 녹음 단축키") {
                ShortcutPicker("수정 전용", shortcut: $draft.config.editHotkey, onBeginCapture: coordinator.beginShortcutCapture, onEndCapture: coordinator.endShortcutCapture)
                Text("현재 입력창을 고칩니다. ‘수정’ 같은 명령어 없이 ‘내일을 오늘로 바꿔’처럼 수정 내용만 말하세요. 전송하지 않습니다. 수정에는 다듬기 서버가 필요합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                ShortcutPicker("일반 받아쓰기 전용", shortcut: $draft.config.literalHotkey, onBeginCapture: coordinator.beginShortcutCapture, onEndCapture: coordinator.endShortcutCapture)
                Text("‘수정’, ‘보내’도 본문으로 입력합니다. 선택한 전사·다듬기 방식은 유지하고, 넣은 뒤 자동 Return은 누르지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("두 전용 단축키는 현재 입력창에 적용됩니다. 누르고 말하기와 짧게 눌러 토글하기는 기본 단축키와 같습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("앱으로 보내기") {
                ShortcutPicker("단축키", shortcut: $draft.config.targetAppHotkey, onBeginCapture: coordinator.beginShortcutCapture, onEndCapture: coordinator.endShortcutCapture)
                LabeledContent("대상 앱") {
                    HStack(spacing: 8) {
                        if let bundleID = draft.config.targetAppBundleID {
                            if let icon = TargetApp.icon(bundleID: bundleID) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(TargetApp.displayName(bundleID: bundleID))
                                Text(bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("선택된 앱 없음").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("앱 선택…", action: chooseTargetApp)
                    }
                }
                Text("이 키로 받아쓰면 대상 앱으로 전환해 넣은 뒤 원래 앱으로 돌아옵니다. 대상 앱이 실행 중이 아니면 녹음을 시작하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("넣은 뒤 Return 누르기", isOn: $draft.config.targetAppPressReturn)
                Text("대상 앱이 터미널이면 명령이 실행됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("기록") {
                Toggle("받아쓰기 기록 남기기", isOn: $draft.config.logEnabled)
                Text("말한 내용과 다듬은 결과가 로그 파일에 남습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("시작") {
                Toggle("로그인할 때 자동으로 시작", isOn: $draft.launchAtLogin)
                Text("시스템 설정 › 일반 › 로그인 항목에서도 바꿀 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                // 버튼과 한 줄을 나눠 쓰면 긴 문구가 잘려 보이지 않는다. 폼 폭 520pt에서 버튼 옆에
                // 남는 폭은 약 170pt인데 가장 긴 문구는 291pt다.
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                HStack {
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
                    Button("저장") { _ = save() }
                        .disabled(coordinator.shortcutCaptureActive)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .background(SettingsWindowCloseConfirmation(
            hasUnsavedChanges: { draft.hasUnsavedChanges }, save: save
        ))
    }

    private func phraseBinding(_ keyPath: WritableKeyPath<VoiceCommandRules, [String]>) -> Binding<String> {
        Binding(get: { draft.config.voiceCommandRules[keyPath: keyPath].joined(separator: "\n") }, set: {
            draft.config.voiceCommandRules[keyPath: keyPath] = $0.components(separatedBy: .newlines)
        })
    }

    /// /Applications에서 .app을 고르게 한다. 파일에는 bundle ID만 저장하므로 여기서 읽어 둔다.
    private func chooseTargetApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
            errorMessage = "앱 정보를 읽을 수 없습니다"
            return
        }
        draft.config.targetAppBundleID = bundleID
        errorMessage = nil
    }

    private func save() -> Bool {
        let config: AppConfig
        do {
            config = try draft.validatedConfig()
        } catch {
            errorMessage = error.message
            return false
        }
        do {
            try AppConfig.save(config)
        } catch {
            // 키가 담긴 설정이므로 로그에는 error만 남긴다.
            NSLog("[SettingsView] 설정 저장 실패: %@", String(describing: error))
            errorMessage = "설정을 저장하지 못했습니다"
            return false
        }
        coordinator.apply(config)
        // 로그인 항목은 파일 저장·적용 뒤에 처리한다. 여기서 실패해도 API 키 등
        // 다른 변경은 이미 저장된 상태여야 한다.
        if draft.launchAtLogin != LoginItem.isEnabled {
            do {
                try LoginItem.setEnabled(draft.launchAtLogin)
            } catch {
                NSLog("[SettingsView] 로그인 항목 변경 실패: %@", String(describing: error))
                errorMessage = "시작 프로그램 등록에 실패했습니다"
                return false
            }
            if draft.launchAtLogin, LoginItem.requiresApproval {
                LoginItem.openSystemSettings()
                errorMessage = "시스템 설정의 로그인 항목에서 Untyped를 허용해 주세요"
                return false
            }
        }
        draft.config = config
        draft.markSaved()
        errorMessage = nil
        return true
    }
}
