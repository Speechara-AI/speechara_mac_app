@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

struct MicrophoneInputDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

enum MicrophoneCaptureError: LocalizedError {
    case alreadyCapturing
    case permissionDenied
    case inputUnavailable
    case selectedDeviceUnavailable
    case startFailed(Error)

    var errorDescription: String? {
        switch self {
        case .alreadyCapturing:
            return "Microphone capture is already running."
        case .permissionDenied:
            return "Microphone permission was not granted."
        case .inputUnavailable:
            return "The app could not access the selected microphone input."
        case .selectedDeviceUnavailable:
            return "The selected microphone is not available."
        case .startFailed(let error):
            return "Microphone capture failed to start: \(error.localizedDescription)"
        }
    }
}

final class MicrophoneCaptureService: @unchecked Sendable {
    private static let inputBusNumber: UInt32 = 1
    private static let gateOpenThreshold = 0.025
    private static let gateHoldChunks = 10

    private let captureQueue = DispatchQueue(label: "Speechara.MicrophoneCapture")

    private var audioUnit: AudioUnit?
    private var captureFormat: AVAudioFormat?
    private var liveAudioDataHandler: (@Sendable (Data) -> Void)?
    private var errorHandler: (@Sendable (String) -> Void)?
    private var levelHandler: (@Sendable (Double) -> Void)?
    private var encoder = AudioChunkEncoder()
    private var microphoneGateChunksRemaining = 0

    static func availableDevices() -> [MicrophoneInputDevice] {
        allInputDevices().map { device in
            MicrophoneInputDevice(id: device.uid, name: device.name)
        }
    }

    static func defaultDeviceID() -> String? {
        guard let deviceID = try? defaultInputDeviceID() else {
            return availableDevices().first?.id
        }

        return (try? deviceUID(for: deviceID)) ?? availableDevices().first?.id
    }

    func setLiveAudioDataHandler(_ handler: (@Sendable (Data) -> Void)?) {
        captureQueue.sync {
            liveAudioDataHandler = handler
        }
    }

    func setErrorHandler(_ handler: (@Sendable (String) -> Void)?) {
        captureQueue.sync {
            errorHandler = handler
        }
    }

    func setLevelHandler(_ handler: (@Sendable (Double) -> Void)?) {
        captureQueue.sync {
            levelHandler = handler
        }
    }

    @MainActor
    func startCapture(deviceID: String?) async throws {
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch authorizationStatus {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                throw MicrophoneCaptureError.permissionDenied
            }
        case .denied, .restricted:
            throw MicrophoneCaptureError.permissionDenied
        @unknown default:
            throw MicrophoneCaptureError.permissionDenied
        }

        let selectedAudioDeviceID = try Self.resolveAudioDeviceID(for: deviceID)

        try captureQueue.sync {
            guard audioUnit == nil else {
                throw MicrophoneCaptureError.alreadyCapturing
            }

            encoder = AudioChunkEncoder()
            microphoneGateChunksRemaining = 0
            levelHandler?(0)

            do {
                let (audioUnit, captureFormat) = try Self.makeAudioUnit(
                    deviceID: selectedAudioDeviceID,
                    refCon: Unmanaged.passUnretained(self).toOpaque()
                )

                self.audioUnit = audioUnit
                self.captureFormat = captureFormat

                let startStatus = AudioOutputUnitStart(audioUnit)
                guard startStatus == noErr else {
                    throw Self.makeOSStatusError(startStatus, description: "The selected microphone could not start.")
                }
            } catch {
                teardownAudioUnit()
                throw MicrophoneCaptureError.startFailed(error)
            }
        }
    }

    @MainActor
    func stopCapture() {
        captureQueue.sync {
            teardownAudioUnit()
            levelHandler?(0)
        }
    }

    private func handleInput(
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        inTimeStamp: UnsafePointer<AudioTimeStamp>,
        inBusNumber _: UInt32,
        inNumberFrames: UInt32
    ) -> OSStatus {
        guard let audioUnit, let captureFormat else {
            return noErr
        }

        let bytesPerFrame = captureFormat.streamDescription.pointee.mBytesPerFrame
        let bytesPerBuffer = Int(inNumberFrames * bytesPerFrame)
        let rawAudioData = UnsafeMutableRawPointer.allocate(
            byteCount: bytesPerBuffer,
            alignment: MemoryLayout<Int16>.alignment
        )
        defer {
            rawAudioData.deallocate()
        }

        var audioBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: captureFormat.channelCount,
                mDataByteSize: UInt32(bytesPerBuffer),
                mData: rawAudioData
            )
        )

        let status = AudioUnitRender(
            audioUnit,
            ioActionFlags,
            inTimeStamp,
            Self.inputBusNumber,
            inNumberFrames,
            &audioBufferList
        )

        guard status == noErr else {
            reportError(Self.makeOSStatusError(status, description: "Microphone capture failed.").localizedDescription)
            return status
        }

        let level = Self.microphoneLevel(
            fromRawInt16Data: rawAudioData,
            sampleCount: Int(inNumberFrames * captureFormat.channelCount)
        )

        guard shouldStreamMicrophoneAudio(level: level) else {
            captureQueue.async { [weak self] in
                self?.levelHandler?(level)
            }
            return noErr
        }

        let pcmData = Data(bytes: rawAudioData, count: bytesPerBuffer)
        captureQueue.async { [weak self] in
            self?.levelHandler?(level)
            self?.processCapturedPCMData(pcmData, frameCount: inNumberFrames)
        }

        return noErr
    }

    private func processCapturedPCMData(_ pcmData: Data, frameCount: UInt32) {
        guard let captureFormat, audioUnit != nil else {
            return
        }

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: captureFormat,
            frameCapacity: frameCount
        ) else {
            reportError("The app could not allocate a microphone buffer.")
            return
        }

        pcmBuffer.frameLength = frameCount
        let destinationBufferList = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
        guard let destination = destinationBufferList.first?.mData else {
            reportError("The app could not copy microphone audio into the buffer.")
            return
        }

        pcmData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            memcpy(destination, baseAddress, pcmData.count)
        }

        do {
            let encodedAudio = try encoder.encode(pcmBuffer: pcmBuffer)
            guard !encodedAudio.isEmpty else {
                return
            }

            liveAudioDataHandler?(encodedAudio)
        } catch {
            reportError(error.localizedDescription)
        }
    }

    private func reportError(_ message: String) {
        errorHandler?(message)
    }

    private func teardownAudioUnit() {
        if let audioUnit {
            AudioOutputUnitStop(audioUnit)
            AudioUnitUninitialize(audioUnit)
            AudioComponentInstanceDispose(audioUnit)
        }

        audioUnit = nil
        captureFormat = nil
        microphoneGateChunksRemaining = 0
    }

    private func shouldStreamMicrophoneAudio(level: Double) -> Bool {
        if level >= Self.gateOpenThreshold {
            microphoneGateChunksRemaining = Self.gateHoldChunks
            return true
        }

        if microphoneGateChunksRemaining > 0 {
            microphoneGateChunksRemaining -= 1
            return true
        }

        return false
    }

    private static let inputCallback: AURenderCallback = { inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, _ in
        let service = Unmanaged<MicrophoneCaptureService>.fromOpaque(inRefCon).takeUnretainedValue()
        return service.handleInput(
            ioActionFlags: ioActionFlags,
            inTimeStamp: inTimeStamp,
            inBusNumber: inBusNumber,
            inNumberFrames: inNumberFrames
        )
    }

    private static func makeAudioUnit(
        deviceID: AudioDeviceID,
        refCon: UnsafeMutableRawPointer
    ) throws -> (AudioUnit, AVAudioFormat) {
        var componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &componentDescription) else {
            throw MicrophoneCaptureError.inputUnavailable
        }

        var maybeAudioUnit: AudioUnit?
        var status = AudioComponentInstanceNew(component, &maybeAudioUnit)
        guard status == noErr, let audioUnit = maybeAudioUnit else {
            throw makeOSStatusError(status, description: "The app could not create the microphone audio unit.")
        }

        do {
            var enableInput: UInt32 = 1
            status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Input,
                Self.inputBusNumber,
                &enableInput,
                UInt32(MemoryLayout<UInt32>.size)
            )
            guard status == noErr else {
                throw makeOSStatusError(status, description: "The app could not enable microphone input.")
            }

            var disableOutput: UInt32 = 0
            status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output,
                0,
                &disableOutput,
                UInt32(MemoryLayout<UInt32>.size)
            )
            guard status == noErr else {
                throw makeOSStatusError(status, description: "The app could not disable speaker output on the microphone unit.")
            }

            var mutableDeviceID = deviceID
            status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &mutableDeviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else {
                throw makeOSStatusError(status, description: "The app could not switch to the selected microphone.")
            }

            var deviceFormat = AudioStreamBasicDescription()
            var deviceFormatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            status = AudioUnitGetProperty(
                audioUnit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Input,
                Self.inputBusNumber,
                &deviceFormat,
                &deviceFormatSize
            )
            guard status == noErr else {
                throw makeOSStatusError(status, description: "The app could not read the selected microphone format.")
            }

            guard let captureFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: deviceFormat.mSampleRate,
                channels: max(1, deviceFormat.mChannelsPerFrame),
                interleaved: true
            ) else {
                throw MicrophoneCaptureError.inputUnavailable
            }

            var desiredFormat = captureFormat.streamDescription.pointee
            status = AudioUnitSetProperty(
                audioUnit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output,
                Self.inputBusNumber,
                &desiredFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            )
            guard status == noErr else {
                throw makeOSStatusError(status, description: "The app could not configure the selected microphone format.")
            }

            var callback = AURenderCallbackStruct(
                inputProc: inputCallback,
                inputProcRefCon: refCon
            )
            status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_SetInputCallback,
                kAudioUnitScope_Global,
                0,
                &callback,
                UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            )
            guard status == noErr else {
                throw makeOSStatusError(status, description: "The app could not register the microphone callback.")
            }

            status = AudioUnitInitialize(audioUnit)
            guard status == noErr else {
                throw makeOSStatusError(status, description: "The app could not initialize the selected microphone.")
            }

            return (audioUnit, captureFormat)
        } catch {
            AudioUnitUninitialize(audioUnit)
            AudioComponentInstanceDispose(audioUnit)
            throw error
        }
    }

    private static func allInputDevices() -> [(id: AudioDeviceID, uid: String, name: String)] {
        let deviceIDs = (try? enumerateAudioDeviceIDs()) ?? []

        return deviceIDs.compactMap { deviceID in
            guard hasInputChannels(deviceID),
                  let uid = try? deviceUID(for: deviceID),
                  let name = try? deviceName(for: deviceID) else {
                return nil
            }

            return (deviceID, uid, name)
        }
        .sorted { left, right in
            left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    private static func resolveAudioDeviceID(for deviceID: String?) throws -> AudioDeviceID {
        let allDevices = allInputDevices()

        if let deviceID,
           let matchingDevice = allDevices.first(where: { $0.uid == deviceID }) {
            return matchingDevice.id
        }

        if let defaultDevice = try? defaultInputDeviceID() {
            return defaultDevice
        }

        guard let firstDevice = allDevices.first else {
            throw MicrophoneCaptureError.selectedDeviceUnavailable
        }

        return firstDevice.id
    }

    private static func enumerateAudioDeviceIDs() throws -> [AudioDeviceID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else {
            throw makeOSStatusError(status, description: "The app could not list audio devices.")
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else {
            throw makeOSStatusError(status, description: "The app could not load audio devices.")
        }

        return deviceIDs
    }

    private static func defaultInputDeviceID() throws -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceID = AudioDeviceID(0)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr else {
            throw makeOSStatusError(status, description: "The app could not read the default microphone.")
        }

        return deviceID
    }

    private static func deviceUID(for deviceID: AudioDeviceID) throws -> String {
        try getStringProperty(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    private static func deviceName(for deviceID: AudioDeviceID) throws -> String {
        try getStringProperty(
            objectID: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else {
            return false
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            bufferListPointer.deallocate()
        }

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            bufferListPointer
        )
        guard status == noErr else {
            return false
        }

        let audioBufferList = bufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func getStringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var unmanagedString: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &unmanagedString
        )

        guard status == noErr else {
            throw makeOSStatusError(status, description: "The app could not read an audio device property.")
        }

        guard let unmanagedString else {
            return ""
        }

        return unmanagedString.takeUnretainedValue() as String
    }

    private static func microphoneLevel(fromRawInt16Data rawAudioData: UnsafeMutableRawPointer, sampleCount: Int) -> Double {
        guard sampleCount > 0 else {
            return 0
        }

        let int16Pointer = rawAudioData.bindMemory(to: Int16.self, capacity: sampleCount)
        return normalizedLevel(fromInt16Pointer: int16Pointer, frameLength: sampleCount)
    }

    private static func normalizedLevel(fromInt16Pointer pointer: UnsafePointer<Int16>, frameLength: Int) -> Double {
        var sumSquares = 0.0

        for index in 0 ..< frameLength {
            let normalized = Double(pointer[index]) / Double(Int16.max)
            sumSquares += normalized * normalized
        }

        return makeNormalizedLevel(meanSquare: sumSquares / Double(frameLength))
    }
    private static func makeNormalizedLevel(meanSquare: Double) -> Double {
        guard meanSquare > 0 else {
            return 0
        }

        let rms = sqrt(meanSquare)
        let decibels = 20 * log10(max(rms, 0.000_01))
        let normalizedLevel = (decibels + 60) / 60
        return max(0, min(1, normalizedLevel))
    }

    private static func makeOSStatusError(_ status: OSStatus, description: String) -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: "\(description) OSStatus: \(status)"]
        )
    }
}
