import AudioToolbox
import AVFAudio
import CoreAudio
import Foundation

enum SystemAudioCaptureError: LocalizedError {
    case alreadyCapturing
    case notCapturing
    case unsupportedSystemAudioTap
    case failedToCreateProcessTap(OSStatus)
    case failedToCreateAggregateDevice(OSStatus)
    case failedToCreateIOProc(OSStatus)
    case failedToStartDevice(OSStatus)
    case failedToStopDevice(OSStatus)
    case failedToDestroyIOProc(OSStatus)
    case failedToDestroyAggregateDevice(OSStatus)
    case failedToDestroyProcessTap(OSStatus)
    case failedToReadTapFormat(OSStatus)
    case failedToReadTapUID(OSStatus)
    case failedToPrepareOutputDirectory(Error)
    case failedToCreateAudioFile
    case failedToWriteAudioFile(OSStatus)
    case failedToCreateAudioBuffer
    case missingAudioFormat
    case unsupportedAudioFormat
    case captureInterrupted(Error)

    var errorDescription: String? {
        switch self {
        case .alreadyCapturing:
            return "System audio capture is already running."
        case .notCapturing:
            return "System audio capture is not running."
        case .unsupportedSystemAudioTap:
            return "Audio-only system capture requires macOS 14.2 or newer."
        case .failedToCreateProcessTap(let status):
            return "The app could not create an audio-only system tap. OSStatus: \(status)"
        case .failedToCreateAggregateDevice(let status):
            return "The app could not create a private system audio device. OSStatus: \(status)"
        case .failedToCreateIOProc(let status):
            return "The app could not attach to the system audio stream. OSStatus: \(status)"
        case .failedToStartDevice(let status):
            return "The app could not start system audio capture. OSStatus: \(status)"
        case .failedToStopDevice(let status):
            return "The app could not stop system audio capture cleanly. OSStatus: \(status)"
        case .failedToDestroyIOProc(let status):
            return "The app could not detach from the system audio stream. OSStatus: \(status)"
        case .failedToDestroyAggregateDevice(let status):
            return "The app could not remove the private system audio device. OSStatus: \(status)"
        case .failedToDestroyProcessTap(let status):
            return "The app could not remove the system audio tap. OSStatus: \(status)"
        case .failedToReadTapFormat(let status):
            return "The app could not read the system audio format. OSStatus: \(status)"
        case .failedToReadTapUID(let status):
            return "The app could not read the system audio tap identifier. OSStatus: \(status)"
        case .failedToPrepareOutputDirectory(let error):
            return "The app could not create the output folder for saved audio recordings: \(error.localizedDescription)"
        case .failedToCreateAudioFile:
            return "The app could not create the M4A file."
        case .failedToWriteAudioFile(let status):
            return "The app could not write the M4A file. OSStatus: \(status)"
        case .failedToCreateAudioBuffer:
            return "The app could not convert the captured system audio into a PCM buffer."
        case .missingAudioFormat:
            return "The captured system audio did not include a valid format."
        case .unsupportedAudioFormat:
            return "The captured system audio format is not supported."
        case .captureInterrupted(let error):
            return "System audio capture was interrupted: \(error.localizedDescription)"
        }
    }
}

final class SystemAudioCaptureService: @unchecked Sendable {
    private let processingQueue = DispatchQueue(label: "Speechara.SystemAudioCapture.Processing")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var tapFormat: AVAudioFormat?
    private var streamBytesPerFrame: UInt32 = 0
    private var liveAudioDataHandler: (@Sendable (Data) -> Void)?
    private var liveAudioEncoder = AudioChunkEncoder()
    private var captureError: Error?
    private var isProcessingAudio = false

    func setLiveAudioDataHandler(_ handler: (@Sendable (Data) -> Void)?) {
        processingQueue.sync {
            liveAudioDataHandler = handler
        }
    }

    func startCapture(recordAudio: Bool) async throws {
        try await Task.detached(priority: .userInitiated) { [self] in
            try startCaptureSynchronously(recordAudio: recordAudio)
        }.value
    }

    private func startCaptureSynchronously(recordAudio: Bool) throws {
        _ = recordAudio

        guard tapID == kAudioObjectUnknown, aggregateDeviceID == kAudioObjectUnknown else {
            throw SystemAudioCaptureError.alreadyCapturing
        }

        guard #available(macOS 14.2, *) else {
            throw SystemAudioCaptureError.unsupportedSystemAudioTap
        }

        do {
            let processObjectIDs = (try? Self.currentProcessObjectID()).map { [$0] } ?? []
            let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: processObjectIDs)
            tapDescription.name = "Speechara System Audio"
            tapDescription.uuid = UUID()
            tapDescription.isPrivate = true
            tapDescription.muteBehavior = CATapMuteBehavior.unmuted

            var newTapID = AudioObjectID(kAudioObjectUnknown)
            var status = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
            guard status == noErr else {
                throw SystemAudioCaptureError.failedToCreateProcessTap(status)
            }
            tapID = newTapID

            var streamDescription = try Self.tapStreamDescription(for: newTapID)
            guard streamDescription.mBytesPerFrame > 0 else {
                throw SystemAudioCaptureError.unsupportedAudioFormat
            }

            guard let audioFormat = AVAudioFormat(streamDescription: &streamDescription) else {
                throw SystemAudioCaptureError.unsupportedAudioFormat
            }

            let tapUID = try Self.tapUID(for: newTapID)
            let aggregateUID = "com.speechara.system-audio.\(UUID().uuidString)"
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Speechara System Audio",
                kAudioAggregateDeviceUIDKey: aggregateUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: false,
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapUIDKey: tapUID,
                        kAudioSubTapDriftCompensationKey: true,
                    ],
                ],
            ]

            var newAggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
            status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateDeviceID)
            guard status == noErr else {
                throw SystemAudioCaptureError.failedToCreateAggregateDevice(status)
            }
            aggregateDeviceID = newAggregateDeviceID

            processingQueue.sync {
                tapFormat = audioFormat
                streamBytesPerFrame = streamDescription.mBytesPerFrame
                liveAudioEncoder = AudioChunkEncoder()
                captureError = nil
                isProcessingAudio = true
            }

            var newIOProcID: AudioDeviceIOProcID?
            let ioBlock: AudioDeviceIOBlock = { [weak self] _, inputData, _, _, _ in
                self?.copyAndProcessInputData(inputData)
            }
            status = AudioDeviceCreateIOProcIDWithBlock(&newIOProcID, newAggregateDeviceID, nil, ioBlock)
            guard status == noErr, let newIOProcID else {
                throw SystemAudioCaptureError.failedToCreateIOProc(status)
            }
            ioProcID = newIOProcID

            status = AudioDeviceStart(newAggregateDeviceID, newIOProcID)
            guard status == noErr else {
                throw SystemAudioCaptureError.failedToStartDevice(status)
            }
        } catch {
            try? stopCaptureIfNeeded()
            throw error
        }
    }

    func stopCapture() async throws -> URL? {
        try await Task.detached(priority: .userInitiated) { [self] in
            guard tapID != kAudioObjectUnknown || aggregateDeviceID != kAudioObjectUnknown else {
                throw SystemAudioCaptureError.notCapturing
            }

            try stopCaptureIfNeeded()
        }.value
        return nil
    }

    private func copyAndProcessInputData(_ inputData: UnsafePointer<AudioBufferList>) {
        let bytesPerFrame = streamBytesPerFrame
        guard bytesPerFrame > 0 else {
            return
        }

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard let firstBuffer = sourceBuffers.first,
              firstBuffer.mDataByteSize > 0 else {
            return
        }

        let frameCount = AVAudioFrameCount(firstBuffer.mDataByteSize / bytesPerFrame)
        guard frameCount > 0 else {
            return
        }

        let buffers = sourceBuffers.compactMap { sourceBuffer -> CapturedAudioBuffer? in
            guard let sourceData = sourceBuffer.mData, sourceBuffer.mDataByteSize > 0 else {
                return nil
            }

            return CapturedAudioBuffer(
                data: Data(bytes: sourceData, count: Int(sourceBuffer.mDataByteSize)),
                channelCount: sourceBuffer.mNumberChannels
            )
        }

        guard !buffers.isEmpty else {
            return
        }

        let chunk = CapturedAudioChunk(buffers: buffers, frameCount: frameCount)
        processingQueue.async { [weak self] in
            self?.processCapturedChunk(chunk)
        }
    }

    private func processCapturedChunk(_ chunk: CapturedAudioChunk) {
        guard isProcessingAudio, let tapFormat else {
            return
        }

        do {
            let pcmBuffer = try Self.makePCMBuffer(from: chunk, format: tapFormat)
            let encodedAudio = try liveAudioEncoder.encode(pcmBuffer: pcmBuffer)
            guard !encodedAudio.isEmpty else {
                return
            }

            liveAudioDataHandler?(encodedAudio)
        } catch {
            captureError = error
        }
    }

    private func stopCaptureIfNeeded() throws {
        var stopError: Error?

        processingQueue.sync {
            isProcessingAudio = false
            tapFormat = nil
            streamBytesPerFrame = 0
            liveAudioEncoder = AudioChunkEncoder()
            if let captureError {
                stopError = captureError
            }
            captureError = nil
        }

        if let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            let stopStatus = AudioDeviceStop(aggregateDeviceID, ioProcID)
            if stopStatus != noErr, stopStatus != kAudioHardwareNotRunningError, stopError == nil {
                stopError = SystemAudioCaptureError.failedToStopDevice(stopStatus)
            }

            let destroyStatus = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            if destroyStatus != noErr, stopError == nil {
                stopError = SystemAudioCaptureError.failedToDestroyIOProc(destroyStatus)
            }
        }
        ioProcID = nil

        if aggregateDeviceID != kAudioObjectUnknown {
            let destroyStatus = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if destroyStatus != noErr, stopError == nil {
                stopError = SystemAudioCaptureError.failedToDestroyAggregateDevice(destroyStatus)
            }
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }

        if #available(macOS 14.2, *), tapID != kAudioObjectUnknown {
            let destroyStatus = AudioHardwareDestroyProcessTap(tapID)
            if destroyStatus != noErr, stopError == nil {
                stopError = SystemAudioCaptureError.failedToDestroyProcessTap(destroyStatus)
            }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }

        if let stopError {
            throw stopError
        }
    }

    private static func makePCMBuffer(from chunk: CapturedAudioChunk, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk.frameCount) else {
            throw SystemAudioCaptureError.failedToCreateAudioBuffer
        }

        pcmBuffer.frameLength = chunk.frameCount
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
        guard destinationBuffers.count == chunk.buffers.count else {
            throw SystemAudioCaptureError.unsupportedAudioFormat
        }

        for index in destinationBuffers.indices {
            guard let destination = destinationBuffers[index].mData else {
                throw SystemAudioCaptureError.failedToCreateAudioBuffer
            }

            let sourceData = chunk.buffers[index].data
            let byteCount = min(Int(destinationBuffers[index].mDataByteSize), sourceData.count)
            sourceData.withUnsafeBytes { rawBuffer in
                if let source = rawBuffer.baseAddress {
                    memcpy(destination, source, byteCount)
                }
            }
            destinationBuffers[index].mDataByteSize = UInt32(byteCount)
            destinationBuffers[index].mNumberChannels = chunk.buffers[index].channelCount
        }

        return pcmBuffer
    }

    private static func currentProcessObjectID() throws -> AudioObjectID {
        var processID = pid_t(ProcessInfo.processInfo.processIdentifier)
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let qualifierSize = UInt32(MemoryLayout<pid_t>.size)
        let status = withUnsafePointer(to: &processID) { processIDPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                qualifierSize,
                processIDPointer,
                &dataSize,
                &processObjectID
            )
        }

        guard status == noErr, processObjectID != kAudioObjectUnknown else {
            throw SystemAudioCaptureError.failedToCreateProcessTap(status)
        }

        return processObjectID
    }

    private static func tapUID(for tapID: AudioObjectID) throws -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedString: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            tapID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &unmanagedString
        )

        guard status == noErr, let unmanagedString else {
            throw SystemAudioCaptureError.failedToReadTapUID(status)
        }

        return unmanagedString.takeUnretainedValue() as String
    }

    private static func tapStreamDescription(for tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamDescription = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(
            tapID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &streamDescription
        )

        guard status == noErr else {
            throw SystemAudioCaptureError.failedToReadTapFormat(status)
        }

        return streamDescription
    }
}

private struct CapturedAudioChunk {
    let buffers: [CapturedAudioBuffer]
    let frameCount: AVAudioFrameCount
}

private struct CapturedAudioBuffer {
    let data: Data
    let channelCount: UInt32
}
