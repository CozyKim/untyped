import CoreAudio
import Foundation

/// 녹음 중 다른 앱의 스피커 출력을 막아, 그 소리가 마이크로 되돌아 들어오지 않게 한다.
///
/// Core Audio Process Tap을 `.mutedWhenTapped`로 만들고, 탭만 담은 aggregate device에
/// IOProc을 걸어 읽기만 하면 읽는 동안 다른 프로세스의 오디오가 하드웨어로 나가지
/// 않는다. 출력 장치의 볼륨을 만지지 않으므로 HDMI/DisplayPort처럼 볼륨 조절 자체가
/// 없는 장치에서도 동작한다.
///
/// `.muted`(읽지 않아도 음소거)를 쓰지 않는 이유: 탭을 파괴한 뒤에도 이미 열려 있던
/// 다른 앱의 스트림에 음소거가 남아, 사용자가 재생을 다시 시작해야 소리가 돌아오는
/// 것이 관찰됐다. `.mutedWhenTapped`는 IO를 멈추는 순간 복원된다.
///
/// 탭으로 받은 오디오는 버린다 — 이 타입은 녹음하지 않는다. 가로챈 소리를 작게 다시
/// 내보내는 "줄이기"는 불가능하다: 탭이 읽히는 동안에는 탭에서 제외한 프로세스의
/// 출력까지 장치 전체가 음소거된다.
actor SystemAudioMuter {
    private var tap: AudioObjectID?
    private var aggregate: AudioObjectID?
    private var ioProc: AudioDeviceIOProcID?

    /// 실패해도 던지지 않는다. 음소거는 받아쓰기의 부가 기능이라 녹음을 막으면 안 된다.
    func mute() {
        guard tap == nil else { return }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        var tapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            NSLog("[SystemAudioMuter] 탭 생성 실패: %d", status)
            return
        }
        tap = tapID

        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Untyped Mute",
            kAudioAggregateDeviceUIDKey: "com.jaehyun.untyped.mute",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: 1,
            ]],
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregateID)
        guard status == noErr else {
            NSLog("[SystemAudioMuter] aggregate device 생성 실패: %d", status)
            unmute()
            return
        }
        aggregate = aggregateID

        var procID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, _, _, _, _ in }
        guard status == noErr, let procID else {
            NSLog("[SystemAudioMuter] IOProc 생성 실패: %d", status)
            unmute()
            return
        }
        ioProc = procID

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            NSLog("[SystemAudioMuter] IO 시작 실패: %d", status)
            unmute()
            return
        }
    }

    /// 만들어 둔 것만 되돌린다. 음소거 중이 아니면 아무것도 하지 않는다.
    func unmute() {
        if let aggregate, let ioProc {
            AudioDeviceStop(aggregate, ioProc)
            AudioDeviceDestroyIOProcID(aggregate, ioProc)
        }
        if let aggregate {
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        if let tap {
            AudioHardwareDestroyProcessTap(tap)
        }
        ioProc = nil
        aggregate = nil
        tap = nil
    }
}
