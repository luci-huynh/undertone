import CoreAudio
import Foundation
import os

nonisolated enum LiveCaptureError: Error, Equatable, Sendable {
    /// Live needs macOS 26 (tap by bundle ID; SpeechAnalyzer at L03).
    case unsupportedOS
    /// The tap was refused — typically “System Audio Recording” not allowed.
    case tapRefused(OSStatus)
    case noOutputDevice
    case deviceFailed(OSStatus)
    case unsupportedFormat

    var message: String {
        switch self {
        case .unsupportedOS: "Live needs macOS 26 or later."
        case .tapRefused: "Audio capture was refused. Allow Undertone under System Settings → Privacy & Security → Screen & System Audio Recording (System Audio Recording Only)."
        case .noOutputDevice: "No audio output device is available."
        case .deviceFailed(let status): "Couldn't start audio capture (error \(status))."
        case .unsupportedFormat: "The meeting audio format isn't supported."
        }
    }
}

/// One block of captured audio, already mixed to mono.
nonisolated struct LiveAudioLevel: Sendable, Equatable {
    /// Root-mean-square amplitude of the block, 0…1.
    let rms: Float
}

/// Starts and stops capture of the given processes' output. No microphone,
/// no file, no playback: only the tapped processes' sound reaches `buffer`.
protocol LiveAudioCapturing: AnyObject {
    /// `onLevel` is called on the main actor at most about 10 times a second.
    func start(bundleIDs: [String], into sink: any LiveAudioSink, onLevel: @escaping @MainActor (LiveAudioLevel) -> Void) throws
    func stop()
}

/// Stand-in below macOS 26.
final class UnsupportedLiveCapture: LiveAudioCapturing {
    func start(bundleIDs: [String], into sink: any LiveAudioSink, onLevel: @escaping @MainActor (LiveAudioLevel) -> Void) throws {
        throw LiveCaptureError.unsupportedOS
    }

    func stop() {}
}

/// Core Audio process tap (L01 decision A): a private tap on the chosen
/// bundle IDs (restored when those processes restart), inside a private
/// aggregate device clocked by the default output device; an IO block mixes
/// the tap input to mono into the ring buffer. The aggregate device has no
/// input device, so the microphone is never part of it.
@available(macOS 26.0, *)
nonisolated final class CoreAudioTapCapture: LiveAudioCapturing, @unchecked Sendable {
    /// Core Audio waits for IO blocks on this queue (they are dispatched
    /// synchronously), so the block only mixes to mono and hands off.
    private let queue = DispatchQueue(label: "local.chienhuynh.Undertone.live-capture", qos: .userInteractive)
    /// Conversion, speech input, ring buffer and meter run here, off the IO path.
    private let processing = DispatchQueue(label: "local.chienhuynh.Undertone.live-processing", qos: .userInitiated)
    private let logger = Logger(subsystem: "local.chienhuynh.Undertone", category: "live")
    private let lock = NSLock()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    /// Diagnostics for the stop log: IO callbacks, callbacks without audio data, frames.
    private let counters = CaptureCounters()

    func start(bundleIDs: [String], into sink: any LiveAudioSink, onLevel: @escaping @MainActor (LiveAudioLevel) -> Void) throws {
        stop()
        let description = CATapDescription(__stereoMixdownOfProcesses: [])
        description.bundleIDs = bundleIDs
        description.isProcessRestoreEnabled = true
        description.isMono = true
        description.isPrivate = true
        description.muteBehavior = .unmuted
        description.name = "Undertone Live"

        var tap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        guard tapStatus == noErr, tap != kAudioObjectUnknown else { throw LiveCaptureError.tapRefused(tapStatus) }

        do {
            let format = try Self.property(tap, kAudioTapPropertyFormat, AudioStreamBasicDescription())
            guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32, format.mSampleRate > 0
            else { throw LiveCaptureError.unsupportedFormat }

            // The aggregate needs a clock sub-device. One with inputs (a headset)
            // would put its microphone stream into the IO buffers, so prefer an
            // output-only device; if none exists, skip its input streams (L08 review).
            guard let clock = ClockDeviceChooser.choose(from: CoreAudioDevices.outputCandidates()) else { throw LiveCaptureError.noOutputDevice }
            let outputUID = clock.uid
            if clock.inputStreams > 0 {
                logger.notice("Live clock device has \(clock.inputStreams, privacy: .public) input streams; they are skipped")
            }

            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Undertone Live",
                kAudioAggregateDeviceUIDKey: "local.chienhuynh.Undertone.live." + UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
            ]
            var aggregate = AudioObjectID(kAudioObjectUnknown)
            let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate)
            guard aggregateStatus == noErr else { throw LiveCaptureError.deviceFailed(aggregateStatus) }
            lock.withLock {
                tapID = tap
                aggregateID = aggregate
            }

            let sampleRate = format.mSampleRate
            let meter = LevelMeter(onLevel: onLevel)
            let counters = counters
            counters.reset()
            let skip = clock.inputStreams
            let processing = processing
            var proc: AudioDeviceIOProcID?
            let procStatus = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, queue) { _, input, _, _, _ in
                let mono = Self.tapMono(input, format: format, skippingStreams: skip)
                counters.record(frames: mono?.count ?? 0)
                guard let mono else { return }
                processing.async {
                    sink.append(mono, sampleRate: sampleRate)
                    meter.add(mono, sampleRate: sampleRate)
                }
            }
            guard procStatus == noErr, let proc else { throw LiveCaptureError.deviceFailed(procStatus) }
            lock.withLock { procID = proc }
            let startStatus = AudioDeviceStart(aggregate, proc)
            guard startStatus == noErr else { throw LiveCaptureError.deviceFailed(startStatus) }
            logger.notice("Live capture started: \(bundleIDs.count, privacy: .public) bundle IDs, \(Int(sampleRate), privacy: .public) Hz, \(format.mChannelsPerFrame, privacy: .public) ch")
        } catch {
            let (aggregate, proc) = lock.withLock { (aggregateID, procID) }
            if let proc, aggregate != kAudioObjectUnknown { AudioDeviceDestroyIOProcID(aggregate, proc) }
            teardown(tap: tap)
            throw error
        }
    }

    func stop() {
        let (tap, aggregate, proc) = lock.withLock { (tapID, aggregateID, procID) }
        guard tap != kAudioObjectUnknown || aggregate != kAudioObjectUnknown else { return }
        if let proc, aggregate != kAudioObjectUnknown {
            AudioDeviceStop(aggregate, proc)
            AudioDeviceDestroyIOProcID(aggregate, proc)
        }
        teardown(tap: tap)
        let (callbacks, empty, frames) = counters.values
        logger.notice("Live capture stopped: \(callbacks, privacy: .public) callbacks, \(empty, privacy: .public) without data, \(frames, privacy: .public) frames")
    }

    private func teardown(tap: AudioObjectID) {
        let aggregate = lock.withLock { aggregateID }
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        lock.withLock {
            tapID = AudioObjectID(kAudioObjectUnknown)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
            procID = nil
        }
    }

    /// The tap's audio mixed to mono. Only the tap's streams are read: the
    /// clock device's input streams (if any) come first and are skipped.
    static func tapMono(
        _ input: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription, skippingStreams skip: Int
    ) -> [Float]? {
        let all = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard all.count > skip else { return nil }
        let buffers = Array(all[skip...])
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        let channels = Int(max(1, format.mChannelsPerFrame))
        guard let first = buffers.first, let firstData = first.mData else { return nil }
        let frames = interleaved ? Int(first.mDataByteSize) / (4 * channels) : Int(first.mDataByteSize) / 4
        guard frames > 0 else { return nil }

        var mono = [Float](repeating: 0, count: frames)
        if interleaved {
            let samples = firstData.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels { sum += samples[frame * channels + channel] }
                mono[frame] = sum / Float(channels)
            }
        } else {
            let used = buffers.prefix(channels)
            for audioBuffer in used {
                guard let data = audioBuffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                for frame in 0..<min(frames, Int(audioBuffer.mDataByteSize) / 4) { mono[frame] += samples[frame] / Float(used.count) }
            }
        }
        return mono
    }

    private static func property<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) throws -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr else { throw LiveCaptureError.deviceFailed(status) }
        return value
    }

    private static func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        guard let value = CoreAudioProcessList.string(object, selector) else { throw LiveCaptureError.deviceFailed(kAudioHardwareUnknownPropertyError) }
        return value
    }
}

/// An output device that can clock the aggregate.
nonisolated struct ClockCandidate: Equatable, Sendable {
    let uid: String
    let inputStreams: Int
    /// Default (system) output first, then the rest.
    let isDefault: Bool
}

nonisolated enum ClockDeviceChooser {
    /// Output-only devices first (default one preferred), then the default
    /// even if it has inputs (their streams are skipped by `tapMono`).
    static func choose(from candidates: [ClockCandidate]) -> ClockCandidate? {
        let ordered = candidates.filter(\.isDefault) + candidates.filter { !$0.isDefault }
        return ordered.first { $0.inputStreams == 0 } ?? ordered.first
    }
}

/// Read-only Core Audio device queries for the clock choice.
nonisolated enum CoreAudioDevices {
    static func outputCandidates() -> [ClockCandidate] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let defaults = [kAudioHardwarePropertyDefaultSystemOutputDevice, kAudioHardwarePropertyDefaultOutputDevice].compactMap { selector -> AudioObjectID? in
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var id = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id) == noErr, id != kAudioObjectUnknown else { return nil }
            return id
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard streams(of: id, scope: kAudioObjectPropertyScopeOutput) > 0,
                  let uid = CoreAudioProcessList.string(id, kAudioDevicePropertyDeviceUID),
                  !uid.hasPrefix("local.chienhuynh.Undertone.live.")
            else { return nil }
            return ClockCandidate(uid: uid, inputStreams: streams(of: id, scope: kAudioObjectPropertyScopeInput), isDefault: defaults.contains(id))
        }
    }

    static func streams(of device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }
}

nonisolated final class CaptureCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var callbacks = 0
    private var empty = 0
    private var frames = 0

    var values: (Int, Int, Int) { lock.withLock { (callbacks, empty, frames) } }

    func reset() { lock.withLock { callbacks = 0; empty = 0; frames = 0 } }

    func record(frames count: Int) {
        lock.withLock {
            callbacks += 1
            if count == 0 { empty += 1 }
            frames += count
        }
    }
}

/// Aggregates blocks and reports an RMS level about every 100 ms.
nonisolated final class LevelMeter: @unchecked Sendable {
    private let onLevel: @MainActor (LiveAudioLevel) -> Void
    private var sumSquares: Double = 0
    private var samples = 0

    init(onLevel: @escaping @MainActor (LiveAudioLevel) -> Void) {
        self.onLevel = onLevel
    }

    /// Called on the capture queue only.
    func add(_ block: [Float], sampleRate: Double) {
        for sample in block { sumSquares += Double(sample * sample) }
        samples += block.count
        guard Double(samples) >= sampleRate / 10 else { return }
        let rms = Float((sumSquares / Double(samples)).squareRoot())
        sumSquares = 0
        samples = 0
        let onLevel = onLevel
        Task { @MainActor in onLevel(LiveAudioLevel(rms: min(rms, 1))) }
    }
}

/// Core Audio's process list: bundle ID and whether it is playing. Read-only.
nonisolated struct CoreAudioProcessList: LiveProcessListing {
    func audioProcesses() -> [LiveAudioProcess] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard let bundleID = Self.string(id, kAudioProcessPropertyBundleID), !bundleID.isEmpty else { return nil }
            var playingAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var playing: UInt32 = 0
            var playingSize = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(id, &playingAddress, 0, nil, &playingSize, &playing)
            return LiveAudioProcess(bundleID: bundleID, isPlaying: playing != 0)
        }
    }

    /// CFString properties are returned retained; the caller releases them.
    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
