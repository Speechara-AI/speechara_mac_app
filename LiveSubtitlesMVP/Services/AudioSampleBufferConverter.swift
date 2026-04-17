import AVFAudio
import CoreMedia
import Foundation

enum AudioSampleBufferConverter {
    static func audioFormat(from sampleBuffer: CMSampleBuffer) throws -> AVAudioFormat {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw SystemAudioCaptureError.missingAudioFormat
        }

        guard CMFormatDescriptionGetMediaType(formatDescription) == kCMMediaType_Audio else {
            throw SystemAudioCaptureError.missingAudioFormat
        }

        let audioFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        guard audioFormat.commonFormat != .otherFormat else {
            throw SystemAudioCaptureError.unsupportedAudioFormat
        }

        return audioFormat
    }

    static func makePCMBuffer(from sampleBuffer: CMSampleBuffer, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let bufferCount = format.isInterleaved ? 1 : Int(format.channelCount)
        let audioBufferListSize = MemoryLayout<AudioBufferList>.size
            + max(0, bufferCount - 1) * MemoryLayout<AudioBuffer>.size

        let audioBufferListMemory = UnsafeMutableRawPointer.allocate(
            byteCount: audioBufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        audioBufferListMemory.initializeMemory(as: UInt8.self, repeating: 0, count: audioBufferListSize)

        let audioBufferListPointer = audioBufferListMemory.bindMemory(to: AudioBufferList.self, capacity: 1)
        var retainedBlockBuffer: CMBlockBuffer?

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferListPointer,
            bufferListSize: audioBufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &retainedBlockBuffer
        )

        guard status == noErr else {
            audioBufferListMemory.deallocate()
            throw SystemAudioCaptureError.failedToCreateAudioBuffer
        }

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            bufferListNoCopy: audioBufferListPointer,
            deallocator: { _ in
                audioBufferListMemory.deallocate()
                _ = retainedBlockBuffer
            }
        ) else {
            audioBufferListMemory.deallocate()
            throw SystemAudioCaptureError.failedToCreateAudioBuffer
        }

        pcmBuffer.frameLength = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        return pcmBuffer
    }
}
