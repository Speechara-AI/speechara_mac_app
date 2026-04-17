import Foundation

actor MixedAudioStreamMixer {
    private static let chunkSampleCount = 320
    private static let chunkIntervalNanoseconds: UInt64 = 20_000_000
    private static let systemGain = 0.95
    private static let microphoneGain = 1.35

    private var systemSamples: ArraySlice<Int16> = []
    private var microphoneSamples: ArraySlice<Int16> = []
    private var microphoneEnabled = false
    private var outputHandler: (@Sendable (Data) async -> Void)?
    private var outputLoopTask: Task<Void, Never>?

    func setOutputHandler(_ handler: (@Sendable (Data) async -> Void)?) {
        outputHandler = handler

        if handler == nil {
            stopOutputLoop()
        } else {
            startOutputLoopIfNeeded()
        }
    }

    func reset() {
        systemSamples.removeAll(keepingCapacity: false)
        microphoneSamples.removeAll(keepingCapacity: false)
        microphoneEnabled = false
        outputHandler = nil
        stopOutputLoop()
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        microphoneEnabled = enabled

        if !enabled {
            microphoneSamples.removeAll(keepingCapacity: false)
        }
    }

    func appendSystemAudio(_ audioData: Data) async {
        append(audioData, into: &systemSamples)
        startOutputLoopIfNeeded()
    }

    func appendMicrophoneAudio(_ audioData: Data) async {
        guard microphoneEnabled else {
            return
        }

        append(audioData, into: &microphoneSamples)
        startOutputLoopIfNeeded()
    }

    func drainRemainingAudio() async {
        await flushIfNeeded(force: true)
    }

    private func startOutputLoopIfNeeded() {
        guard outputHandler != nil, outputLoopTask == nil else {
            return
        }

        outputLoopTask = Task {
            while !Task.isCancelled {
                await flushIfNeeded(force: false)

                do {
                    try await Task.sleep(nanoseconds: Self.chunkIntervalNanoseconds)
                } catch {
                    break
                }
            }
        }
    }

    private func stopOutputLoop() {
        outputLoopTask?.cancel()
        outputLoopTask = nil
    }

    private func flushIfNeeded(force: Bool) async {
        while shouldEmitChunk(force: force) {
            let sampleCount = nextChunkSampleCount(force: force)
            let mixedAudio = mixChunk(sampleCount: sampleCount)
            guard !mixedAudio.isEmpty else {
                continue
            }
            await outputHandler?(mixedAudio)
        }
    }

    private func shouldEmitChunk(force: Bool) -> Bool {
        let availableSampleCount = max(systemSamples.count, microphoneEnabled ? microphoneSamples.count : 0)

        if force {
            return availableSampleCount > 0
        }

        return availableSampleCount >= Self.chunkSampleCount
    }

    private func nextChunkSampleCount(force: Bool) -> Int {
        let availableSampleCount = max(systemSamples.count, microphoneEnabled ? microphoneSamples.count : 0)
        return force ? min(Self.chunkSampleCount, availableSampleCount) : Self.chunkSampleCount
    }

    private func mixChunk(sampleCount: Int) -> Data {
        let systemChunk = Array(systemSamples.prefix(sampleCount))
        let microphoneChunk = Array(microphoneSamples.prefix(sampleCount))

        systemSamples = systemSamples.dropFirst(min(sampleCount, systemSamples.count))
        microphoneSamples = microphoneSamples.dropFirst(min(sampleCount, microphoneSamples.count))

        var mixedSamples = [Int16]()
        mixedSamples.reserveCapacity(sampleCount)

        for index in 0 ..< sampleCount {
            let systemSample = index < systemChunk.count ? Double(systemChunk[index]) * Self.systemGain : 0
            let microphoneSample = microphoneEnabled && index < microphoneChunk.count
                ? Double(microphoneChunk[index]) * Self.microphoneGain
                : 0

            let mixedValue = max(
                Int(Int16.min),
                min(Int(Int16.max), Int(systemSample + microphoneSample))
            )

            mixedSamples.append(Int16(mixedValue))
        }

        return mixedSamples.withUnsafeBufferPointer { bufferPointer in
            guard let baseAddress = bufferPointer.baseAddress else {
                return Data()
            }

            return Data(
                bytes: baseAddress,
                count: bufferPointer.count * MemoryLayout<Int16>.size
            )
        }
    }

    private func append(_ audioData: Data, into storage: inout ArraySlice<Int16>) {
        let sampleCount = audioData.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else {
            return
        }

        let samples = audioData.withUnsafeBytes { rawBuffer -> [Int16] in
            let pointer = rawBuffer.bindMemory(to: Int16.self)
            return Array(pointer.prefix(sampleCount))
        }

        storage.append(contentsOf: samples)
    }
}
