import SwiftUI
import AppKit

@main
struct MenuBarApp: App {
    @State private var coordinator = Coordinator(
        refiner: OpenAICompatibleRefiner(
            baseURL: URL(string: "http://127.0.0.1:8081/v1")!,
            model: "gemma-4-e2b-it-8bit",
            apiKey: ProcessInfo.processInfo.environment["TYPELESS_API_KEY"]
        )
    )

    var body: some Scene {
        MenuBarExtra {
            if !PermissionStatus.microphoneGranted {
                Button("마이크 권한 허용하기…") {
                    Task {
                        await PermissionStatus.requestMicrophone()
                        if !PermissionStatus.microphoneGranted {
                            PermissionStatus.openMicrophoneSettings()
                        }
                    }
                }
            }
            if !PermissionStatus.accessibilityGranted {
                Button("손쉬운 사용 권한 허용하기…") {
                    TextInserter.requestAccessibilityPermission()
                    PermissionStatus.openAccessibilitySettings()
                }
            }
            if !PermissionStatus.microphoneGranted || !PermissionStatus.accessibilityGranted {
                Divider()
            }
            Text(statusLabel)
            Divider()
            Button("종료") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: iconName)
        }
        .onChange(of: coordinator.state) { _, _ in }
        .commands { }
    }

    private var iconName: String {
        switch coordinator.state {
        case .idle: "mic"
        case .holding, .toggled: "mic.fill"
        case .processing: "waveform"
        }
    }

    private var statusLabel: String {
        switch coordinator.state {
        case .idle: "대기 중 — 오른쪽 Option을 누르세요"
        case .holding, .toggled: "녹음 중"
        case .processing: "다듬는 중"
        }
    }

    init() {
        let coordinator = coordinator
        Task { @MainActor in coordinator.start() }
    }
}
