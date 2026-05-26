import AVFAudio
import CoreMedia
import Foundation

final class AudioChunkEncoder {
    static let targetSampleRate = 16_000
    static let targetChannelCount: AVAudioChannelCount = 1

    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var sourceFormatSignature: AudioFormatSignature?

    init() {
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(Self.targetSampleRate),
            channels: Self.targetChannelCount,
            interleaved: true
        )!
    }

    func encode(sampleBuffer: CMSampleBuffer) throws -> Data {
        let sourceFormat = try AudioSampleBufferConverter.audioFormat(from: sampleBuffer)
        let sourcePCMBuffer = try AudioSampleBufferConverter.makePCMBuffer(from: sampleBuffer, format: sourceFormat)
        return try encode(pcmBuffer: sourcePCMBuffer)
    }

    func encode(pcmBuffer: AVAudioPCMBuffer) throws -> Data {
        let sourceFormat = pcmBuffer.format

        let sourceSignature = AudioFormatSignature(format: sourceFormat)
        if converter == nil || sourceFormatSignature != sourceSignature {
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
            sourceFormatSignature = sourceSignature
        }

        guard let converter else {
            throw SystemAudioCaptureError.failedToCreateAudioBuffer
        }

        let frameRatio = targetFormat.sampleRate / sourceFormat.sampleRate
        let targetFrameCapacity = AVAudioFrameCount(
            max(1, ceil(Double(pcmBuffer.frameLength) * frameRatio) + 32)
        )

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: targetFrameCapacity
        ) else {
            throw SystemAudioCaptureError.failedToCreateAudioBuffer
        }

        var conversionError: NSError?
        var consumedInput = false

        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if consumedInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            consumedInput = true
            outStatus.pointee = .haveData
            return pcmBuffer
        }

        if let conversionError {
            throw conversionError
        }

        guard status != .error, convertedBuffer.frameLength > 0 else {
            throw SystemAudioCaptureError.failedToCreateAudioBuffer
        }

        guard let audioBuffer = convertedBuffer.audioBufferList.pointee.mBuffers.mData else {
            throw SystemAudioCaptureError.failedToCreateAudioBuffer
        }

        let byteCount = Int(convertedBuffer.audioBufferList.pointee.mBuffers.mDataByteSize)
        return Data(bytes: audioBuffer, count: byteCount)
    }
}

private struct AudioFormatSignature: Equatable {
    let sampleRate: Double
    let channelCount: AVAudioChannelCount
    let commonFormat: AVAudioCommonFormat
    let isInterleaved: Bool

    init(format: AVAudioFormat) {
        self.sampleRate = format.sampleRate
        self.channelCount = format.channelCount
        self.commonFormat = format.commonFormat
        self.isInterleaved = format.isInterleaved
    }
}
