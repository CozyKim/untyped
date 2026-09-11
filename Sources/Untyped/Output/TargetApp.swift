import AppKit
import ApplicationServices

/// 앱으로 보내기의 대상 앱. bundle ID 하나로 실행 여부·이름·아이콘을 조회하고,
/// 텍스트를 그 앱에 넣은 뒤 원래 앱으로 돌아오는 순서를 담는다.
/// 텍스트가 어디서 왔는지(전사·다듬기)는 모른다. 붙여넣기 자체는 TextInserter에 맡긴다.
enum TargetApp {
    enum SendResult: Equatable, Sendable {
        case inserted
        /// 대상 앱이 실행 중이 아니다. 녹음을 시작한 뒤 사용자가 앱을 종료한 경우.
        case notRunning
        /// 활성화를 요청했지만 시간 안에 키보드 포커스가 넘어오지 않았다. 이때 ⌘V를 보내면
        /// 원래 앱에 들어가므로 삽입하지 않는다.
        case notBroughtToFront
    }

    /// 활성화 요청 뒤 대상 앱이 실제로 키 입력을 받기까지 기다리는 상한. frontmost 표시는
    /// 0.2초 안에 바뀌지만 키보드 포커스는 0.2~0.8초 뒤에 넘어오는 것을 실측했다. 시스템이
    /// 바쁠 때를 위해 여유를 둔다.
    static let activationTimeout: Duration = .seconds(2)
    /// 붙여넣기 이벤트를 보낸 뒤 원래 앱으로 돌아가기 전 여유. 이벤트는 보낸 순간 앞에
    /// 있는 앱의 큐에 들어가지만, 대상 앱이 그것을 처리하기 전에 포커스를 빼앗지 않도록
    /// 잠깐 기다린다.
    static let returnDelay: Duration = .milliseconds(200)

    static func runningApplication(bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// 알림과 설정 창에 보여줄 이름. 실행 중이면 그 이름, 아니면 디스크의 앱 번들 이름,
    /// 앱이 삭제됐으면 bundle ID 그대로.
    static func displayName(bundleID: String) -> String {
        if let name = runningApplication(bundleID: bundleID)?.localizedName { return name }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    static func icon(bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// 대상 앱을 앞으로 가져와 텍스트를 붙여넣고 원래 앱으로 돌아온다.
    @MainActor
    static func send(_ text: String, toAppWithBundleID bundleID: String) async -> SendResult {
        guard let target = runningApplication(bundleID: bundleID) else { return .notRunning }
        // 돌아갈 앱은 녹음 시작 시점이 아니라 지금 읽는다. 토글 녹음 중에 사용자가 다른
        // 앱으로 옮겨갔을 수 있고, 지금 있는 곳이 돌아갈 곳이다.
        let origin = NSWorkspace.shared.frontmostApplication
        if origin != target {
            _ = target.activate(options: [])
            guard await waitUntilKeyboardFocus(target) else { return .notBroughtToFront }
        }
        await TextInserter.insert(text)
        if let origin, origin != target, !origin.isTerminated {
            try? await Task.sleep(for: returnDelay)
            // 복귀 실패는 무시한다. 텍스트는 이미 들어갔다.
            _ = origin.activate(options: [])
        }
        return .inserted
    }

    /// `NSWorkspace.frontmostApplication`은 LaunchServices가 앞 프로세스로 표시하는 순간 바뀌지만,
    /// 그 앱이 실제로 키 입력을 받기까지는 수백 ms가 더 걸린다 — 창이 키 윈도우가 되는 데
    /// 시간이 걸리는 Electron·터미널 앱에서 특히 그렇다. 그 사이에 ⌘V를 보내면 원래 앱에
    /// 들어간다. 접근성 시스템이 보고하는 "키보드 포커스를 가진 앱"은 실제 포커스가 넘어간
    /// 뒤에 바뀌므로, frontmost와 이 값이 모두 대상 앱일 때까지 기다린다.
    @MainActor
    private static func waitUntilKeyboardFocus(_ app: NSRunningApplication) async -> Bool {
        let deadline = ContinuousClock.now + activationTimeout
        while ContinuousClock.now < deadline {
            // NSRunningApplication의 시간에 따라 변하는 속성은 메인 런 루프가 한 번 돌아야
            // 갱신된다. sleep이 메인 액터를 놓아주어 그 한 턴이 생긴다.
            if hasKeyboardFocus(app) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return hasKeyboardFocus(app)
    }

    private static func hasKeyboardFocus(_ app: NSRunningApplication) -> Bool {
        guard NSWorkspace.shared.frontmostApplication == app else { return false }
        return focusedApplicationPID() == app.processIdentifier
    }

    /// 접근성 시스템이 보고하는, 지금 키보드 포커스를 가진 앱의 pid. 손쉬운 사용 권한이 없거나
    /// 포커스를 가진 앱이 없으면 nil — 권한이 없으면 ⌘V도 보낼 수 없으므로 여기서 막히는 것이 맞다.
    private static func focusedApplicationPID() -> pid_t? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &value
        )
        guard result == .success, let value else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(value as! AXUIElement, &pid) == .success else { return nil }
        return pid
    }
}
