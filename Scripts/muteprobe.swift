// 음소거 탭이 다른 앱의 재생을 깨뜨리는지 검증하는 도구.
//
// SystemAudioMuter와 같은 순서로 탭·aggregate·IOProc을 만들고 부수기를 반복하면서, 별도의
// `.unmuted` 탭으로 (1) 원본 앱(기본 Spotify)이 내는 소리와 (2) 시스템 오디오를 탭으로 읽어
// 다시 내보내는 앱(Toneka 같은 이퀄라이저)이 렌더링하는 소리를 250ms마다 측정한다.
// 원본 앱은 소리를 내는데 재생기가 1초 넘게 무음이면 "BROKEN"을 찍고 3으로 끝낸다 —
// coreaudiod가 원본 앱과 재생기 탭의 연결을 잃은 상태이며, 원본 앱이나 재생기를 재시작해야
// 돌아온다. 재생기가 없으면 원본 앱 쪽만 측정한다.
//
// 빌드·실행 (원본 앱을 재생 중인 상태에서):
//   swiftc -O -o /tmp/muteprobe Scripts/muteprobe.swift
//   /tmp/muteprobe --mic --cycles 40 --hold 120 --gap 300
// 옵션:
//   --tap auto|all|renderer  탭 대상. auto는 앱과 같은 규칙(재생기가 있으면 그것만, 없으면 전체).
//   --mic                    녹음처럼 사이클마다 마이크를 열고 닫는다.
//   --source <bundle id>     원본 앱 (기본 com.spotify.client).
//   --cycles N --hold MS --gap MS --settle MS --baseline MS
// 종료 코드: 0 정상, 2 측정 불가, 3 고장 재현.

import AVFAudio
import CoreAudio
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

var cycles = 3, holdMS = 150, gapMS = 2000, settleMS = 5000, baselineMS = 3000
var useMic = false
var tapTarget = "auto"
var sourceBundle = "com.spotify.client"
var args = CommandLine.arguments.dropFirst().makeIterator()
while let a = args.next() {
    switch a {
    case "--cycles": cycles = Int(args.next()!)!
    case "--hold": holdMS = Int(args.next()!)!
    case "--gap": gapMS = Int(args.next()!)!
    case "--settle": settleMS = Int(args.next()!)!
    case "--baseline": baselineMS = Int(args.next()!)!
    case "--mic": useMic = true
    case "--tap": tapTarget = args.next()!
    case "--source": sourceBundle = args.next()!
    default: fatalError("unknown arg \(a)")
    }
}

// MARK: - Core Audio 속성 읽기

func address(
    _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func objectIDs(
    of object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> [AudioObjectID] {
    var addr = address(selector, scope: scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func flag(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool? {
    var addr = address(selector)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
    return value != 0
}

func string(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var addr = address(selector)
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var value: Unmanaged<CFString>?
    guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
    return value.takeRetainedValue() as String
}

struct AudioProcess {
    let id: AudioObjectID
    let bundleID: String
    let isRunningInput: Bool
    let isRunningOutput: Bool
    let hasVisibleInputDevice: Bool
    /// SystemAudioMuter와 같은 규칙: 입력 IO가 도는데 보이는 입력 장치가 없으면 입력이 탭이다.
    var isRenderer: Bool { isRunningInput && isRunningOutput && !hasVisibleInputDevice }
}

let processes: [AudioProcess] = objectIDs(of: AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
    .compactMap { id in
        guard let input = flag(of: id, kAudioProcessPropertyIsRunningInput),
              let output = flag(of: id, kAudioProcessPropertyIsRunningOutput) else { return nil }
        let inputDevices = objectIDs(of: id, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput)
        return AudioProcess(
            id: id, bundleID: string(of: id, kAudioProcessPropertyBundleID) ?? "",
            isRunningInput: input, isRunningOutput: output, hasVisibleInputDevice: !inputDevices.isEmpty
        )
    }
let source = processes.first { $0.bundleID == sourceBundle }
let renderers = processes.filter(\.isRenderer)
print("source: \(source.map { "\($0.bundleID) (\($0.id))" } ?? "없음")")
print("renderers: \(renderers.map { "\($0.bundleID) (\($0.id))" })")

// MARK: - 관찰용 탭

/// 지정한 프로세스의 출력을 `.unmuted` 탭으로 받아 피크(dBFS)를 잰다. 음소거하지 않는다.
final class Monitor {
    let label: String
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    // [0] = 마지막 읽기 이후 피크. IO 스레드가 쓰고 메인 스레드가 읽는다.
    private let peak = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private let cycles = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)

    init?(label: String, processes: [AudioObjectID]) {
        self.label = label
        peak.initialize(to: 0)
        cycles.initialize(to: 0)
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.name = "muteprobe monitor \(label)"
        description.muteBehavior = .unmuted
        description.isPrivate = true
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { print("[\(label)] 관찰 탭 생성 실패: \(status)"); return nil }
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "muteprobe \(label)",
            kAudioAggregateDeviceUIDKey: "muteprobe.\(label).\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: 1,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate)
        guard status == noErr else { print("[\(label)] 관찰 aggregate 생성 실패: \(status)"); return nil }
        let peak = peak, cycles = cycles
        status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, input, _, _, _ in
            var top: Float = 0
            for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
                guard let data = buffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                for i in 0..<Int(buffer.mDataByteSize) / MemoryLayout<Float>.size where abs(samples[i]) > top {
                    top = abs(samples[i])
                }
            }
            if top > peak[0] { peak[0] = top }
            cycles[0] += 1
        }
        guard status == noErr, let proc else { print("[\(label)] 관찰 IOProc 생성 실패: \(status)"); return nil }
        status = AudioDeviceStart(aggregate, proc)
        guard status == noErr else { print("[\(label)] 관찰 IO 시작 실패: \(status)"); return nil }
    }

    /// 마지막 읽기 이후의 피크(dBFS)와 IO 횟수. 읽으면 초기화된다.
    func read() -> (db: Float, cycles: UInt64) {
        let p = peak[0]; peak[0] = 0
        let c = cycles[0]; cycles[0] = 0
        return (p > 0 ? 20 * log10(p) : -160, c)
    }

    func stop() {
        if let proc { AudioDeviceStop(aggregate, proc); AudioDeviceDestroyIOProcID(aggregate, proc) }
        AudioHardwareDestroyAggregateDevice(aggregate)
        AudioHardwareDestroyProcessTap(tap)
    }
}

// MARK: - 음소거 (SystemAudioMuter와 같은 순서)

final class Muter {
    private var tap: AudioObjectID?
    private var aggregate: AudioObjectID?
    private var ioProc: AudioDeviceIOProcID?

    func mute() {
        guard tap == nil else { return }
        let description: CATapDescription
        switch tapTarget {
        case "renderer": description = CATapDescription(stereoMixdownOfProcesses: renderers.map(\.id))
        case "all": description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        default:
            description = renderers.isEmpty
                ? CATapDescription(stereoGlobalTapButExcludeProcesses: [])
                : CATapDescription(stereoMixdownOfProcesses: renderers.map(\.id))
        }
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        var tapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { print("탭 생성 실패: \(status)"); return }
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
        guard status == noErr else { print("aggregate 생성 실패: \(status)"); unmute(); return }
        aggregate = aggregateID
        var procID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, _, _, _, _ in }
        guard status == noErr, let procID else { print("IOProc 생성 실패: \(status)"); unmute(); return }
        ioProc = procID
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { print("IO 시작 실패: \(status)"); unmute(); return }
    }

    func unmute() {
        if let aggregate, let ioProc {
            AudioDeviceStop(aggregate, ioProc)
            AudioDeviceDestroyIOProcID(aggregate, ioProc)
        }
        if let aggregate { AudioHardwareDestroyAggregateDevice(aggregate) }
        if let tap { AudioHardwareDestroyProcessTap(tap) }
        ioProc = nil; aggregate = nil; tap = nil
    }
}

/// AudioCapture처럼 녹음마다 새 엔진으로 마이크를 열고 닫는다.
final class Mic {
    private let engine = AVAudioEngine()
    func start() throws {
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 4096, format: input.outputFormat(forBus: 0)) { _, _ in }
        engine.prepare()
        try engine.start()
    }
    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }
}

// MARK: - 실행

guard let source else { print("원본 앱 \(sourceBundle)이 오디오를 내고 있지 않음"); exit(2) }
guard let sourceMonitor = Monitor(label: "source", processes: [source.id]) else { exit(2) }
let rendererMonitor = renderers.isEmpty ? nil : Monitor(label: "renderer", processes: renderers.map(\.id))
let monitors = [sourceMonitor] + (rendererMonitor.map { [$0] } ?? [])
let muter = Muter()
let startedAt = Date()
var currentCycle = 0
var brokenStreak = 0

func sample(_ phase: String, for ms: Int, every: Int = 250) {
    let end = Date().addingTimeInterval(Double(ms) / 1000)
    while Date() < end {
        Thread.sleep(forTimeInterval: Double(every) / 1000)
        let readings = monitors.map { ($0.label, $0.read()) }
        let columns = readings.map { String(format: "%@ %7.1f dB (%3d io)", $0.0, $0.1.db, Int($0.1.cycles)) }
        print(String(format: "%6.2fs %-9@ %@", Date().timeIntervalSince(startedAt), phase, columns.joined(separator: "   ")))
        // 음소거가 풀린 뒤에도 원본 앱은 소리를 내는데 재생기가 무음이면 연결이 끊긴 것이다.
        guard phase != "muted", readings.count == 2 else { continue }
        if readings[0].1.db > -40, readings[1].1.db < -100 {
            brokenStreak += 1
            if brokenStreak >= 4 {
                print("BROKEN after cycle \(currentCycle): 원본 앱은 소리를 내는데 재생기가 1초 넘게 무음")
                monitors.forEach { $0.stop() }
                muter.unmute()
                exit(3)
            }
        } else {
            brokenStreak = 0
        }
    }
}

print("tap=\(tapTarget) mic=\(useMic) cycles=\(cycles) hold=\(holdMS)ms gap=\(gapMS)ms")
sample("baseline", for: baselineMS)
for i in stride(from: 1, through: cycles, by: 1) {
    currentCycle = i
    var mic: Mic?
    if useMic { mic = Mic(); try! mic!.start() }
    let muteStart = Date()
    muter.mute()
    print(String(format: "== cycle %d: mute() %.0f ms", i, Date().timeIntervalSince(muteStart) * 1000))
    sample("muted", for: holdMS, every: min(250, max(holdMS, 10)))
    mic?.stop()
    let unmuteStart = Date()
    muter.unmute()
    print(String(format: "== cycle %d: unmute() %.0f ms", i, Date().timeIntervalSince(unmuteStart) * 1000))
    sample("after", for: gapMS)
}
sample("settle", for: settleMS, every: 500)
monitors.forEach { $0.stop() }
print("done")
