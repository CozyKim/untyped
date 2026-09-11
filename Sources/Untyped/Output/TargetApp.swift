import AppKit

/// 앱으로 보내기의 대상 앱. bundle ID 하나로 실행 여부·이름·아이콘을 조회하고,
/// 텍스트를 그 앱에 넣은 뒤 원래 앱으로 돌아오는 순서를 담는다.
/// 텍스트가 어디서 왔는지(전사·다듬기)는 모른다. 붙여넣기 자체는 TextInserter에 맡긴다.
enum TargetApp {
    enum SendResult: Equatable, Sendable {
        case inserted
        /// 대상 앱이 실행 중이 아니다. 녹음을 시작한 뒤 사용자가 앱을 종료한 경우.
        case notRunning
        /// 활성화를 요청했지만 시간 안에 앞으로 오지 않았다. 이때 ⌘V를 보내면
        /// 엉뚱한 앱에 들어가므로 삽입하지 않는다.
        case notBroughtToFront
    }

    /// 활성화 요청 뒤 실제로 frontmost가 되기까지 기다리는 상한. 실측은 13~23ms지만
    /// NSRunningApplication 헤더가 활성화 시점도 활성화 자체도 보장하지 않는다고 하므로
    /// 넉넉히 둔다.
    static let activationTimeout: Duration = .seconds(1)
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
            guard await waitUntilFrontmost(target) else { return .notBroughtToFront }
        }
        await TextInserter.insert(text)
        if let origin, origin != target, !origin.isTerminated {
            try? await Task.sleep(for: returnDelay)
            // 복귀 실패는 무시한다. 텍스트는 이미 들어갔다.
            _ = origin.activate(options: [])
        }
        return .inserted
    }

    @MainActor
    private static func waitUntilFrontmost(_ app: NSRunningApplication) async -> Bool {
        let deadline = ContinuousClock.now + activationTimeout
        while ContinuousClock.now < deadline {
            // NSRunningApplication의 시간에 따라 변하는 속성은 메인 런 루프가 한 번 돌아야
            // 갱신된다. sleep이 메인 액터를 놓아주어 그 한 턴이 생긴다.
            if NSWorkspace.shared.frontmostApplication == app { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return NSWorkspace.shared.frontmostApplication == app
    }
}
