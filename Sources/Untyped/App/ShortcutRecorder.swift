import AppKit
import Observation

/// 설정 창 안에서만 키를 받으며, 모든 종료 경로에서 기존 단축키를 복구한다.
@MainActor
@Observable
final class ShortcutRecorder {
    private(set) var isRecording = false
    private(set) var message: String?
    @ObservationIgnored private var state = ShortcutRecordingState()
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var onEnd: (() -> Void)?
    @ObservationIgnored private var onCapture: ((KeyboardShortcut) -> Void)?

    func start(
        begin: () -> Bool, end: @escaping () -> Void,
        capture: @escaping (KeyboardShortcut) -> Void
    ) {
        guard !isRecording else { return }
        guard let recordingWindow = NSApp.keyWindow else {
            message = "설정 창을 활성화한 뒤 다시 눌러주세요."
            return
        }
        guard begin() else {
            message = "진행 중인 녹음이나 다른 단축키 입력을 먼저 끝내주세요."
            return
        }
        state = ShortcutRecordingState()
        message = nil
        isRecording = true
        onEnd = end
        onCapture = capture
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            guard NSApp.keyWindow == recordingWindow,
                  event.window == nil || event.window == recordingWindow else { self.cancel(); return event }
            self.handle(event)
            return nil
        }
        guard monitor != nil else { cancel(); message = "키 입력을 시작하지 못했습니다."; return }
        for (name, object) in [
            (NSApplication.didResignActiveNotification, nil as AnyObject?),
            (NSWindow.didResignKeyNotification, recordingWindow as AnyObject?),
        ] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            })
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.rawValue
        let input: ShortcutRecordingState.Input
        switch event.type {
        case .keyDown: input = .keyDown(event.keyCode, modifiers: flags, isRepeat: event.isARepeat)
        case .keyUp: input = .keyUp(event.keyCode, modifiers: flags)
        case .flagsChanged: input = .flagsChanged(event.keyCode, modifiers: flags)
        default: return
        }
        switch state.handle(input) {
        case .waiting: break
        case .pending(let shortcut): message = "\(shortcut.displayName) — 키를 모두 떼면 등록됩니다."
        case .invalid(let reason): message = reason
        case .cancelled: cancel()
        case .captured(let shortcut):
            let capture = onCapture
            cancel()
            capture?(shortcut)
        }
    }

    func requestCancel() {
        guard isRecording else { return }
        if state.requestCancellation() == .cancelled { cancel() }
        else { message = "키를 모두 떼면 취소됩니다." }
    }

    func cancel() {
        guard isRecording else { return }
        isRecording = false
        message = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        let end = onEnd
        onEnd = nil
        onCapture = nil
        end?()
    }
}
