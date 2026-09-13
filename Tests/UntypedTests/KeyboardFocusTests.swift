import Testing
@testable import Untyped

@Test func unreadableSystemFocusUsesPositiveElementFocus() {
    // -25204(CannotComplete)를 PID nil로 전달하더라도 앱별 AXFocused=true는 유효한 증거다.
    #expect(TargetApp.keyboardFocusMatches(
        frontmostPID: 42, targetPID: 42, focusedApplicationPID: nil, elementIsFocused: true
    ))
}

@Test func keyboardFocusFallbackNeverOverridesAnotherAppOrUnknownElement() {
    #expect(!TargetApp.keyboardFocusMatches(
        frontmostPID: 43, targetPID: 42, focusedApplicationPID: nil, elementIsFocused: true
    ))
    #expect(!TargetApp.keyboardFocusMatches(
        frontmostPID: 42, targetPID: 42, focusedApplicationPID: 43, elementIsFocused: true
    ))
    #expect(!TargetApp.keyboardFocusMatches(
        frontmostPID: 42, targetPID: 42, focusedApplicationPID: nil, elementIsFocused: nil
    ))
    #expect(!TargetApp.keyboardFocusMatches(
        frontmostPID: 42, targetPID: 42, focusedApplicationPID: nil, elementIsFocused: false
    ))
}
