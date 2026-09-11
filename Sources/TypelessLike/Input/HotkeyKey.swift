import Foundation

/// 트리거로 쓸 수 있는 단독 수식키.
///
/// 단독 수식키라 다른 앱의 단축키와 충돌하지 않고 flagsChanged로 눌림과 뗌을
/// 모두 받을 수 있다. Fn은 시스템이 받아쓰기와 이모지 입력에 쓰고, Caps Lock은
/// 토글식이라 누르고 있는 동안 녹음하는 동작이 성립하지 않아 제외한다.
///
/// rawValue가 config.json에 저장된다. allCases 순서가 설정 창 Picker의 순서다 —
/// 일상 조합키(⌘C 등)에 덜 쓰이는 오른쪽 키를 먼저 둔다.
enum HotkeyKey: String, Codable, CaseIterable, Sendable, Hashable {
    case rightOption = "right_option"
    case rightCommand = "right_command"
    case rightControl = "right_control"
    case rightShift = "right_shift"
    case leftOption = "left_option"
    case leftCommand = "left_command"
    case leftControl = "left_control"
    case leftShift = "left_shift"

    /// HIToolbox/Events.h의 kVK_* 값.
    var keyCode: UInt16 {
        switch self {
        case .leftCommand: 0x37
        case .rightCommand: 0x36
        case .leftShift: 0x38
        case .rightShift: 0x3C
        case .leftOption: 0x3A
        case .rightOption: 0x3D
        case .leftControl: 0x3B
        case .rightControl: 0x3E
        }
    }

    /// IOKit/hidsystem/IOLLEvent.h의 NX_DEVICE*KEYMASK 값.
    /// modifierFlags.rawValue의 낮은 16비트에 장치 고유 수식키 비트가 있다.
    var deviceMask: UInt {
        switch self {
        case .leftControl: 0x0001
        case .leftShift: 0x0002
        case .rightShift: 0x0004
        case .leftCommand: 0x0008
        case .rightCommand: 0x0010
        case .leftOption: 0x0020
        case .rightOption: 0x0040
        case .rightControl: 0x2000
        }
    }

    var displayName: String {
        switch self {
        case .rightOption: "오른쪽 ⌥ Option"
        case .rightCommand: "오른쪽 ⌘ Command"
        case .rightControl: "오른쪽 ⌃ Control"
        case .rightShift: "오른쪽 ⇧ Shift"
        case .leftOption: "왼쪽 ⌥ Option"
        case .leftCommand: "왼쪽 ⌘ Command"
        case .leftControl: "왼쪽 ⌃ Control"
        case .leftShift: "왼쪽 ⇧ Shift"
        }
    }

    /// flagsChanged 이벤트가 이 키의 것이면 눌림 여부를, 다른 키면 nil을 돌려준다.
    ///
    /// modifierFlags.contains(.option) 같은 검사는 왼쪽 Option이 눌려도 true가 되어,
    /// 오른쪽 Option을 놓으면서 왼쪽 Option이 눌려 있으면 뗌을 감지하지 못한다.
    /// 장치 고유 마스크로 이 키만 검사한다.
    func transition(keyCode: UInt16, modifierFlags: UInt) -> Bool? {
        guard keyCode == self.keyCode else { return nil }
        return modifierFlags & deviceMask != 0
    }
}
