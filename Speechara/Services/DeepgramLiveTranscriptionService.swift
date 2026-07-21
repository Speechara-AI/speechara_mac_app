import Foundation
import OSLog

enum DeepgramLiveTranscriptionError: LocalizedError {
    case authenticationRequired
    case invalidRequest
    case alreadyConnected
    case connectionFailed(String)
    case sendFailed(Error)
    case receiveFailed(Error)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Sign in to start live transcription."
        case .invalidRequest:
            return "The app could not create the live transcription request."
        case .alreadyConnected:
            return "Live transcription is already connected."
        case .connectionFailed(let message):
            return "The app could not open the live transcription connection: \(message)"
        case .sendFailed(let error):
            return "The app could not stream audio for transcription: \(error.localizedDescription)"
        case .receiveFailed(let error):
            return "The app could not receive a transcription update: \(error.localizedDescription)"
        case .serverError(let message):
            return "The transcription service returned an error: \(message)"
        }
    }
}

private enum DeepgramWebSocketOpenError: LocalizedError {
    case timedOut
    case closed(URLSessionWebSocketTask.CloseCode, String?)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "The transcription service did not accept the connection in time."
        case .closed(let code, let reason):
            if let reason, !reason.isEmpty {
                return "The transcription service closed the connection before it was ready. Code \(code.rawValue): \(reason)"
            }

            return "The transcription service closed the connection before it was ready. Code \(code.rawValue)."
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

private final class DeepgramWebSocketOpenObserver: NSObject, URLSessionWebSocketDelegate, URLSessionTaskDelegate {
    private let lock = NSLock()
    private var continuations = [Int: CheckedContinuation<Void, Error>]()
    private var completedTaskIDs = Set<Int>()
    private var completedResults = [Int: Result<Void, Error>]()

    func prepare(for taskIdentifier: Int) {
        lock.lock()
        continuations.removeValue(forKey: taskIdentifier)
        completedTaskIDs.remove(taskIdentifier)
        completedResults.removeValue(forKey: taskIdentifier)
        lock.unlock()
    }

    func waitForOpen(taskIdentifier: Int, timeout: TimeInterval = 8) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()

            if let result = completedResults.removeValue(forKey: taskIdentifier) {
                lock.unlock()
                continuation.resume(with: result)
                return
            }

            continuations[taskIdentifier] = continuation
            lock.unlock()

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.complete(
                    taskIdentifier: taskIdentifier,
                    with: .failure(DeepgramWebSocketOpenError.timedOut)
                )
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        complete(taskIdentifier: webSocketTask.taskIdentifier, with: .success(()))
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) }
        complete(
            taskIdentifier: webSocketTask.taskIdentifier,
            with: .failure(DeepgramWebSocketOpenError.closed(closeCode, reasonText))
        )
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else {
            return
        }

        complete(
            taskIdentifier: task.taskIdentifier,
            with: .failure(DeepgramWebSocketOpenError.transport(error))
        )
    }

    private func complete(taskIdentifier: Int, with result: Result<Void, Error>) {
        lock.lock()

        guard !completedTaskIDs.contains(taskIdentifier) else {
            lock.unlock()
            return
        }

        completedTaskIDs.insert(taskIdentifier)

        if let continuation = continuations.removeValue(forKey: taskIdentifier) {
            lock.unlock()
            continuation.resume(with: result)
            return
        }

        completedResults[taskIdentifier] = result
        lock.unlock()
    }
}

enum DeepgramTranscriptEvent {
    case interim(DeepgramTranscriptResult)
    case final(DeepgramTranscriptResult)
}

struct DeepgramTranscriptResult: Sendable {
    let transcript: String
    let speechFinal: Bool
}

actor DeepgramLiveTranscriptionService {
    private static let diagnosticsInterval: TimeInterval = 5
    // Never replay old meeting audio after a temporary network stall. Eight 64 ms
    // chunks keep less than 0.6 s of audio waiting on the client.
    private static let maximumPendingAudioChunks = 8
    private static let reconnectDelayNanoseconds: [UInt64] = [
        250_000_000,
        750_000_000,
        2_000_000_000,
        4_000_000_000,
    ]
    private static let logger = Logger(subsystem: "ai.speechara.mac", category: "DeepgramLiveTranscription")

    private let session: URLSession
    private let webSocketOpenObserver: DeepgramWebSocketOpenObserver?
    private let proxyService: SpeecharaBackendProxyService
    private var currentSourceLanguageCode = ""
    private var currentDiarize = false
    private var currentUtterances = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var audioSendLoopTask: Task<Void, Never>?
    private var pendingAudioChunks = [Data]()
    private var eventHandler: (@Sendable (DeepgramTranscriptEvent) -> Void)?
    private var errorHandler: (@Sendable (String) -> Void)?
    private var isStopping = false
    private var didReportStreamingError = false
    private var connectionGeneration = UUID()
    private var lastDiagnosticsLogDate = Date()
    private var lastResultDiagnosticsLogDate = Date()
    private var firstAudioSentAtUptimeNanoseconds: UInt64?
    private var sentAudioSampleCount: Int64 = 0
    private var enqueuedChunkCount = 0
    private var sentChunkCount = 0
    private var sendDurationTotalMilliseconds = 0.0
    private var sendDurationSampleCount = 0
    private var reconnectAttemptCount = 0
    private var inFlightAudioSendCount = 0
    private var droppedAudioChunkCount = 0
    private var maximumObservedPendingAudioChunks = 0
    private var audioSendsDrainedContinuation: CheckedContinuation<Void, Never>?

    init(
        session: URLSession? = nil,
        proxyService: SpeecharaBackendProxyService = SpeecharaBackendProxyService()
    ) {
        if let session {
            self.session = session
            self.webSocketOpenObserver = nil
        } else {
            let webSocketOpenObserver = DeepgramWebSocketOpenObserver()
            self.webSocketOpenObserver = webSocketOpenObserver
            self.session = URLSession(
                configuration: .default,
                delegate: webSocketOpenObserver,
                delegateQueue: nil
            )
        }

        self.proxyService = proxyService
    }

    func connect(
        sourceLanguageCode: String,
        diarize: Bool = false,
        utterances: Bool = false,
        eventHandler: @escaping @Sendable (DeepgramTranscriptEvent) -> Void,
        errorHandler: @escaping @Sendable (String) -> Void
    ) async throws {
        SpeecharaDiagnostics.transcription.notice("connect requested language=\(sourceLanguageCode) diarize=\(diarize) utterances=\(utterances)")
        guard webSocketTask == nil else {
            SpeecharaDiagnostics.transcription.error("connect rejected: websocket already exists")
            throw DeepgramLiveTranscriptionError.alreadyConnected
        }

        self.eventHandler = eventHandler
        self.errorHandler = errorHandler
        self.isStopping = false
        self.didReportStreamingError = false
        self.connectionGeneration = UUID()
        self.currentSourceLanguageCode = sourceLanguageCode
        self.currentDiarize = diarize
        self.currentUtterances = utterances
        self.reconnectAttemptCount = 0
        resetDiagnostics()

        do {
            try await openWebSocket()
        } catch {
            cleanup()
            throw error
        }
    }

    func sendAudio(_ audioData: Data) {
        guard !audioData.isEmpty, !isStopping, !didReportStreamingError, let webSocketTask else {
            SpeecharaDiagnostics.audio.debug("audio chunk dropped bytes=\(audioData.count) stopping=\(self.isStopping) hasSocket=\(self.webSocketTask != nil) reportedError=\(self.didReportStreamingError)")
            return
        }

        enqueuedChunkCount += 1
        if pendingAudioChunks.count >= Self.maximumPendingAudioChunks {
            let numberToDrop = pendingAudioChunks.count - Self.maximumPendingAudioChunks + 1
            pendingAudioChunks.removeFirst(numberToDrop)
            droppedAudioChunkCount += numberToDrop
            Self.logger.warning(
                "dropped stale audio chunks count=\(numberToDrop, privacy: .public) totalDropped=\(self.droppedAudioChunkCount, privacy: .public)"
            )
        }
        pendingAudioChunks.append(audioData)
        maximumObservedPendingAudioChunks = max(maximumObservedPendingAudioChunks, pendingAudioChunks.count)
        logDiagnosticsIfNeeded(reason: "enqueue")
        let generation = connectionGeneration

        guard audioSendLoopTask == nil else {
            return
        }
        audioSendLoopTask = Task { [weak self] in
            await self?.runAudioSendLoop(on: webSocketTask, generation: generation)
        }
    }

    func stop() async {
        SpeecharaDiagnostics.transcription.notice(
            "stop requested pendingAudio=\(self.pendingAudioChunks.count) inFlight=\(self.inFlightAudioSendCount) dropped=\(self.droppedAudioChunkCount)"
        )
        isStopping = true
        pendingAudioChunks.removeAll()
        audioSendLoopTask?.cancel()
        await waitForOutstandingAudioSends()

        if let webSocketTask {
            do {
                try await webSocketTask.send(.string(#"{"type":"Finalize"}"#))
            } catch {
                handleStreamingError(DeepgramLiveTranscriptionError.sendFailed(error))
            }

            try? await Task.sleep(nanoseconds: 500_000_000)

            do {
                try await webSocketTask.send(.string(#"{"type":"CloseStream"}"#))
            } catch {
                handleStreamingError(DeepgramLiveTranscriptionError.sendFailed(error))
            }

            webSocketTask.cancel(with: .normalClosure, reason: nil)
        }

        cleanup()
    }

    private func openWebSocket() async throws {
        let request: URLRequest
        do {
            request = try await makeRequest(
                sourceLanguageCode: currentSourceLanguageCode,
                diarize: currentDiarize,
                utterances: currentUtterances
            )
        } catch let error as SpeecharaBackendProxyError {
            switch error {
            case .authenticationRequired:
                throw DeepgramLiveTranscriptionError.authenticationRequired
            case .invalidRequest, .invalidBackendBaseURL:
                throw DeepgramLiveTranscriptionError.invalidRequest
            case .invalidResponse, .serverError:
                throw DeepgramLiveTranscriptionError.serverError(error.localizedDescription)
            }
        }

        let generation = connectionGeneration
        let webSocketTask = session.webSocketTask(with: request)
        webSocketOpenObserver?.prepare(for: webSocketTask.taskIdentifier)
        self.webSocketTask = webSocketTask
        webSocketTask.resume()

        do {
            try await webSocketOpenObserver?.waitForOpen(taskIdentifier: webSocketTask.taskIdentifier)
        } catch {
            webSocketTask.cancel(with: .goingAway, reason: nil)
            throw DeepgramLiveTranscriptionError.connectionFailed(error.localizedDescription)
        }

        startReceiveLoop(for: webSocketTask, generation: generation)
        startKeepAliveLoop(for: webSocketTask, generation: generation)
    }

    private func startReceiveLoop(for webSocketTask: URLSessionWebSocketTask, generation: UUID) {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(for: webSocketTask, generation: generation)
        }
    }

    private func runAudioSendLoop(
        on webSocketTask: URLSessionWebSocketTask,
        generation: UUID
    ) async {
        defer {
            audioSendLoopDidFinish(generation: generation, webSocketTask: webSocketTask)
        }

        while !Task.isCancelled {
            guard generation == connectionGeneration,
                  self.webSocketTask === webSocketTask,
                  !isStopping,
                  !didReportStreamingError,
                  !pendingAudioChunks.isEmpty else {
                return
            }

            let audioData = pendingAudioChunks.removeFirst()
            inFlightAudioSendCount = 1
            do {
                let startedAt = Date()
                try await webSocketTask.send(.data(audioData))
                let elapsedMilliseconds = Date().timeIntervalSince(startedAt) * 1_000
                if firstAudioSentAtUptimeNanoseconds == nil {
                    firstAudioSentAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
                }
                sentAudioSampleCount += Int64(audioData.count / MemoryLayout<Int16>.size)
                sentChunkCount += 1
                reconnectAttemptCount = 0
                sendDurationTotalMilliseconds += elapsedMilliseconds
                sendDurationSampleCount += 1
                inFlightAudioSendCount = 0
                audioSendDidFinish()
                logDiagnosticsIfNeeded(reason: "send")
            } catch is CancellationError {
                inFlightAudioSendCount = 0
                audioSendDidFinish()
                return
            } catch {
                inFlightAudioSendCount = 0
                audioSendDidFinish()
                guard generation == connectionGeneration,
                      self.webSocketTask === webSocketTask,
                      !isStopping else {
                    return
                }
                if await reconnectAfterTransientSocketFailure(
                    error,
                    generation: generation,
                    failedTask: webSocketTask,
                    cancelAudioSendLoop: false
                ) {
                    return
                }
                handleStreamingError(DeepgramLiveTranscriptionError.sendFailed(error))
                return
            }
        }
    }

    private func startKeepAliveLoop(for webSocketTask: URLSessionWebSocketTask, generation: UUID) {
        keepAliveTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self.sendKeepAlive(on: webSocketTask, generation: generation)
            }
        }
    }

    private func receiveLoop(for webSocketTask: URLSessionWebSocketTask, generation: UUID) async {
        while !Task.isCancelled {
            do {
                let message = try await webSocketTask.receive()

                switch message {
                case .string(let text):
                    try await handleIncomingTextMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        try await handleIncomingTextMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if isStopping || Task.isCancelled {
                    break
                }

                guard generation == connectionGeneration,
                      self.webSocketTask === webSocketTask else {
                    break
                }

                if await reconnectAfterTransientSocketFailure(
                    error,
                    generation: generation,
                    failedTask: webSocketTask,
                    cancelAudioSendLoop: true
                ) {
                    break
                }

                handleStreamingError(DeepgramLiveTranscriptionError.receiveFailed(error))
                break
            }
        }
    }

    private func sendKeepAlive(on webSocketTask: URLSessionWebSocketTask, generation: UUID) async {
        guard !isStopping,
              generation == connectionGeneration,
              self.webSocketTask === webSocketTask else {
            return
        }

        do {
            try await webSocketTask.send(.string(#"{"type":"KeepAlive"}"#))
        } catch {
            guard generation == connectionGeneration,
                  self.webSocketTask === webSocketTask else {
                return
            }

            handleStreamingError(DeepgramLiveTranscriptionError.sendFailed(error))
        }
    }

    private func reconnectAfterTransientSocketFailure(
        _ error: Error,
        generation: UUID,
        failedTask: URLSessionWebSocketTask,
        cancelAudioSendLoop: Bool
    ) async -> Bool {
        guard reconnectAttemptCount < Self.reconnectDelayNanoseconds.count,
              generation == connectionGeneration,
              self.webSocketTask === failedTask,
              !isStopping,
              !didReportStreamingError else {
            return false
        }

        keepAliveTask?.cancel()
        keepAliveTask = nil
        if cancelAudioSendLoop {
            audioSendLoopTask?.cancel()
        }
        audioSendLoopTask = nil
        pendingAudioChunks.removeAll()
        failedTask.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        while reconnectAttemptCount < Self.reconnectDelayNanoseconds.count {
            let delay = Self.reconnectDelayNanoseconds[reconnectAttemptCount]
            reconnectAttemptCount += 1
            Self.logger.warning(
                "Deepgram socket failed; reconnecting attempt=\(self.reconnectAttemptCount, privacy: .public) source=\(cancelAudioSendLoop ? "receive" : "send", privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )

            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return true
            }
            guard generation == connectionGeneration,
                  !isStopping,
                  !didReportStreamingError else {
                return true
            }

            webSocketTask = nil
            do {
                try await openWebSocket()
                Self.logger.notice(
                    "Deepgram websocket reconnected attempt=\(self.reconnectAttemptCount, privacy: .public)"
                )
                return true
            } catch {
                Self.logger.warning(
                    "Deepgram reconnect attempt failed attempt=\(self.reconnectAttemptCount, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
        return false
    }

    private func handleIncomingTextMessage(_ text: String) async throws {
        guard let data = text.data(using: .utf8) else {
            return
        }

        let envelope = try JSONDecoder().decode(DeepgramMessageEnvelope.self, from: data)

        switch envelope.type {
        case "Results":
            let results = try JSONDecoder().decode(DeepgramResultsMessage.self, from: data)
            reconnectAttemptCount = 0
            logResultLatencyIfNeeded(results)
            let transcript = Self.transcript(from: results)
            guard !transcript.isEmpty else {
                return
            }

            let eventResult = DeepgramTranscriptResult(
                transcript: transcript,
                speechFinal: results.speechFinal
            )

            if results.isFinal {
                eventHandler?(.final(eventResult))
            } else {
                eventHandler?(.interim(eventResult))
            }
        case "Metadata", "UtteranceEnd", "SpeechStarted":
            return
        case "Error":
            let errorMessage = (try? JSONDecoder().decode(DeepgramErrorMessage.self, from: data))?.description
                ?? (try? JSONDecoder().decode(DeepgramErrorMessage.self, from: data))?.message
                ?? "Unknown transcription service error."
            throw DeepgramLiveTranscriptionError.serverError(errorMessage)
        default:
            return
        }
    }

    private func handleStreamingError(_ error: Error) {
        guard !isStopping, !didReportStreamingError else {
            SpeecharaDiagnostics.transcription.debug("streaming error suppressed stopping=\(self.isStopping) alreadyReported=\(self.didReportStreamingError)")
            return
        }

        SpeecharaDiagnostics.transcription.error("streaming error error=\(error.localizedDescription) queued=\(self.enqueuedChunkCount) sent=\(self.sentChunkCount)")
        didReportStreamingError = true
        let errorMessage = error.localizedDescription
        let errorHandler = errorHandler
        cleanup(cancelWebSocket: true)
        errorHandler?(errorMessage)
    }

    private func cleanup(cancelWebSocket: Bool = false) {
        connectionGeneration = UUID()
        receiveTask?.cancel()
        keepAliveTask?.cancel()
        audioSendLoopTask?.cancel()
        if cancelWebSocket {
            webSocketTask?.cancel(with: .goingAway, reason: nil)
        }
        receiveTask = nil
        keepAliveTask = nil
        audioSendLoopTask = nil
        pendingAudioChunks.removeAll()
        webSocketTask = nil
        eventHandler = nil
        errorHandler = nil
        isStopping = false
    }

    private func resetDiagnostics() {
        lastDiagnosticsLogDate = Date()
        lastResultDiagnosticsLogDate = Date()
        firstAudioSentAtUptimeNanoseconds = nil
        sentAudioSampleCount = 0
        enqueuedChunkCount = 0
        sentChunkCount = 0
        sendDurationTotalMilliseconds = 0
        sendDurationSampleCount = 0
        droppedAudioChunkCount = 0
        maximumObservedPendingAudioChunks = 0
    }

    private func waitForOutstandingAudioSends() async {
        guard inFlightAudioSendCount > 0 else {
            return
        }

        await withCheckedContinuation { continuation in
            audioSendsDrainedContinuation = continuation
        }
    }

    private func audioSendDidFinish() {
        guard inFlightAudioSendCount == 0,
              let continuation = audioSendsDrainedContinuation else {
            return
        }

        audioSendsDrainedContinuation = nil
        continuation.resume()
    }

    private func audioSendLoopDidFinish(
        generation: UUID,
        webSocketTask finishedWebSocketTask: URLSessionWebSocketTask
    ) {
        guard generation == connectionGeneration,
              webSocketTask == nil || webSocketTask === finishedWebSocketTask else {
            return
        }
        audioSendLoopTask = nil
        audioSendDidFinish()
    }

    private func logDiagnosticsIfNeeded(reason: String) {
        let now = Date()
        guard now.timeIntervalSince(lastDiagnosticsLogDate) >= Self.diagnosticsInterval else {
            return
        }

        let averageSendMilliseconds = sendDurationSampleCount > 0
            ? sendDurationTotalMilliseconds / Double(sendDurationSampleCount)
            : 0
        Self.logger.info(
            "Deepgram stream diagnostics reason=\(reason, privacy: .public) enqueued=\(self.enqueuedChunkCount, privacy: .public) sent=\(self.sentChunkCount, privacy: .public) pending=\(self.pendingAudioChunks.count, privacy: .public) maxPending=\(self.maximumObservedPendingAudioChunks, privacy: .public) dropped=\(self.droppedAudioChunkCount, privacy: .public) inFlight=\(self.inFlightAudioSendCount, privacy: .public) avgSendMs=\(averageSendMilliseconds, privacy: .public)"
        )

        lastDiagnosticsLogDate = now
        enqueuedChunkCount = 0
        sentChunkCount = 0
        sendDurationTotalMilliseconds = 0
        sendDurationSampleCount = 0
        maximumObservedPendingAudioChunks = pendingAudioChunks.count
    }

    private func logResultLatencyIfNeeded(_ results: DeepgramResultsMessage) {
        let now = Date()
        guard now.timeIntervalSince(lastResultDiagnosticsLogDate) >= Self.diagnosticsInterval,
              let firstAudioSentAtUptimeNanoseconds else {
            return
        }

        let uptimeNow = DispatchTime.now().uptimeNanoseconds
        let wallAudioSeconds = uptimeNow >= firstAudioSentAtUptimeNanoseconds
            ? Double(uptimeNow - firstAudioSentAtUptimeNanoseconds) / 1_000_000_000
            : 0
        let resultAudioEndSeconds = (results.start ?? 0) + (results.duration ?? 0)
        let resultAgeSeconds = max(0, wallAudioSeconds - resultAudioEndSeconds)
        let sentAudioSeconds = Double(sentAudioSampleCount) / Double(AudioChunkEncoder.targetSampleRate)

        Self.logger.info(
            "Deepgram result latency resultEndSec=\(resultAudioEndSeconds, privacy: .public) wallSec=\(wallAudioSeconds, privacy: .public) sentAudioSec=\(sentAudioSeconds, privacy: .public) resultAgeSec=\(resultAgeSeconds, privacy: .public) isFinal=\(results.isFinal, privacy: .public) speechFinal=\(results.speechFinal, privacy: .public)"
        )
        lastResultDiagnosticsLogDate = now
    }

    private func makeRequest(
        sourceLanguageCode: String,
        diarize: Bool,
        utterances: Bool
    ) async throws -> URLRequest {
        try await proxyService.makeWebSocketRequest(
            path: "/api/stt/deepgram/live",
            queryItems: [
                URLQueryItem(name: "model", value: "nova-3"),
                URLQueryItem(name: "language", value: sourceLanguageCode),
                URLQueryItem(name: "encoding", value: "linear16"),
                URLQueryItem(name: "sample_rate", value: String(AudioChunkEncoder.targetSampleRate)),
                URLQueryItem(name: "channels", value: String(AudioChunkEncoder.targetChannelCount)),
                URLQueryItem(name: "interim_results", value: "true"),
                URLQueryItem(name: "punctuate", value: "true"),
                URLQueryItem(name: "smart_format", value: "true"),
                URLQueryItem(name: "diarize", value: diarize ? "true" : "false"),
                URLQueryItem(name: "utterances", value: utterances ? "true" : "false"),
                URLQueryItem(name: "vad_events", value: "true"),
                URLQueryItem(name: "endpointing", value: "300"),
                URLQueryItem(name: "utterance_end_ms", value: "1000"),
            ]
        )
    }

    private static func transcript(from results: DeepgramResultsMessage) -> String {
        guard let alternative = results.channel.alternatives.first else {
            return utteranceTranscript(from: results)
        }

        let transcript = alternative.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !transcript.isEmpty {
            return transcript
        }

        return utteranceTranscript(from: results)
    }

    private static func utteranceTranscript(from results: DeepgramResultsMessage) -> String {
        guard let utterances = results.utterances, !utterances.isEmpty else {
            return ""
        }

        return utterances
            .compactMap { utterance in
                let transcript = (utterance.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return transcript.isEmpty ? nil : transcript
            }
            .joined(separator: " ")
    }
}

private struct DeepgramMessageEnvelope: Decodable {
    let type: String
}

private struct DeepgramResultsMessage: Decodable {
    let type: String
    let channel: DeepgramResultsChannel
    let isFinal: Bool
    let speechFinal: Bool
    let start: Double?
    let duration: Double?
    let utterances: [DeepgramUtterance]?

    enum CodingKeys: String, CodingKey {
        case type
        case channel
        case isFinal = "is_final"
        case speechFinal = "speech_final"
        case start
        case duration
        case utterances
    }
}

private struct DeepgramResultsChannel: Decodable {
    let alternatives: [DeepgramTranscriptAlternative]
}

private struct DeepgramTranscriptAlternative: Decodable {
    let transcript: String?
}

private struct DeepgramUtterance: Decodable {
    let transcript: String?
}

private struct DeepgramErrorMessage: Decodable {
    let type: String?
    let message: String?
    let description: String?
}
