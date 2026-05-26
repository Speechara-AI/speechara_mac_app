import AudioToolbox
import AVFAudio
import Foundation

final class M4AAudioFileWriter {
    let outputURL: URL

    private let clientFormat: AVAudioFormat
    private var audioFile: ExtAudioFileRef?

    init(outputURL: URL) {
        self.outputURL = outputURL
        self.clientFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(AudioChunkEncoder.targetSampleRate),
            channels: AudioChunkEncoder.targetChannelCount,
            interleaved: true
        )!
    }

    func append(pcmData: Data) throws {
        guard !pcmData.isEmpty else {
            return
        }

        if audioFile == nil {
            try createAudioFile()
        }

        guard let audioFile else {
            throw SystemAudioCaptureError.failedToCreateAudioFile
        }

        let bytesPerFrame = Int(clientFormat.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else {
            throw SystemAudioCaptureError.failedToCreateAudioBuffer
        }

        let frameCount = UInt32(pcmData.count / bytesPerFrame)
        guard frameCount > 0 else {
            return
        }

        let writeStatus = pcmData.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let baseAddress = rawBuffer.baseAddress else {
                return noErr
            }

            let audioBuffer = AudioBuffer(
                mNumberChannels: clientFormat.channelCount,
                mDataByteSize: UInt32(pcmData.count),
                mData: UnsafeMutableRawPointer(mutating: baseAddress)
            )

            var audioBufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: audioBuffer
            )

            return ExtAudioFileWrite(audioFile, frameCount, &audioBufferList)
        }

        guard writeStatus == noErr else {
            throw SystemAudioCaptureError.failedToWriteAudioFile(writeStatus)
        }
    }

    func finish() {
        if let audioFile {
            ExtAudioFileDispose(audioFile)
        }

        audioFile = nil
    }

    private func createAudioFile() throws {
        var destinationFormat = AudioStreamBasicDescription(
            mSampleRate: clientFormat.sampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: AudioFormatFlags(MPEG4ObjectID.AAC_LC.rawValue),
            mBytesPerPacket: 0,
            mFramesPerPacket: 0,
            mBytesPerFrame: 0,
            mChannelsPerFrame: clientFormat.channelCount,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        var destinationFormatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let formatStatus = AudioFormatGetProperty(
            kAudioFormatProperty_FormatInfo,
            0,
            nil,
            &destinationFormatSize,
            &destinationFormat
        )

        guard formatStatus == noErr else {
            throw SystemAudioCaptureError.failedToCreateAudioFile
        }

        var audioFile: ExtAudioFileRef?
        let createStatus = ExtAudioFileCreateWithURL(
            outputURL as CFURL,
            kAudioFileM4AType,
            &destinationFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &audioFile
        )

        guard createStatus == noErr, let audioFile else {
            throw SystemAudioCaptureError.failedToCreateAudioFile
        }

        var clientStreamDescription = clientFormat.streamDescription.pointee
        let clientFormatStatus = ExtAudioFileSetProperty(
            audioFile,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &clientStreamDescription
        )

        guard clientFormatStatus == noErr else {
            ExtAudioFileDispose(audioFile)
            throw SystemAudioCaptureError.failedToCreateAudioFile
        }

        var audioConverter: AudioConverterRef?
        var converterSize = UInt32(MemoryLayout<AudioConverterRef?>.size)
        let converterStatus = ExtAudioFileGetProperty(
            audioFile,
            kExtAudioFileProperty_AudioConverter,
            &converterSize,
            &audioConverter
        )

        if converterStatus == noErr, let audioConverter {
            var bitRate: UInt32 = 128_000
            _ = AudioConverterSetProperty(
                audioConverter,
                kAudioConverterEncodeBitRate,
                UInt32(MemoryLayout<UInt32>.size),
                &bitRate
            )
        }

        self.audioFile = audioFile
    }
}
