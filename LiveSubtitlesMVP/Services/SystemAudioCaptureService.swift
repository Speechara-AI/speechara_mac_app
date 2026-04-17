import AppKit
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

enum SystemAudioCaptureError: LocalizedError {
    case alreadyCapturing
    case notCapturing
    case permissionRequested
    case permissionDenied
    case displayNotFound
    case failedToPrepareOutputDirectory(Error)
    case missingAudioFormat
    case unsupportedAudioFormat
    case failedToCreateAudioFile
    case failedToWriteAudioFile(OSStatus)
    case failedToCreateAudioBuffer
    case noAudioCaptured
    case startFailed(Error)
    case stopFailed(Error)
    case captureInterrupted(Error)

    var errorDescription: String? {
        switch self {
        case .alreadyCapturing:
            return "System audio capture is already running."
        case .notCapturing:
            return "System audio capture is not running."
        case .permissionRequested:
            return "Screen and system audio recording access was requested. Allow it in System Settings, then fully quit and reopen the app once."
        case .permissionDenied:
            return "Screen and system audio recording permission was not granted."
        case .displayNotFound:
            return "The app could not find a display to use for system audio capture."
        case .failedToPrepareOutputDirectory(let error):
            return "The app could not create the output folder for saved audio recordings: \(error.localizedDescription)"
        case .missingAudioFormat:
            return "The captured audio sample did not include a valid audio format."
        case .unsupportedAudioFormat:
            return "The captured audio format is not supported for file export."
        case .failedToCreateAudioFile:
            return "The app could not create the M4A file."
        case .failedToWriteAudioFile(let status):
            return "The app could not write the M4A file. OSStatus: \(status)"
        case .failedToCreateAudioBuffer:
            return "The app could not convert the captured audio into a writable PCM buffer."
        case .noAudioCaptured:
            return "The capture session stopped before any system audio samples were received."
        case .startFailed(let error):
            return "System audio capture failed to start: \(error.localizedDescription)"
        case .stopFailed(let error):
            return "System audio capture failed to stop cleanly: \(error.localizedDescription)"
        case .captureInterrupted(let error):
            return "System audio capture was interrupted: \(error.localizedDescription)"
        }
    }
}

final class SystemAudioCaptureService: NSObject, SCStreamDelegate, SCStreamOutput {
    private let audioQueue = DispatchQueue(label: "LiveSubtitlesMVP.SystemAudioCapture")
    private let screenQueue = DispatchQueue(label: "LiveSubtitlesMVP.SystemAudioCapture.ScreenDrain")

    private var stream: SCStream?
    private var liveAudioDataHandler: (@Sendable (Data) -> Void)?
    private var liveAudioEncoder: AudioChunkEncoder?
    private var captureError: Error?
    private var receivedAudioBuffers = 0

    func setLiveAudioDataHandler(_ handler: (@Sendable (Data) -> Void)?) {
        audioQueue.sync {
            liveAudioDataHandler = handler
        }
    }

    @MainActor
    func startCapture(recordAudio: Bool) async throws {
        _ = recordAudio

        guard stream == nil else {
            throw SystemAudioCaptureError.alreadyCapturing
        }

        let shareableContent: SCShareableContent

        do {
            shareableContent = try await SCShareableContent.current
        } catch {
            if CGPreflightScreenCaptureAccess() {
                throw SystemAudioCaptureError.startFailed(error)
            }

            _ = CGRequestScreenCaptureAccess()
            throw SystemAudioCaptureError.permissionRequested
        }

        guard let display = preferredDisplay(from: shareableContent) else {
            throw SystemAudioCaptureError.displayNotFound
        }

        let contentFilter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications(from: shareableContent),
            exceptingWindows: []
        )

        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.capturesAudio = true
        streamConfiguration.excludesCurrentProcessAudio = true
        streamConfiguration.sampleRate = 48_000
        streamConfiguration.channelCount = 2
        streamConfiguration.queueDepth = 3
        // ScreenCaptureKit does not expose a "video off" flag for display streams.
        // We attach a no-op screen output to silence internal "stream output NOT found"
        // errors and throttle screen delivery to the bare minimum because we only use audio.
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        streamConfiguration.showsCursor = false

        let stream = SCStream(filter: contentFilter, configuration: streamConfiguration, delegate: self)

        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: screenQueue)
        } catch {
            throw SystemAudioCaptureError.startFailed(error)
        }

        audioQueue.sync {
            liveAudioEncoder = AudioChunkEncoder()
            captureError = nil
            receivedAudioBuffers = 0
        }

        self.stream = stream

        do {
            try await stream.startCapture()
        } catch {
            cleanupCaptureState()
            throw SystemAudioCaptureError.startFailed(error)
        }
    }

    @MainActor
    func stopCapture() async throws -> URL? {
        guard let stream else {
            throw SystemAudioCaptureError.notCapturing
        }

        do {
            try await stream.stopCapture()
        } catch {
            cleanupCaptureState()
            throw SystemAudioCaptureError.stopFailed(error)
        }

        do {
            try audioQueue.sync {
                defer {
                    captureError = nil
                    receivedAudioBuffers = 0
                }

                if let captureError {
                    throw captureError
                }

            }
        } catch {
            self.stream = nil
            throw error
        }

        self.stream = nil
        return nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        switch type {
        case .audio:
            guard captureError == nil else {
                return
            }

            do {
                if let encodedAudio = try liveAudioEncoder?.encode(sampleBuffer: sampleBuffer), !encodedAudio.isEmpty {
                    liveAudioDataHandler?(encodedAudio)
                }
                receivedAudioBuffers += 1
            } catch {
                captureError = error
                return
            }

        case .screen:
            // Drain display frames so ScreenCaptureKit doesn't spam the console
            // when we're intentionally using the stream only for system audio.
            return

        default:
            return
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        audioQueue.async { [weak self] in
            self?.captureError = SystemAudioCaptureError.captureInterrupted(error)
        }
    }

    @MainActor
    private func preferredDisplay(from shareableContent: SCShareableContent) -> SCDisplay? {
        if let screenNumber = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let mainDisplayID = CGDirectDisplayID(screenNumber.uint32Value)

            if let matchingDisplay = shareableContent.displays.first(where: { $0.displayID == mainDisplayID }) {
                return matchingDisplay
            }
        }

        return shareableContent.displays.first
    }

    private func excludedApplications(from shareableContent: SCShareableContent) -> [SCRunningApplication] {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return []
        }

        return shareableContent.applications.filter { $0.bundleIdentifier == bundleIdentifier }
    }

    @MainActor
    private func cleanupCaptureState() {
        audioQueue.sync {
            liveAudioEncoder = nil
            captureError = nil
            receivedAudioBuffers = 0
        }

        stream = nil
    }
}
