import Foundation

actor MixedAudioStreamMixer {
    // 1,024 samples at 16 kHz is 64 ms, within Deepgram's recommended
    // 20–100 ms streaming buffer range.
    private static let chunkSampleCount = 1024
    private static let maximumBufferedSampleCount = chunkSampleCount * 8
    private static let maximumPendingOutputChunks = 6
    private static let diagnosticsInterval: TimeInterval = 5
    private static let systemGain = 0.95
    private static let microphoneGain = 1.35

    private var systemSamples: ArraySlice<Int16> = []
    private var microphoneSamples: ArraySlice<Int16> = []
    private var pendingOutputChunks = [Data]()
    private var microphoneEnabled = false
    private var outputHandler: (@Sendable (Data) async -> Void)?
    private var outputLoopTask: Task<Void, Never>?
    private var outputLoopGeneration = UUID()
    private var outputDrainContinuations = [CheckedContinuation<Void, Never>]()
    private var lastDiagnosticsDate = Date()
    private var receivedSystemSampleCount = 0
    private var receivedMicrophoneSampleCount = 0
    private var producedChunkCount = 0
    private var deliveredChunkCount = 0

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
        pendingOutputChunks.removeAll(keepingCapacity: false)
        microphoneEnabled = false
        outputHandler = nil
        stopOutputLoop()
        lastDiagnosticsDate = Date()
        receivedSystemSampleCount = 0
        receivedMicrophoneSampleCount = 0
        producedChunkCount = 0
        deliveredChunkCount = 0
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        microphoneEnabled = enabled
        SpeecharaDiagnostics.audio.notice(
            "mixer microphone enabled=\(enabled) systemBuffered=\(self.systemSamples.count) microphoneBuffered=\(self.microphoneSamples.count)"
        )

        if !enabled {
            microphoneSamples.removeAll(keepingCapacity: false)
        }
    }

    func appendSystemAudio(_ audioData: Data) async {
        receivedSystemSampleCount += audioData.count / MemoryLayout<Int16>.size
        append(audioData, into: &systemSamples)
        trimStaleSamplesIfNeeded(in: &systemSamples, lane: "system")
        enqueueAvailableChunks(force: false)
        startOutputLoopIfNeeded()
        logDiagnosticsIfNeeded()
    }

    func appendMicrophoneAudio(_ audioData: Data) async {
        guard microphoneEnabled else {
            return
        }

        receivedMicrophoneSampleCount += audioData.count / MemoryLayout<Int16>.size
        append(audioData, into: &microphoneSamples)
        trimStaleSamplesIfNeeded(in: &microphoneSamples, lane: "microphone")
        enqueueAvailableChunks(force: false)
        startOutputLoopIfNeeded()
        logDiagnosticsIfNeeded()
    }

    func drainRemainingAudio() async {
        enqueueAvailableChunks(force: true)
        startOutputLoopIfNeeded()
        guard outputLoopTask != nil else {
            return
        }
        await withCheckedContinuation { continuation in
            outputDrainContinuations.append(continuation)
        }
    }

    private func startOutputLoopIfNeeded() {
        guard outputHandler != nil,
              !pendingOutputChunks.isEmpty,
              outputLoopTask == nil else {
            return
        }

        let generation = outputLoopGeneration
        outputLoopTask = Task { [weak self] in
            await self?.runOutputLoop(generation: generation)
        }
    }

    private func stopOutputLoop() {
        outputLoopGeneration = UUID()
        outputLoopTask?.cancel()
        outputLoopTask = nil
        pendingOutputChunks.removeAll(keepingCapacity: false)
        resumeOutputDrainContinuations()
    }

    private func enqueueAvailableChunks(force: Bool) {
        while shouldEmitChunk(force: force) {
            let sampleCount = nextChunkSampleCount(force: force)
            let mixedAudio = mixChunk(sampleCount: sampleCount)
            guard !mixedAudio.isEmpty else {
                continue
            }
            pendingOutputChunks.append(mixedAudio)
            producedChunkCount += 1
            if pendingOutputChunks.count > Self.maximumPendingOutputChunks {
                let numberToDrop = pendingOutputChunks.count - Self.maximumPendingOutputChunks
                pendingOutputChunks.removeFirst(numberToDrop)
                SpeecharaDiagnostics.audio.warning(
                    "mixer dropped stale output chunks count=\(numberToDrop) pending=\(self.pendingOutputChunks.count)"
                )
            }
        }
    }

    private func runOutputLoop(generation: UUID) async {
        while !Task.isCancelled,
              generation == outputLoopGeneration,
              let handler = outputHandler,
              !pendingOutputChunks.isEmpty {
            let audioData = pendingOutputChunks.removeFirst()
            await handler(audioData)
            deliveredChunkCount += 1
        }

        guard generation == outputLoopGeneration else {
            return
        }
        outputLoopTask = nil
        if outputHandler != nil, !pendingOutputChunks.isEmpty {
            startOutputLoopIfNeeded()
        } else if pendingOutputChunks.isEmpty {
            resumeOutputDrainContinuations()
        }
    }

    private func resumeOutputDrainContinuations() {
        let continuations = outputDrainContinuations
        outputDrainContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func logDiagnosticsIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastDiagnosticsDate) >= Self.diagnosticsInterval else {
            return
        }
        SpeecharaDiagnostics.audio.info(
            "mixer diagnostics systemSamples=\(self.receivedSystemSampleCount) microphoneSamples=\(self.receivedMicrophoneSampleCount) produced=\(self.producedChunkCount) delivered=\(self.deliveredChunkCount) systemBuffered=\(self.systemSamples.count) microphoneBuffered=\(self.microphoneSamples.count) outputPending=\(self.pendingOutputChunks.count)"
        )
        lastDiagnosticsDate = now
        receivedSystemSampleCount = 0
        receivedMicrophoneSampleCount = 0
        producedChunkCount = 0
        deliveredChunkCount = 0
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

    private func trimStaleSamplesIfNeeded(in storage: inout ArraySlice<Int16>, lane: String) {
        guard storage.count > Self.maximumBufferedSampleCount else {
            return
        }
        let numberToDrop = storage.count - Self.maximumBufferedSampleCount
        storage = storage.dropFirst(numberToDrop)
        let bufferedSampleCount = storage.count
        SpeecharaDiagnostics.audio.warning(
            "mixer dropped stale samples lane=\(lane) samples=\(numberToDrop) buffered=\(bufferedSampleCount)"
        )
    }
}
