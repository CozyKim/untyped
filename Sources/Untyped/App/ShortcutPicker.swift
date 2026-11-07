import SwiftUI

/// 누른 키를 등록한다. 완료 전에는 기존 binding이나 저장 파일을 바꾸지 않는다.
@MainActor
struct ShortcutPicker: View {
    let title: String
    @Binding var shortcut: KeyboardShortcut?
    let allowsNone: Bool
    let onBeginCapture: () -> Bool
    let onEndCapture: () -> Void
    @State private var recorder = ShortcutRecorder()

    init(
        _ title: String, shortcut: Binding<KeyboardShortcut?>, allowsNone: Bool = true,
        onBeginCapture: @escaping () -> Bool, onEndCapture: @escaping () -> Void
    ) {
        self.title = title
        _shortcut = shortcut
        self.allowsNone = allowsNone
        self.onBeginCapture = onBeginCapture
        self.onEndCapture = onEndCapture
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            HStack {
                Text(recorder.isRecording ? "원하는 키를 누르세요…" : (shortcut?.displayName ?? "미지정"))
                    .foregroundStyle(recorder.isRecording ? .secondary : .primary)
                    .accessibilityLabel("\(title): \(shortcut?.displayName ?? "미지정")")
                Spacer()
                if recorder.isRecording {
                    Button("취소") { recorder.requestCancel() }
                } else {
                    Button("키 입력") {
                        let binding = $shortcut
                        recorder.start(begin: onBeginCapture, end: onEndCapture) { binding.wrappedValue = $0 }
                    }
                    .accessibilityLabel("\(title) 키 입력")
                    if allowsNone, shortcut != nil {
                        Button("지우기") { shortcut = nil }
                            .accessibilityLabel("\(title) 지우기")
                    }
                }
            }
            if let message = recorder.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            } else if recorder.isRecording {
                Text("조합키를 누르거나 수식키 하나를 눌렀다 떼세요. Esc로 취소합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { recorder.cancel() }
    }
}
