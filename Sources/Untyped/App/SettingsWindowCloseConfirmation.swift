import AppKit
import SwiftUI

enum SettingsCloseChoice {
    case save, discard, cancel

    func allowsClosing(save: () -> Bool) -> Bool {
        switch self {
        case .save: save()
        case .discard: true
        case .cancel: false
        }
    }
}

/// 저장 실패 시에도 닫히는 dismissalConfirmationDialog 대신 저장 성공 여부를 확인한다.
/// 직접 처리하지 않는 이벤트는 SwiftUI의 기존 창 delegate에 전달한다.
struct SettingsWindowCloseConfirmation: NSViewRepresentable {
    let hasUnsavedChanges: () -> Bool
    let save: () -> Bool

    func makeNSView(context: Context) -> WindowView { WindowView() }

    func updateNSView(_ nsView: WindowView, context: Context) {
        nsView.hasUnsavedChanges = hasUnsavedChanges
        nsView.save = save
    }

    static func dismantleNSView(_ nsView: WindowView, coordinator: ()) { nsView.detach() }

    final class WindowView: NSView {
        var hasUnsavedChanges: () -> Bool = { false }
        var save: () -> Bool = { false }
        private weak var attachedWindow: NSWindow?
        private var closeDelegate: CloseDelegate?
        private var attachmentGeneration = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let window else { return }
            let generation = attachmentGeneration
            // SwiftUI의 창 초기화가 끝난 뒤 기존 delegate를 감싼다.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window,
                      self.attachmentGeneration == generation else { return }
                let delegate = CloseDelegate(
                    original: window.delegate,
                    hasUnsavedChanges: { [weak self] in self?.hasUnsavedChanges() ?? false },
                    save: { [weak self] in self?.save() ?? false }
                )
                self.attachedWindow = window
                self.closeDelegate = delegate
                window.delegate = delegate
            }
        }

        func detach() {
            attachmentGeneration += 1
            if let attachedWindow, let closeDelegate, attachedWindow.delegate === closeDelegate {
                attachedWindow.delegate = closeDelegate.original
            }
            attachedWindow = nil
            closeDelegate = nil
        }
    }

    @MainActor
    final class CloseDelegate: NSObject, NSWindowDelegate {
        // 불변 참조이며, 비격리 Objective-C selector 조회·전달에도 사용한다.
        nonisolated(unsafe) let original: (any NSWindowDelegate)?
        let hasUnsavedChanges: () -> Bool
        let save: () -> Bool
        private var presentingConfirmation = false

        init(original: (any NSWindowDelegate)?, hasUnsavedChanges: @escaping () -> Bool, save: @escaping () -> Bool) {
            self.original = original
            self.hasUnsavedChanges = hasUnsavedChanges
            self.save = save
        }

        nonisolated override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }

        nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
            if original?.responds(to: selector) == true { return original }
            return super.forwardingTarget(for: selector)
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard !presentingConfirmation else { return false }
            guard hasUnsavedChanges() else { return original?.windowShouldClose?(sender) ?? true }
            presentingConfirmation = true
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "설정 변경 사항을 저장하시겠습니까?"
            alert.informativeText = "저장하지 않고 닫으면 변경한 내용이 사라집니다."
            alert.addButton(withTitle: "저장")
            alert.addButton(withTitle: "취소").keyEquivalent = "\u{1b}"
            let discard = alert.addButton(withTitle: "저장하지 않음")
            discard.keyEquivalent = "d"
            discard.keyEquivalentModifierMask = .command
            alert.beginSheetModal(for: sender) { [weak self, weak sender] response in
                guard let self else { return }
                self.presentingConfirmation = false
                guard let sender, sender.delegate === self else { return }
                let choice: SettingsCloseChoice = switch response {
                case .alertFirstButtonReturn: .save
                case .alertThirdButtonReturn: .discard
                default: .cancel
                }
                guard choice.allowsClosing(save: self.save),
                      self.original?.windowShouldClose?(sender) ?? true else { return }
                // performClose()로 재진입하면 확인 창이 반복된다. 기존 delegate의 동의 후 직접 닫는다.
                sender.close()
            }
            return false
        }
    }
}
