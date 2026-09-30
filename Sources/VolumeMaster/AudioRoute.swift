import CoreAudio
import Foundation
import VolumeDSP

struct AudioFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@available(macOS 14.2, *)
final class AudioRoute {
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?
    private var dsp: OpaquePointer?
    private(set) var device: AudioObjectID = 0
    private(set) var sampleRate: Double = 0
    private(set) var name = "System output"
    var peak: Float { dsp.map(vm_peak) ?? 0 }
    var reduction: Float { dsp.map(vm_reduction) ?? 0 }
    var frames: UInt64 { dsp.map(vm_frames) ?? 0 }
    var faults: UInt32 { dsp.map(vm_faults) ?? 0 }

    deinit { stop() }

    func start(volume: Double, bass: Double, bands: [Double]) throws {
        stop()
        do {
            device = try Self.defaultOutput()
            let uid = try Self.string(device, kAudioDevicePropertyDeviceUID)
            name = try Self.string(device, kAudioObjectPropertyName)
            sampleRate = try Self.read(device, kAudioDevicePropertyNominalSampleRate, initial: Double(0))
            let outputStreams = try Self.streams(device, scope: kAudioObjectPropertyScopeOutput)
            guard let first = outputStreams.first else { throw AudioFailure(message: "No output is available. Connect speakers or headphones.") }
            let hardwareFormat = try Self.format(first)
            guard outputStreams.count == 1, (1...2).contains(hardwareFormat.mChannelsPerFrame) else {
                throw AudioFailure(message: "Choose a mono or stereo output in Sound settings. Multichannel outputs aren’t supported yet.")
            }

            var pid = getpid()
            var ownProcess: AudioObjectID = 0
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            var address = Self.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
            try Self.check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &ownProcess), "Find the app’s audio process")
            guard ownProcess != 0 else { throw AudioFailure(message: "The app’s audio process isn’t available. Reopen Volume Master.") }

            // Device-specific capture avoids global mixdown attenuation on multichannel systems.
            let description = CATapDescription(excludingProcesses: [ownProcess], deviceUID: uid, stream: 0)
            description.name = "Volume Master"
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            try Self.check(AudioHardwareCreateProcessTap(description, &tap), "Allow system audio access in Privacy & Security → Screen & System Audio Recording")
            let tapFormat = try Self.read(tap, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
            try Self.validate(tapFormat)
            guard tapFormat.mChannelsPerFrame == hardwareFormat.mChannelsPerFrame,
                  abs(tapFormat.mSampleRate - sampleRate) < 1 else {
                throw AudioFailure(message: "The output format changed. Try enabling audio again.")
            }
            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Volume Master · private",
                kAudioAggregateDeviceUIDKey: "com.figtracer.volumemaster.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceMainSubDeviceKey: uid,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                 kAudioSubTapDriftCompensationKey: true]],
                kAudioAggregateDeviceTapAutoStartKey: false
            ]
            try Self.check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate), "Connect the audio output")
            let inputs = try Self.streams(aggregate, scope: kAudioObjectPropertyScopeInput)
            let outputs = try Self.streams(aggregate, scope: kAudioObjectPropertyScopeOutput)
            let inputFormats = try inputs.map { try Self.format($0) }
            let outputFormats = try outputs.map { try Self.format($0) }
            let channels = tapFormat.mChannelsPerFrame
            let totalInputs = inputFormats.reduce(UInt32(0)) { $0 + $1.mChannelsPerFrame }
            guard totalInputs >= channels,
                  outputFormats.reduce(UInt32(0), { $0 + $1.mChannelsPerFrame }) == channels else {
                throw AudioFailure(message: "This audio device has an unsupported channel layout.")
            }
            let offset = totalInputs - channels
            var inputStarts: [UInt32] = []
            for stream in inputs {
                inputStarts.append(try Self.read(stream, kAudioStreamPropertyStartingChannel, initial: UInt32(0)))
            }
            for (index, format) in inputFormats.enumerated() where inputStarts[index] > offset { try Self.validate(format) }
            for format in outputFormats { try Self.validate(format) }
            guard let processor = vm_create(sampleRate) else { throw AudioFailure(message: "Choose a sample rate between 22.05 and 192 kHz in Audio MIDI Setup.") }
            dsp = processor
            vm_set_routing(processor, offset, channels)
            update(volume: volume, bass: bass, bands: bands)
            try Self.check(AudioDeviceCreateIOProcID(aggregate, vm_io, UnsafeMutableRawPointer(processor), &io), "Prepare audio processing")

            // An output device can also have microphones. Never enable its physical input streams.
            let usageSize = MemoryLayout<AudioHardwareIOProcStreamUsage>.size + max(0, inputs.count - 1) * MemoryLayout<UInt32>.size
            let usageStorage = UnsafeMutableRawPointer.allocate(byteCount: usageSize, alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment)
            defer { usageStorage.deallocate() }
            usageStorage.initializeMemory(as: UInt8.self, repeating: 0, count: usageSize)
            let usage = usageStorage.assumingMemoryBound(to: AudioHardwareIOProcStreamUsage.self)
            guard let io else { throw AudioFailure(message: "Core Audio did not create a processing callback.") }
            usage.pointee.mIOProc = unsafeBitCast(io, to: UnsafeMutableRawPointer.self)
            usage.pointee.mNumberStreams = UInt32(inputs.count)
            let flagsOffset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn)!
            let flags = usageStorage.advanced(by: flagsOffset).assumingMemoryBound(to: UInt32.self)
            for index in inputs.indices { flags[index] = inputStarts[index] > offset ? 1 : 0 }
            var usageAddress = Self.address(kAudioDevicePropertyIOProcStreamUsage, scope: kAudioObjectPropertyScopeInput)
            try Self.check(AudioObjectSetPropertyData(aggregate, &usageAddress, 0, nil, UInt32(usageSize), usage), "Select system audio input")
            try Self.check(AudioDeviceStart(aggregate, io), "Start audio processing")
        } catch {
            stop()
            throw error
        }
    }

    func update(volume: Double, bass: Double, bands: [Double]) {
        guard let dsp, bands.count == 5 else { return }
        let values = bands.map(Float.init)
        values.withUnsafeBufferPointer { vm_set_controls(dsp, Float(volume / 100), Float(bass), $0.baseAddress!) }
    }

    func stop() {
        if let io {
            AudioDeviceStop(aggregate, io)
            AudioDeviceDestroyIOProcID(aggregate, io)
        }
        io = nil
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
        if let dsp { vm_destroy(dsp) }
        dsp = nil
    }

    func routeChanged() -> Bool {
        guard let current = try? Self.defaultOutput(), current == device,
              let rate = try? Self.read(device, kAudioDevicePropertyNominalSampleRate, initial: Double(0)),
              let alive = try? Self.read(device, kAudioDevicePropertyDeviceIsAlive, initial: UInt32(0)) else { return true }
        return alive == 0 || abs(rate - sampleRate) > 0.5
    }

    static func defaultOutput() throws -> AudioObjectID {
        let result = try read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(0))
        guard result != 0 else { throw AudioFailure(message: "Connect an audio output, then try again.") }
        return result
    }

    static func outputName() -> String {
        (try? string(defaultOutput(), kAudioObjectPropertyName)) ?? "No output connected"
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func check(_ status: OSStatus, _ action: String) throws {
        guard status == noErr else { throw AudioFailure(message: "\(action). (Core Audio \(status))") }
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T) throws -> T {
        var result = initial
        var size = UInt32(MemoryLayout<T>.size)
        var property = address(selector)
        try withUnsafeMutablePointer(to: &result) { pointer in
            try check(AudioObjectGetPropertyData(object, &property, 0, nil, &size, pointer), "Read the audio device")
        }
        return result
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        try read(object, selector, initial: "" as CFString) as String
    }

    private static func streams(_ object: AudioObjectID, scope: AudioObjectPropertyScope) throws -> [AudioObjectID] {
        var property = address(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size), "Read audio streams")
        var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try result.withUnsafeMutableBytes { bytes in
            if size > 0 { try check(AudioObjectGetPropertyData(object, &property, 0, nil, &size, bytes.baseAddress!), "Read audio streams") }
        }
        return result
    }

    private static func format(_ stream: AudioObjectID) throws -> AudioStreamBasicDescription {
        try read(stream, kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription())
    }

    private static func validate(_ format: AudioStreamBasicDescription) throws {
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.mBitsPerChannel == 32 else {
            throw AudioFailure(message: "This output needs 32-bit floating-point audio. Choose another output in Sound settings.")
        }
    }
}
