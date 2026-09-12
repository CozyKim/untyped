import CoreAudio
import Testing
@testable import Untyped

// 음소거 탭의 대상 고르기. 다른 앱이 시스템 오디오를 탭으로 가로채 다시 내보내고 있으면
// (Toneka 같은 이퀄라이저) 그 앱만 탭해야 한다. 원본 앱까지 함께 탭하면 coreaudiod가 원본
// 앱과 기존 탭의 연결을 잃어 음소거를 풀어도 소리가 돌아오지 않는 것이 관찰됐다.

private func process(
    _ id: AudioObjectID, input: Bool, output: Bool, visibleInput: Bool
) -> AudioProcessState {
    AudioProcessState(id: id, isRunningInput: input, isRunningOutput: output, hasVisibleInputDevice: visibleInput)
}

@Test func equalizerReadingATapIsARenderer() {
    // 입력 IO가 돌지만 보이는 입력 장치가 없다 — 입력이 비공개 aggregate 안의 탭이다.
    let toneka = process(10, input: true, output: true, visibleInput: false)
    #expect(tapRenderers(in: [toneka]) == [10])
}

@Test func playerWithoutInputIsNotARenderer() {
    let spotify = process(11, input: false, output: true, visibleInput: false)
    #expect(tapRenderers(in: [spotify]).isEmpty)
}

@Test func microphoneAppIsNotARenderer() {
    // 통화 앱은 입력과 출력이 함께 돌지만 입력 장치(마이크)가 보인다.
    let call = process(12, input: true, output: true, visibleInput: true)
    #expect(tapRenderers(in: [call]).isEmpty)
}

@Test func recorderReadingATapWithoutOutputIsNotARenderer() {
    // 탭을 읽기만 하고 내보내지 않으면 스피커로 나가는 소리가 아니다.
    let recorder = process(13, input: true, output: false, visibleInput: false)
    #expect(tapRenderers(in: [recorder]).isEmpty)
}

@Test func onlyRenderersAreKeptInOrder() {
    let list = [
        process(11, input: false, output: true, visibleInput: false),
        process(10, input: true, output: true, visibleInput: false),
        process(12, input: true, output: true, visibleInput: true),
        process(14, input: true, output: true, visibleInput: false),
    ]
    #expect(tapRenderers(in: list) == [10, 14])
}

@Test func noProcessesMeansNoRenderers() {
    #expect(tapRenderers(in: []).isEmpty)
}
