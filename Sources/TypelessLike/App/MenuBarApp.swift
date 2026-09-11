import SwiftUI
import AppKit

@main
struct MenuBarApp: App {
    @State private var coordinator = Coordinator(config: AppConfig.loadOrCreateDefault())
    /// 설정 창을 열 때마다 값을 바꿔 SettingsView에 새 identity를 준다. macOS의
    /// Settings 씬은 창을 닫아도 파괴하지 않고 숨기기만 할 수 있어, identity가
    /// 그대로면 이전 초안과 에러 메시지가 다시 열었을 때 남아 있게 된다.
    @State private var settingsGeneration = 0

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
            if !coordinator.refinerAvailable {
                Divider()
                Text("다듬기 서버에 연결할 수 없음 — 원본 받아쓰기만 삽입됩니다")
            }
            Divider()
            OpenSettingsButton { settingsGeneration += 1 }
            Button("종료") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: iconName)
        }
        .onChange(of: coordinator.state) { _, _ in }
        .onChange(of: coordinator.refinerAvailable) { _, _ in }
        .commands { }

        Settings {
            SettingsView(coordinator: coordinator)
                .id(settingsGeneration)
        }
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
        case .idle: "대기 중 — \(coordinator.config.hotkey.displayName) 키를 누르세요"
        case .holding, .toggled: "듣는 중"
        case .processing: "다듬는 중"
        }
    }

    init() {
        // 시작 시점에 손쉬운 사용 권한이 없으면 시스템 다이얼로그를 띄운다.
        // 이 권한이 없으면 전역 모니터가 눌림/뗌을 받아도 insert()가 조용히
        // 아무것도 하지 않아, 사용자가 메뉴를 열어보지 않는 한 앱이 멈춘 것처럼
        // 보인다. 반복 확인하지 않고 시작할 때 한 번만 띄운다 — 메뉴의 안내
        // 버튼이 거부했을 때의 재시도 경로로 남는다.
        if !PermissionStatus.accessibilityGranted {
            TextInserter.requestAccessibilityPermission()
        }

        let coordinator = coordinator
        Task { @MainActor in coordinator.start() }
    }
}

/// LSUIElement 앱은 활성화 없이 설정 창을 열면 다른 앱 뒤에 가려질 수 있다.
/// openSettings는 환경값이라 씬 안의 뷰에서만 읽을 수 있어 별도 뷰로 뺀다.
private struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings
    let onOpen: () -> Void

    var body: some View {
        Button("설정…") {
            onOpen()
            NSApp.activate()
            openSettings()
        }
    }
}
