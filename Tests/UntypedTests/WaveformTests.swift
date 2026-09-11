import Foundation
import Testing
@testable import Untyped

private func near(_ a: CGFloat, _ b: CGFloat) -> Bool {
    abs(a - b) < 1e-6
}

@Test func waveEndpointsStayCenteredRegardlessOfAmplitudeAndPhase() {
    for phase in stride(from: 0.0, to: 2 * CGFloat.pi, by: 0.37) {
        #expect(near(waveY(x: 0, width: 80, height: 20, amplitude: 1, cycles: 2, phase: phase), 10))
        #expect(near(waveY(x: 80, width: 80, height: 20, amplitude: 1, cycles: 2, phase: phase), 10))
    }
}

@Test func waveIsFlatAtZeroAmplitude() {
    for x in stride(from: 0.0, through: 80.0, by: 1.0) {
        #expect(near(waveY(x: x, width: 80, height: 20, amplitude: 0, cycles: 2, phase: 1.3), 10))
    }
}

@Test func waveStaysWithinHeightAtFullAmplitude() {
    for cycles in [1.5, 2.2, 3.1] as [CGFloat] {
        for phase in stride(from: 0.0, to: 2 * CGFloat.pi, by: 0.11) {
            for x in stride(from: 0.0, through: 80.0, by: 1.0) {
                let y = waveY(x: x, width: 80, height: 20, amplitude: 1, cycles: cycles, phase: phase)
                #expect(y >= 0 && y <= 20)
            }
        }
    }
}

@Test func waveDeviationScalesLinearlyWithAmplitude() {
    for x in stride(from: 0.0, through: 80.0, by: 4.0) {
        let full = waveY(x: x, width: 80, height: 20, amplitude: 1, cycles: 2, phase: 0.9) - 10
        let half = waveY(x: x, width: 80, height: 20, amplitude: 0.5, cycles: 2, phase: 0.9) - 10
        #expect(near(half, full / 2))
    }
}

@Test func waveCyclesChangeTheShape() {
    let a = waveY(x: 30, width: 80, height: 20, amplitude: 1, cycles: 2, phase: 0.4)
    let b = waveY(x: 30, width: 80, height: 20, amplitude: 1, cycles: 3, phase: 0.4)
    #expect(!near(a, b))
}

@Test func wavePeaksAreNotAllTheSameHeight() {
    // 단일 정현파라면 테이퍼를 나눈 봉우리 높이가 전부 같다. 두 파를 섞었으면 달라야 한다.
    var peaks: [CGFloat] = []
    var previous: CGFloat = 0
    var rising = false
    for x in stride(from: 1.0, through: 799.0, by: 1.0) {
        let taper = sin(.pi * x / 800)
        let d = abs(waveY(x: x, width: 800, height: 20, amplitude: 1, cycles: 8, phase: 0) - 10) / taper
        if d < previous && rising { peaks.append(previous) }
        rising = d > previous
        previous = d
    }
    #expect(peaks.count >= 4)
    let spread = (peaks.max() ?? 0) - (peaks.min() ?? 0)
    #expect(spread > 1)
}

@Test func amplitudeIsZeroInRoomNoiseRange() {
    #expect(waveAmplitude(level: 0) == 0)
    #expect(waveAmplitude(level: 0.25) == 0)
}

@Test func amplitudeSaturatesAtNormalSpeechLevel() {
    #expect(waveAmplitude(level: 0.7) == 1)
    #expect(waveAmplitude(level: 1) == 1)
}

@Test func amplitudeRisesBetweenFloorAndCeiling() {
    let low = waveAmplitude(level: 0.4)
    let high = waveAmplitude(level: 0.55)
    #expect(low > 0 && low < high && high < 1)
}
