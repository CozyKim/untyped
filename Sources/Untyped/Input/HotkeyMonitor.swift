import AppKit

/// Bare modifiers retain local/global flagsChanged monitoring. Chords use an
/// active event tap so their key events never reach the focused text field.
@MainActor
final class HotkeyMonitor {
    private let key: KeyboardShortcut
    private let onEvent: @MainActor (TriggerEvent) -> Void
    private let onFailure: @MainActor (String) -> Void
    private var monitor: Any?
    private var localMonitor: Any?
    private var isDown = false
    private var wantsMonitor = false
    private var launchObserver: (any NSObjectProtocol)?
    private var activationObserver: (any NSObjectProtocol)?
    private var chordTap: ChordTapRegistration?
    private var chordTracker: ShortcutChordTracker?
    private var deliveryGeneration = UUID()

    var isInstalled: Bool {
        switch key {
        case .modifier, .modifierChord: monitor != nil && localMonitor != nil
        case .chord: chordTap != nil
        }
    }

    init(
        key: KeyboardShortcut,
        onFailure: @escaping @MainActor (String) -> Void = { _ in },
        onEvent: @escaping @MainActor (TriggerEvent) -> Void
    ) {
        self.key = key
        self.onFailure = onFailure
        self.onEvent = onEvent
        if case .chord(let chord) = key { chordTracker = ShortcutChordTracker(chord: chord) }
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
        let generation = deliveryGeneration
        // Returning from System Settings after granting Accessibility should
        // recover a failed tap without restarting the app or changing a key.
        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.deliveryGeneration == generation else { return }
                    self.installMonitor()
                }
            }
        }
        if NSRunningApplication.current.isFinishedLaunching {
            // 이미 런치가 끝난 뒤에 불렸다. 메인 큐를 한 턴 넘겨 설치한다 —
            // didFinishLaunching 옵저버도 큐에 올라간 뒤 실행되므로 같은 타이밍이고,
            // 이 시점엔 런치가 확실히 끝났으니 상태 아이템도 이미 존재한다.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.deliveryGeneration == generation else { return }
                self.installMonitor()
            }
            return
        }
        // 아직 런치가 끝나지 않았다. 완료될 때까지 기다린다.
        guard launchObserver == nil else { return }
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.deliveryGeneration == generation else { return }
                self.finishLaunchObserved()
            }
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
        guard wantsMonitor, NSRunningApplication.current.isFinishedLaunching,
              !isInstalled, key.isValid else { return }
        if case .chord = key {
            chordTap = ChordTapRegistration(owner: self)
            if chordTap == nil {
                onFailure("단축키를 등록하지 못했습니다. 접근성 권한을 허용한 뒤 설정을 다시 저장하세요.")
            }
            return
        }
        // 전역 모니터는 다른 앱으로 라우팅된 이벤트만 본다. 이 앱이 눌림과 뗌 사이에
        // 프론트로 올라오면(메뉴 열기 등) 뗌 이벤트는 이 앱으로 라우팅되어 전역
        // 모니터에 보이지 않고, 상태 기계가 holding에 갇혀 마이크가 계속 켜진다.
        // 로컬 모니터를 같이 달아 같은 핸들러로 흘려보낸다.
        if monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event)
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event)
                return event
            }
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let down: Bool
        switch key {
        case .modifier(let key):
            guard let value = key.transition(keyCode: event.keyCode, modifierFlags: event.modifierFlags.rawValue) else { return }
            down = value
        case .modifierChord(let chord): down = chord.isHeld(modifierFlags: event.modifierFlags.rawValue)
        case .chord: return
        }
        // flagsChanged는 같은 상태를 연달아 보낼 수 있다.
        guard down != isDown else { return }
        isDown = down
        onEvent(down ? .keyDown : .keyUp)
    }

    fileprivate func handleTap(type: CGEventType, event: CGEvent) -> Bool {
        let input: ShortcutChordTracker.Input
        let modifiers: ShortcutModifiers
        let isOwnEvent: Bool
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = chordTap?.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            guard case .chord(let chord) = key else { return false }
            // A release can occur during the disabled interval. Reconcile with
            // physical state so a missed event cannot leave the microphone on.
            input = .tapResumed(keyIsDown: CGEventSource.keyState(.hidSystemState, key: chord.key.keyCode))
            modifiers = ShortcutModifiers(rawValue: UInt(CGEventSource.flagsState(.hidSystemState).rawValue))
            isOwnEvent = false
        } else {
            let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            switch type {
            case .keyDown:
                input = .keyDown(code, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
            case .keyUp: input = .keyUp(code)
            case .flagsChanged: input = .modifiersChanged
            default: return false
            }
            modifiers = ShortcutModifiers(rawValue: UInt(event.flags.rawValue))
            isOwnEvent = event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(ProcessInfo.processInfo.processIdentifier)
        }
        guard let result = chordTracker?.handle(
            input, modifiers: modifiers, isOwnEvent: isOwnEvent
        ) else { return false }
        switch result.transition {
        case .pressed: enqueueChordEvent(.keyDown)
        case .released: enqueueChordEvent(.keyUp)
        case nil: break
        }
        return result.consume
    }

    private func enqueueChordEvent(_ event: TriggerEvent) {
        // AX reads in the recording callback can exceed the event-tap timeout.
        // Return the consumption decision immediately and deliver transitions in
        // FIFO order, dropping callbacks from a stopped/restarted monitor.
        let generation = deliveryGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wantsMonitor, self.deliveryGeneration == generation else { return }
            self.onEvent(event)
        }
    }

    func stop() {
        wantsMonitor = false
        deliveryGeneration = UUID()
        if let launchObserver {
            NotificationCenter.default.removeObserver(launchObserver)
        }
        launchObserver = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        chordTap = nil
        if case .chord(let chord) = key { chordTracker = ShortcutChordTracker(chord: chord) }
        isDown = false
    }
}

/// The callback context is kept alive exactly as long as its port. Its weak
/// owner avoids a tap/monitor cycle; invalidation precedes context destruction.
private final class ChordTapContext {
    weak var owner: HotkeyMonitor?
    init(owner: HotkeyMonitor) { self.owner = owner }
}

private final class ChordTapRegistration {
    let tap: CFMachPort
    private let source: CFRunLoopSource
    private let context: ChordTapContext

    @MainActor
    init?(owner: HotkeyMonitor) {
        let context = ChordTapContext(owner: owner)
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                // This port is attached exclusively to CFRunLoopGetMain().
                let consume = MainActor.assumeIsolated {
                    Unmanaged<ChordTapContext>.fromOpaque(userInfo).takeUnretainedValue()
                        .owner?.handleTap(type: type, event: event) ?? false
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(context).toOpaque()
        ) else { return nil }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return nil
        }
        self.tap = tap
        self.source = source
        self.context = context
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    deinit {
        CFMachPortInvalidate(tap)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }
}
