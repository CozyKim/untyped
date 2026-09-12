import AppKit
import SwiftUI

enum OverlayStatus: Equatable, Sendable {
    case listening
    case refining
    /// 삽입이 끝난 뒤 잠깐 보여주는 안내. 문구는 호출자가 정한다.
    case notice(String)

    /// pill의 높이. 미리보기가 없을 때는 모든 상태에서 같다.
    static let pillHeight: CGFloat = 52

    /// 안내 문구는 파형·스피너보다 넓은 자리가 필요하다.
    var width: CGFloat {
        if case .notice = self { return 320 }
        return 160
    }

    /// 패널 크기. 듣는 중에는 파형 아래 미리보기가 들어갈 자리를 미리 잡는다 — 텍스트가 올 때마다
    /// 패널을 다시 재지 않고 pill만 안에서 늘어난다. 내용은 위 정렬이라 남는 자리는 투명하다.
    var panelSize: CGSize {
        switch self {
        case .listening: CGSize(width: PreviewLayout.width, height: Self.pillHeight + PreviewLayout.height)
        case .refining, .notice: CGSize(width: width, height: Self.pillHeight)
        }
    }
}

/// 파형 아래 미리보기 텍스트 자리. 마지막 두 줄만 보인다.
private enum PreviewLayout {
    static let width: CGFloat = 360
    static let fontSize: CGFloat = 13
    /// 13pt 시스템 글꼴 한 줄. ImageRenderer로 실측한 값이다.
    static let lineHeight: CGFloat = 16
    static let textHeight: CGFloat = lineHeight * 2
    static let bottomPadding: CGFloat = 10
    static let height: CGFloat = textHeight + bottomPadding
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
        model.preview = ""
        model.isVisible = true
        if panel == nil { panel = makePanel() }
        panel?.setContentSize(status.panelSize)
        guard positionAtBottomCenter() else { return }
        panel?.orderFrontRegardless()
    }

    /// 안내를 잠깐 띄웠다 거둔다. 그 사이 새 녹음이 시작돼 상태가 바뀌었으면
    /// 거두지 않는다 — 듣는 중 표시를 지워 버리면 안 된다.
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

    /// 듣는 동안 파형 아래에 보여줄 잠정 전사. 상태가 바뀌면(show·hide) 비워진다.
    func update(preview: String) {
        model.preview = preview
    }

    func hide() {
        model.level = 0
        model.preview = ""
        model.isVisible = false
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 52),
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
        // pill 윗변을 상태와 무관하게 같은 높이에 둔다. 듣는 중 패널은 미리보기 자리만큼 더 높고
        // 내용은 위 정렬이라, 원점을 그만큼 내려야 파형이 스피너와 같은 자리에 온다.
        let top = frame.minY + 120 + OverlayStatus.pillHeight
        panel.setFrameOrigin(NSPoint(x: xOffset, y: top - panel.frame.height))
        return true
    }
}

@MainActor
@Observable
private final class OverlayModel {
    var status: OverlayStatus = .listening
    var level: Float = 0
    /// 듣는 중 파형 아래에 보여줄 잠정 전사. 비어 있으면 자리도 없다.
    var preview = ""
    /// 패널을 orderOut 해도 SwiftUI 뷰는 살아 있다. 숨긴 동안 TimelineView가
    /// 보이지 않는 파형을 60fps로 그리지 않도록 이 값으로 스케줄을 멈춘다.
    var isVisible = false
}

private struct OverlayView: View {
    @Bindable var model: OverlayModel

    var body: some View {
        TimelineView(.animation(paused: !model.isVisible)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            VStack(spacing: 0) {
                statusContent(seconds: seconds)
                    .frame(width: model.status.width, height: OverlayStatus.pillHeight)
                if !model.preview.isEmpty {
                    Text(model.preview)
                        .font(.system(size: PreviewLayout.fontSize))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        // 아래 정렬 + 클립으로 마지막 두 줄만 남긴다. truncationMode(.head)는 첫 줄을
                        // 남기고 마지막 줄 머리만 잘라 쓸 수 없다. 뒤의 fixedSize가 없으면 한 줄일 때도
                        // 두 줄 높이를 차지한다.
                        .frame(maxHeight: PreviewLayout.textHeight, alignment: .bottom)
                        .fixedSize(horizontal: false, vertical: true)
                        .clipped()
                        .padding(.horizontal, 16)
                        .padding(.bottom, PreviewLayout.bottomPadding)
                        .frame(width: PreviewLayout.width)
                }
            }
            // pill 높이에서는 Capsule과 같은 모양이고, 미리보기로 길어져도 모서리는 그대로다.
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: OverlayStatus.pillHeight / 2))
            .animation(.easeOut(duration: 0.15), value: model.preview.isEmpty)
        }
        .frame(width: model.status.panelSize.width, height: model.status.panelSize.height, alignment: .top)
    }

    @ViewBuilder
    private func statusContent(seconds: TimeInterval) -> some View {
        switch model.status {
        case .listening:
            ZStack {
                ForEach(WaveLayer.all, id: \.cycles) { layer in
                    // 조용할 때도 살짝 흔들려야 "듣고 있음"이 보인다.
                    WaveShape(
                        amplitude: CGFloat(max(0.1, waveAmplitude(level: model.level))) * layer.scale,
                        cycles: layer.cycles,
                        phase: CGFloat(seconds.truncatingRemainder(dividingBy: layer.period) / layer.period * 2 * .pi)
                    )
                    .fill(layer.color)
                }
            }
            .frame(width: 132, height: 38)
            // 버퍼 주기로 값이 들어오므로 별도 스무딩 코드 없이 여기서 떨림을 흡수한다.
            .animation(.linear(duration: 0.1), value: model.level)
        case .refining:
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(WaveLayer.all[1].color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 22, height: 22)
                .rotationEffect(.degrees(seconds.truncatingRemainder(dividingBy: 1) * 360))
        case .notice(let text):
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 16)
        }
    }
}

/// 겹쳐 그리는 파형 한 겹. 주기 수·흐름 속도·크기가 서로 달라 겹치면 봉우리가 계속 바뀐다.
private struct WaveLayer {
    let cycles: CGFloat
    /// 위상이 한 바퀴 도는 데 걸리는 초. 짧을수록 빨리 흐른다.
    let period: TimeInterval
    let scale: CGFloat
    let color: Color

    /// 뒤에서 앞 순서. 뒤쪽이 가장 크고 느리다.
    static let all: [WaveLayer] = [
        WaveLayer(cycles: 1.5, period: 1.1, scale: 1.0, color: Color(red: 0.35, green: 0.75, blue: 1.0).opacity(0.45)),
        WaveLayer(cycles: 2.2, period: 0.8, scale: 0.8, color: Color(red: 0.15, green: 0.5, blue: 1.0).opacity(0.5)),
        WaveLayer(cycles: 3.1, period: 0.65, scale: 0.6, color: Color(red: 0.3, green: 0.9, blue: 0.95).opacity(0.5)),
    ]
}

/// 중앙선 위아래로 대칭인 채움 도형. 진폭만 animatable로 둔다 — 위상은 매 프레임 시간에서
/// 새로 오므로 보간 대상이 아니다.
private struct WaveShape: Shape {
    var amplitude: CGFloat
    var cycles: CGFloat
    var phase: CGFloat

    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let xs = Array(stride(from: CGFloat(0), through: rect.width, by: 1))
        for (i, x) in xs.enumerated() {
            let y = waveY(x: x, width: rect.width, height: rect.height, amplitude: amplitude, cycles: cycles, phase: phase)
            let point = CGPoint(x: rect.minX + x, y: rect.minY + y)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        // 같은 곡선을 거꾸로 되돌아오며 중앙선 대칭으로 닫는다.
        for x in xs.reversed() {
            let y = waveY(x: x, width: rect.width, height: rect.height, amplitude: amplitude, cycles: cycles, phase: phase)
            path.addLine(to: CGPoint(x: rect.minX + x, y: rect.minY + rect.height - y))
        }
        path.closeSubpath()
        return path
    }
}

/// 선 파형 한 점의 y 좌표. amplitude는 0…1, cycles는 폭 안에 들어가는 주기 수, phase는 라디안.
/// 주파수가 2.3배인 두 번째 정현파를 반대 방향으로 흘려 섞어, 봉우리 높이가 제각각이고
/// 시간에 따라 제자리에서 오르내리게 한다. 가중치 합이 1이라 편차는 height/2를 넘지 않는다.
/// sin(π·x/width) 테이퍼를 곱해 양 끝은 항상 중앙선에 붙는다. 순수 함수로 두어 뷰 없이 검증한다.
func waveY(x: CGFloat, width: CGFloat, height: CGFloat, amplitude: CGFloat, cycles: CGFloat, phase: CGFloat) -> CGFloat {
    let t = x / width
    let taper = sin(.pi * t)
    let primary = sin(2 * .pi * cycles * t + phase)
    let secondary = sin(2 * .pi * cycles * 2.3 * t - phase * 1.7)
    return height / 2 + amplitude * (height / 2) * (0.65 * primary + 0.35 * secondary) * taper
}

/// 미터 레벨(0…1, -60dB 기준)을 파형 진폭(0…1)으로 되돌린다.
/// 실내 소음 구간(-45dB 이하)은 0으로 깔고 -18dB에서 최대에 닿게 해, 보통 말소리에서
/// 파형이 거의 끝까지 올라가도록 한다. 원래 곡선 그대로면 말소리가 절반 높이에 머문다.
func waveAmplitude(level: Float) -> Float {
    let floor: Float = 0.25
    let ceiling: Float = 0.7
    return max(0, min(1, (level - floor) / (ceiling - floor)))
}
