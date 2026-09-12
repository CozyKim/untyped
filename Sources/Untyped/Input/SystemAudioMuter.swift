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
///
/// 다른 앱이 이미 시스템 오디오를 탭으로 가로채 다시 내보내고 있으면(Toneka 같은
/// 이퀄라이저) 그 앱만 탭한다. 스피커로 나가는 소리는 그 앱의 출력뿐이고, 원본 앱
/// (Spotify 등)은 이미 그 앱의 탭에 음소거돼 있다. 원본 앱까지 함께 탭하면 coreaudiod가
/// 원본 앱의 탭 라우팅을 다시 짜다가 기존 탭과의 연결을 놓쳐, 음소거를 풀어도 원본 앱의
/// 소리가 그 탭에 닿지 않아 재생 중인데 스피커는 무음이 되고 원본 앱이나 그 앱을 재시작해야
/// 돌아오는 것이 관찰됐다. 그런 앱이 없으면 전체를 탭한다.
actor SystemAudioMuter {
    private var tap: AudioObjectID?
    private var aggregate: AudioObjectID?
    private var ioProc: AudioDeviceIOProcID?

    /// 지금 시스템 오디오를 다시 내보내고 있는 프로세스들. `mute(renderers:)`에 넘긴다.
    /// 출력 중인 프로세스마다 coreaudiod에 속성을 물어 40ms 넘게 걸리므로, 호출자가 마이크
    /// 준비와 겹쳐 돌릴 수 있게 음소거와 분리했다.
    func tapRenderers() -> [AudioObjectID] {
        Untyped.tapRenderers(in: Self.audioProcessStates())
    }

    /// 실패해도 던지지 않는다. 음소거는 받아쓰기의 부가 기능이라 녹음을 막으면 안 된다.
    /// `renderers`가 비어 있으면 모든 프로세스를 음소거한다.
    func mute(renderers: [AudioObjectID]) {
        guard tap == nil else { return }

        let description: CATapDescription
        if renderers.isEmpty {
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        } else {
            NSLog("[SystemAudioMuter] 시스템 오디오를 다시 내보내는 앱만 음소거: %@", "\(renderers)")
            description = CATapDescription(stereoMixdownOfProcesses: renderers)
        }
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

    /// 출력 IO가 돌고 있는 오디오 프로세스들의 상태. 속성 조회는 프로세스마다 coreaudiod를
    /// 오가므로, 출력이 없는 프로세스(대부분)는 첫 조회에서 걸러 나머지 조회를 아낀다.
    private static func audioProcessStates() -> [AudioProcessState] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        return objectIDs(of: system, kAudioHardwarePropertyProcessObjectList).compactMap { id in
            guard flag(of: id, kAudioProcessPropertyIsRunningOutput) == true,
                  let input = flag(of: id, kAudioProcessPropertyIsRunningInput)
            else { return nil }
            let inputDevices = objectIDs(
                of: id, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput
            )
            return AudioProcessState(
                id: id, isRunningInput: input, isRunningOutput: true,
                hasVisibleInputDevice: !inputDevices.isEmpty
            )
        }
    }

    private static func objectIDs(
        of object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func flag(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }
}

/// 오디오 프로세스 하나의 IO 상태. coreaudiod의 프로세스 객체 속성에서 읽는다.
struct AudioProcessState: Equatable, Sendable {
    let id: AudioObjectID
    let isRunningInput: Bool
    let isRunningOutput: Bool
    /// 입력 장치 목록이 비어 있지 않은지. 탭은 비공개 aggregate 안에만 있어 다른 프로세스에는
    /// 장치로 보이지 않으므로, 입력 IO가 도는데 이 값이 거짓이면 입력이 탭이다.
    let hasVisibleInputDevice: Bool
}

/// 시스템 오디오를 탭으로 읽어 스피커로 다시 내보내는 프로세스들. 마이크를 쓰는 앱은 입력
/// 장치가 보이고, 탭을 녹음만 하는 앱은 출력이 없어서 둘 다 제외된다.
func tapRenderers(in processes: [AudioProcessState]) -> [AudioObjectID] {
    processes
        .filter { $0.isRunningInput && $0.isRunningOutput && !$0.hasVisibleInputDevice }
        .map(\.id)
}
