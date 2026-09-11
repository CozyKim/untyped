import AppKit
import SwiftUI

enum OverlayStatus: Equatable, Sendable {
    case recording
    case refining
    /// 삽입이 끝난 뒤 잠깐 보여주는 안내. 문구는 호출자가 정한다.
    case notice(String)

    var label: String {
        switch self {
        case .recording: "녹음 중"
        case .refining: "다듬는 중"
        case .notice(let text): text
        }
    }

    /// 안내 문구는 상태 라벨보다 길어 패널을 넓게 잡는다.
    var width: CGFloat {
        if case .notice = self { return 320 }
        return 240
    }
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
        model.level = 0
        if panel == nil { panel = makePanel() }
        panel?.setContentSize(NSSize(width: status.width, height: 64))
        guard positionAtBottomCenter() else { return }
        panel?.orderFrontRegardless()
    }

    /// 안내를 잠깐 띄웠다 거둔다. 그 사이 새 녹음이 시작돼 상태가 바뀌었으면
    /// 거두지 않는다 — 녹음 표시를 지워 버리면 안 된다.
    func showNotice(_ text: String, for duration: Duration = .seconds(2.5)) {
        let status = OverlayStatus.notice(text)
        show(status: status)
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, self.model.status == status else { return }
            self.hide()
        }
    }

    func update(level: Float) {
        model.level = meterLevel(level)
    }

    func hide() {
        model.level = 0
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
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        return panel
    }

    private func positionAtBottomCenter() -> Bool {
        guard let panel else { return false }

        // 마우스 위치의 화면을 선택한다. NSScreen.main은 "키 윈도우가 있는 화면"을
        // 뜻하는데, 이 앱은 키 윈도우를 가지지 않으므로 예측 불가능하다.
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = (NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
                           ?? NSScreen.main
                           ?? NSScreen.screens.first)
        guard let screen = targetScreen else { return false }

        let frame = screen.visibleFrame
        let panelWidth = panel.frame.width
        let xOffset = frame.midX - panelWidth / 2
        panel.setFrameOrigin(NSPoint(x: xOffset, y: frame.minY + 120))
        return true
    }
}

@MainActor
@Observable
private final class OverlayModel {
    var status: OverlayStatus = .recording
    var level: Float = 0
}

private struct OverlayView: View {
    @Bindable var model: OverlayModel

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
            Text(model.status.label)
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
            if case .notice = model.status {
                // 안내에는 소리 레벨이 없다. 빈 미터를 보여주지 않는다.
            } else {
                LevelMeter(level: model.level)
                    .frame(width: 90, height: 12)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: model.status.width, height: 64)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var dotColor: Color {
        switch model.status {
        case .recording: .red
        case .refining: .orange
        case .notice: .yellow
        }
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
