import Testing
@testable import TypelessLike

@Test func rmsOfEmptyBufferIsZero() {
    let samples: [Float] = []
    #expect(samples.withUnsafeBufferPointer { rms($0) } == 0)
}

@Test func rmsOfSilenceIsZero() {
    let samples = [Float](repeating: 0, count: 512)
    #expect(samples.withUnsafeBufferPointer { rms($0) } == 0)
}

@Test func rmsOfFullScaleIsOne() {
    let samples = [Float](repeating: 1, count: 512)
    let value = samples.withUnsafeBufferPointer { rms($0) }
    #expect(abs(value - 1) < 0.0001)
}

@Test func rmsIgnoresSign() {
    let a: [Float] = [0.5, 0.5, 0.5, 0.5]
    let b: [Float] = [-0.5, 0.5, -0.5, 0.5]
    let ra = a.withUnsafeBufferPointer { rms($0) }
    let rb = b.withUnsafeBufferPointer { rms($0) }
    #expect(abs(ra - rb) < 0.0001)
}

@Test func meterLevelIsClampedToUnitRange() {
    #expect(meterLevel(0) == 0)
    #expect(meterLevel(10) == 1)
    let mid = meterLevel(0.1)
    #expect(mid > 0 && mid < 1)
}

@Test func meterLevelFollowsDecibelCurve() {
    let value = meterLevel(0.1)
    let expected: Float = 0.6667
    #expect(abs(value - expected) < 0.001)
}

@Test func meterLevelRespectsFloorBoundary() {
    let value = meterLevel(0.001)
    #expect(abs(value - 0) < 0.001)
}
