import SwiftUI
import AppKit

@main
struct MenuBarApp: App {
    @State private var coordinator = Coordinator(refiner: MenuBarApp.refiner)

    /// 설정 파일(~/Library/Application Support/TypelessLike/config.json)에서
    /// 주소·모델·키를 읽어 다듬기 백엔드를 하나 구성한다. Coordinator와 메뉴의
    /// 연결 상태 확인이 이 인스턴스를 함께 쓴다.
    private static let refiner: OpenAICompatibleRefiner = {
        let config = RefinerConfig.loadOrCreateDefault()
        return OpenAICompatibleRefiner(
            baseURL: config.baseURL,
            model: config.model,
            apiKey: config.apiKeyOrNil
        )
    }()

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
                Button("설정 파일 보기…") {
                    if let url = RefinerConfig.fileURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            Divider()
            Button("종료") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: iconName)
        }
        .onChange(of: coordinator.state) { _, _ in }
        .onChange(of: coordinator.refinerAvailable) { _, _ in }
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
