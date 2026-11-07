import Foundation

/// 같은 입력창으로 보내더라도 녹음을 시작한 키와 의도를 별도로 기억한다.
enum RecordingRoute: CaseIterable, Hashable, Sendable {
    case frontmost, targetApp, edit, literal

    var destination: InsertDestination { self == .targetApp ? .targetApp : .frontmost }

    var displayName: String {
        switch self {
        case .frontmost: "기본 받아쓰기"
        case .targetApp: "앱으로 보내기"
        case .edit: "수정 전용"
        case .literal: "일반 받아쓰기 전용"
        }
    }
}

struct RecordingPolicy {
    let route: RecordingRoute
    let commandsEnabled: Bool
    let rules: VoiceCommandRules

    var needsRawAudio: Bool {
        route == .edit || (route != .literal && commandsEnabled && (rules.editEnabled || rules.submitEnabled))
    }

    var permitsAutomaticReturn: Bool { route != .literal && route != .edit }

    func command(for text: String) -> VoiceCommand? {
        switch route {
        case .literal: return nil
        case .edit:
            // 전용 키에서는 '보내'도 수정 지시의 본문이다. 음성 명령 설정과 독립이다.
            return .edit(text)
        case .frontmost, .targetApp:
            return VoiceCommand.parse(text, enabled: commandsEnabled, rules: rules)
        }
    }
}
