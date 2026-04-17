import Foundation

actor LocalAudioRecordingService {
    private var writer: M4AAudioFileWriter?
    private var outputURL: URL?
    private var recordingError: Error?

    func startRecording(isEnabled: Bool) throws {
        writer?.finish()
        writer = nil
        outputURL = nil
        recordingError = nil

        guard isEnabled else {
            return
        }

        let outputURL = try Self.makeOutputURL()
        writer = M4AAudioFileWriter(outputURL: outputURL)
        self.outputURL = outputURL
    }

    func appendMixedAudio(_ audioData: Data) {
        guard let writer, recordingError == nil else {
            return
        }

        do {
            try writer.append(pcmData: audioData)
        } catch {
            recordingError = error
            writer.finish()
            self.writer = nil

            if let outputURL {
                try? FileManager.default.removeItem(at: outputURL)
                self.outputURL = nil
            }
        }
    }

    func finishRecording() throws -> URL? {
        defer {
            writer?.finish()
            writer = nil
            outputURL = nil
            recordingError = nil
        }

        if let recordingError {
            throw recordingError
        }

        return outputURL
    }

    func cancel() {
        writer?.finish()
        writer = nil

        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }

        outputURL = nil
        recordingError = nil
    }

    private static func makeOutputURL() throws -> URL {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser

        let outputDirectory = baseDirectory.appendingPathComponent("Speechara", isDirectory: true)

        do {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            throw SystemAudioCaptureError.failedToPrepareOutputDirectory(error)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        let fileName = "CapturedAudio-\(formatter.string(from: Date())).m4a"
        return outputDirectory.appendingPathComponent(fileName)
    }
}
