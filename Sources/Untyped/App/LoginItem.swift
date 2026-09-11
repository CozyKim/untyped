import ServiceManagement

/// macOS 로그인 항목 등록. 상태의 소유자는 시스템이다 — 사용자가 시스템 설정 ›
/// 일반 › 로그인 항목에서 직접 끌 수 있으므로 config.json에 복사본을 두지 않는다.
/// 복사본이 있으면 시스템에서 껐는데 파일이 true라서 다음 실행 때 다시 등록하는
/// 식으로 사용자와 싸우게 된다.
///
/// `.app` 번들 안에서 실행될 때만 동작한다. `swift run`처럼 번들 없이 실행하면
/// 등록이 실패하고 설정 창이 오류를 표시한다.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 등록은 됐지만 사용자가 시스템 설정에서 꺼 둔 상태. 앱이 다시 켤 수 없고
    /// 사용자가 시스템 설정에서 허용해야 한다.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
