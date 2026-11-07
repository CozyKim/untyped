import AppKit
import Testing
@testable import Untyped

struct SettingsDraftTests {
    @Test func openingAndRestoringSettingsDoesNotLeaveUnsavedChanges() {
        var draft = SettingsDraft(config: .defaultConfig, launchAtLogin: false)
        #expect(!draft.hasUnsavedChanges)
        draft.config.model = "another-model"
        #expect(draft.hasUnsavedChanges)
        draft.config.model = AppConfig.defaultConfig.model
        #expect(!draft.hasUnsavedChanges)
    }

    @Test func rawInvalidURLAndPromptEditsAreNotLostOnClose() {
        var draft = SettingsDraft(config: .defaultConfig, launchAtLogin: false)
        let originalURL = draft.baseURLText
        draft.baseURLText = "not a URL"
        #expect(draft.hasUnsavedChanges)
        draft.baseURLText = originalURL
        #expect(!draft.hasUnsavedChanges)
        draft.promptText = ""
        #expect(draft.hasUnsavedChanges)
        draft.promptText = RefinementPrompt.defaultSystemPrompt
        #expect(!draft.hasUnsavedChanges)
    }

    @Test func loginItemChangesAreTrackedOutsideTheConfigFile() {
        var draft = SettingsDraft(config: .defaultConfig, launchAtLogin: false)
        draft.launchAtLogin = true
        #expect(draft.hasUnsavedChanges)
        draft.launchAtLogin = false
        #expect(!draft.hasUnsavedChanges)
    }

    @Test func savingMovesTheBaselineToTheLastSavedValues() {
        var draft = SettingsDraft(config: .defaultConfig, launchAtLogin: false)
        draft.config.model = "saved-model"
        draft.baseURLText = "https://example.com/v1"
        draft.promptText = "A new prompt"
        draft.launchAtLogin = true
        draft.markSaved()
        #expect(!draft.hasUnsavedChanges)
        draft.config.model = AppConfig.defaultConfig.model
        #expect(draft.hasUnsavedChanges)
        draft.config.model = "saved-model"
        #expect(!draft.hasUnsavedChanges)
    }

    @Test func cancelAndDiscardNeverSave() {
        #expect(!SettingsCloseChoice.cancel.allowsClosing {
            Issue.record("취소하면 저장하면 안 된다")
            return true
        })
        #expect(SettingsCloseChoice.discard.allowsClosing {
            Issue.record("저장하지 않음을 선택하면 저장하면 안 된다")
            return true
        })
    }

    @Test func saveFailureKeepsTheWindowOpen() {
        #expect(!SettingsCloseChoice.save.allowsClosing { false })
        #expect(SettingsCloseChoice.save.allowsClosing { true })
    }

    @Test func failedValidationDoesNotRetainHiddenChangesAfterEditsAreRestored() {
        var draft = SettingsDraft(config: .defaultConfig, launchAtLogin: false)
        let originalURL = draft.baseURLText
        let originalPrompt = draft.promptText
        draft.baseURLText = "https://example.com/v1"
        draft.promptText = ""
        #expect(throws: SettingsDraft.ValidationError.self) { try draft.validatedConfig() }
        #expect(draft.config.baseURL == AppConfig.defaultConfig.baseURL)
        draft.baseURLText = originalURL
        draft.promptText = originalPrompt
        #expect(!draft.hasUnsavedChanges)
    }

    @Test func validationNormalizesACandidateWithoutChangingTheDraft() throws {
        var draft = SettingsDraft(config: .defaultConfig, launchAtLogin: false)
        draft.baseURLText = "  https://example.com/v1  "
        draft.promptText = "  Custom prompt\n"
        let config = try draft.validatedConfig()
        #expect(config.baseURL.absoluteString == "https://example.com/v1")
        #expect(config.systemPrompt == "Custom prompt")
        #expect(draft.config.baseURL == AppConfig.defaultConfig.baseURL)
        #expect(draft.config.systemPrompt == nil)
        #expect(draft.hasUnsavedChanges)
    }
}

@MainActor
@Suite(.serialized)
struct SettingsWindowBridgeTests {
    @Test func unchangedSettingsRespectTheOriginalDelegateAndForwardWindowEvents() {
        let window = makeWindow()
        let original = OriginalDelegate()
        let proxy = SettingsWindowCloseConfirmation.CloseDelegate(
            original: original, hasUnsavedChanges: { false }, save: {
                Issue.record("변경이 없으면 저장하면 안 된다")
                return true
            }
        )
        #expect(!proxy.windowShouldClose(window))
        #expect(original.closeRequests == 1)
        let delegate: any NSWindowDelegate = proxy
        delegate.windowDidResize?(Notification(name: NSWindow.didResizeNotification, object: window))
        #expect(original.resizeEvents == 1)
    }

    @Test func reattachingBeforeTheMainQueueRunsStillRestoresTheOriginalDelegate() async {
        let window = makeWindow()
        let original = OriginalDelegate()
        window.delegate = original
        let view = SettingsWindowCloseConfirmation.WindowView()
        window.contentView = view
        window.contentView = NSView()
        window.contentView = view
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(window.delegate is SettingsWindowCloseConfirmation.CloseDelegate)
        view.detach()
        #expect(window.delegate === original)
    }

    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private final class OriginalDelegate: NSObject, NSWindowDelegate {
        var closeRequests = 0
        var resizeEvents = 0
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            closeRequests += 1
            return false
        }
        func windowDidResize(_ notification: Notification) { resizeEvents += 1 }
    }
}
