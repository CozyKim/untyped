import AppKit
import SwiftUI

enum OverlayStatus: String, Sendable {
    case recording = "녹음 중"
    case refining = "다듬는 중"
}

/// 키 윈도우가 되면 원래 앱의 텍스트 포커스가 풀려 ⌘V 삽입이 엉뚱한 곳으로 간다.
/// canBecomeKey를 false로 두는 것이 이 클래스의 존재 이유다.
private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private let model = OverlayModel()

    func show(status: OverlayStatus) {
        model.status = status
        if panel == nil { panel = makePanel() }
        positionAtBottomCenter()
        panel?.orderFrontRegardless()
    }

    func update(level: Float) {
        model.level = meterLevel(level)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 64),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        return panel
    }

    private func positionAtBottomCenter() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - 120, y: frame.minY + 120))
    }
}

@Observable
final class OverlayModel {
    var status: OverlayStatus = .recording
    var level: Float = 0
}

private struct OverlayView: View {
    @Bindable var model: OverlayModel

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(model.status == .recording ? Color.red : Color.orange)
                .frame(width: 10, height: 10)
            Text(model.status.rawValue)
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
            LevelMeter(level: model.level)
                .frame(width: 90, height: 12)
        }
        .padding(.horizontal, 16)
        .frame(width: 240, height: 64)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(.tint)
                    .frame(width: geometry.size.width * CGFloat(level))
            }
        }
        // 버퍼 주기로 값이 들어오므로 별도 스무딩 코드 없이 여기서 떨림을 흡수한다.
        .animation(.linear(duration: 0.1), value: level)
    }
}
