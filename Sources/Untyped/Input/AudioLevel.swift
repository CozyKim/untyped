import Foundation

/// 오디오 콜백마다 배열을 복사하지 않으려고 포인터를 받는다.
/// 테스트에서는 [Float]로부터 만들면 되므로 검증에 지장이 없다.
func rms(_ samples: UnsafeBufferPointer<Float>) -> Float {
    guard !samples.isEmpty else { return 0 }
    var sum: Float = 0
    for s in samples { sum += s * s }
    return (sum / Float(samples.count)).squareRoot()
}

/// RMS를 dB로 바꿔 표시 범위(-60dB ~ 0dB)로 클램프한 0…1 값.
/// 선형 RMS를 그대로 그리면 말소리 구간이 막대 아래쪽에 몰려 안 보인다.
func meterLevel(_ value: Float) -> Float {
    guard value > 0 else { return 0 }
    let db = 20 * log10(value)
    let floorDB: Float = -60
    return max(0, min(1, (db - floorDB) / -floorDB))
}
