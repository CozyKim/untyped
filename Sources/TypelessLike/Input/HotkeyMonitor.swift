import AppKit

/// 오른쪽 Option 단독. 단독 수식키라 다른 앱의 단축키와 충돌하지 않고
/// flagsChanged로 눌림과 뗌을 모두 받을 수 있다.
/// Fn은 시스템이 받아쓰기와 이모지 입력에 이미 쓰고 있어 피한다.
@MainActor
final class HotkeyMonitor {
    private static let rightOptionKeyCode: UInt16 = 61
    // IOKit.framework/Headers/hidsystem/IOLLEvent.h에서 정의한 상수.
    // modifierFlags.rawValue의 낮은 16비트에 장치 고유 수식키 비트가 있다.
    private static let rightOptionMask: UInt = 0x40

    private let onEvent: @MainActor (TriggerEvent) -> Void
    private var monitor: Any?
    private var localMonitor: Any?
    private var isDown = false
    private var wantsMonitor = false
    private var launchObserver: (any NSObjectProtocol)?

    init(onEvent: @escaping @MainActor (TriggerEvent) -> Void) {
        self.onEvent = onEvent
    }

    /// 전역 모니터를 앱 런치가 끝나기 전에 설치하면 MenuBarExtra 상태 아이템이
    /// 실제 마우스 클릭을 받지 못한다. 접근성 경로로는 열리므로 앱이 정상처럼 보이지만
    /// 사용자는 아이콘을 눌러도 아무 반응을 얻지 못한다.
    ///
    /// didFinishLaunching 알림은 한 번만 온다. start()가 이미 그 알림이 지나간
    /// 뒤에 호출되면(예: MainActor로 넘긴 Task가 런치보다 늦게 실행되는 경우)
    /// 이 시점에 옵저버를 걸어도 다시는 불리지 않아 모니터가 영영 설치되지 않는다.
    /// NSRunningApplication.current.isFinishedLaunching는 그 알림과 대응하는
    /// "이미 일어났는가"라는 사실을 지금 시점에 되짚어 확인하게 해주므로,
    /// 알림을 놓쳤는지 여부와 무관하게 런치 완료 여부를 판단할 수 있다.
    func start() {
        wantsMonitor = true
        if NSRunningApplication.current.isFinishedLaunching {
            // 이미 런치가 끝난 뒤에 불렸다. 메인 큐를 한 턴 넘겨 설치한다 —
            // didFinishLaunching 옵저버도 큐에 올라간 뒤 실행되므로 같은 타이밍이고,
            // 이 시점엔 런치가 확실히 끝났으니 상태 아이템도 이미 존재한다.
            DispatchQueue.main.async { [weak self] in self?.installMonitor() }
            return
        }
        // 아직 런치가 끝나지 않았다. 완료될 때까지 기다린다.
        guard launchObserver == nil else { return }
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishLaunchObserved() }
        }
    }

    private func finishLaunchObserved() {
        if let launchObserver {
            NotificationCenter.default.removeObserver(launchObserver)
        }
        launchObserver = nil
        installMonitor()
    }

    private func installMonitor() {
        // start() 이후 stop()이 먼저 실행됐거나 이미 설치돼 있으면 설치하지 않는다.
        // 설치가 비동기로 밀리기 때문에 이 확인이 설치 직전에 있어야 한다.
        guard wantsMonitor, monitor == nil else { return }
        // 전역 모니터는 다른 앱으로 라우팅된 이벤트만 본다. 이 앱이 눌림과 뗌 사이에
        // 프론트로 올라오면(메뉴 열기 등) 뗌 이벤트는 이 앱으로 라우팅되어 전역
        // 모니터에 보이지 않고, 상태 기계가 holding에 갇혀 마이크가 계속 켜진다.
        // 로컬 모니터를 같이 달아 같은 핸들러로 흘려보낸다.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard event.keyCode == Self.rightOptionKeyCode else { return }
        // modifierFlags.contains(.option)은 왼쪽 Option이 눌려도 true가 되어,
        // 오른쪽 Option을 놓으면서 왼쪽 Option이 눌려 있으면 뗌을 감지하지 못한다.
        // 장치 고유 마스크로 오른쪽 Option만 검사한다.
        let down = event.modifierFlags.rawValue & Self.rightOptionMask != 0
        // flagsChanged는 같은 상태를 연달아 보낼 수 있다.
        guard down != isDown else { return }
        isDown = down
        onEvent(down ? .keyDown : .keyUp)
    }

    func stop() {
        wantsMonitor = false
        if let launchObserver {
            NotificationCenter.default.removeObserver(launchObserver)
        }
        launchObserver = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        isDown = false
    }
}
