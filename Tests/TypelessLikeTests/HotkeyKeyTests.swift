import Foundation
import Testing
@testable import TypelessLike

@Test(arguments: HotkeyKey.allCases)
func ownKeyCodeWithDeviceBitSetIsDown(key: HotkeyKey) {
    #expect(key.transition(keyCode: key.keyCode, modifierFlags: key.deviceMask) == true)
}

@Test(arguments: HotkeyKey.allCases)
func ownKeyCodeWithDeviceBitClearedIsUp(key: HotkeyKey) {
    #expect(key.transition(keyCode: key.keyCode, modifierFlags: 0) == false)
}

@Test(arguments: HotkeyKey.allCases)
func otherKeysKeyCodeIsIgnored(key: HotkeyKey) {
    for other in HotkeyKey.allCases where other != key {
        // 비트가 켜져 있어도 keyCode가 다르면 이 키의 이벤트가 아니다.
        #expect(key.transition(keyCode: other.keyCode, modifierFlags: key.deviceMask) == nil)
    }
}

@Test func rightOptionReleaseWhileLeftOptionHeldIsUp() {
    // 오른쪽 Option을 놓는 순간 왼쪽 Option이 눌려 있으면 modifierFlags에는
    // 일반 .option 비트(1<<19)와 왼쪽 장치 비트가 남아 있다. 오른쪽만 보면 "뗌"이다.
    let generalOptionBit: UInt = 1 << 19
    let flags = HotkeyKey.leftOption.deviceMask | generalOptionBit
    #expect(HotkeyKey.rightOption.transition(keyCode: 0x3D, modifierFlags: flags) == false)
}

@Test func keyCodesMatchCarbonConstants() {
    #expect(HotkeyKey.leftCommand.keyCode == 0x37)
    #expect(HotkeyKey.rightCommand.keyCode == 0x36)
    #expect(HotkeyKey.leftShift.keyCode == 0x38)
    #expect(HotkeyKey.rightShift.keyCode == 0x3C)
    #expect(HotkeyKey.leftOption.keyCode == 0x3A)
    #expect(HotkeyKey.rightOption.keyCode == 0x3D)
    #expect(HotkeyKey.leftControl.keyCode == 0x3B)
    #expect(HotkeyKey.rightControl.keyCode == 0x3E)
}

@Test func deviceMasksMatchIOLLEventConstants() {
    #expect(HotkeyKey.leftControl.deviceMask == 0x0001)
    #expect(HotkeyKey.leftShift.deviceMask == 0x0002)
    #expect(HotkeyKey.rightShift.deviceMask == 0x0004)
    #expect(HotkeyKey.leftCommand.deviceMask == 0x0008)
    #expect(HotkeyKey.rightCommand.deviceMask == 0x0010)
    #expect(HotkeyKey.leftOption.deviceMask == 0x0020)
    #expect(HotkeyKey.rightOption.deviceMask == 0x0040)
    #expect(HotkeyKey.rightControl.deviceMask == 0x2000)
}

@Test func rightSideKeysComeFirstInAllCases() {
    // Picker 순서. 일상 조합키에 덜 쓰이는 오른쪽 키가 먼저다.
    #expect(HotkeyKey.allCases.first == .rightOption)
    let rightCount = HotkeyKey.allCases.prefix(4).filter { $0.rawValue.hasPrefix("right_") }.count
    #expect(rightCount == 4)
}

@Test func rawValuesRoundTripThroughJSON() throws {
    for key in HotkeyKey.allCases {
        let data = try JSONEncoder().encode(key)
        #expect(try JSONDecoder().decode(HotkeyKey.self, from: data) == key)
    }
}
