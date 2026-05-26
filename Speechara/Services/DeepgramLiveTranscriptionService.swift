import Foundation

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
    private let session: URLSession
    private let webSocketOpenObserver: DeepgramWebSocketOpenObserver?
    private let proxyService: SpeecharaBackendProxyService

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var sendChain: Task<Void, Error>?
    private var eventHandler: (@Sendable (DeepgramTranscriptEvent) -> Void)?
    private var errorHandler: (@Sendable (String) -> Void)?
    private var isStopping = false

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
        guard webSocketTask == nil else {
            throw DeepgramLiveTranscriptionError.alreadyConnected
        }

        let request: URLRequest
        do {
            request = try await makeRequest(
                sourceLanguageCode: sourceLanguageCode,
                diarize: diarize,
                utterances: utterances
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

        self.eventHandler = eventHandler
        self.errorHandler = errorHandler
        self.isStopping = false

        let webSocketTask = session.webSocketTask(with: request)
        webSocketOpenObserver?.prepare(for: webSocketTask.taskIdentifier)
        self.webSocketTask = webSocketTask
        webSocketTask.resume()

        do {
            try await webSocketOpenObserver?.waitForOpen(taskIdentifier: webSocketTask.taskIdentifier)
        } catch {
            webSocketTask.cancel(with: .goingAway, reason: nil)
            cleanup()
            throw DeepgramLiveTranscriptionError.connectionFailed(error.localizedDescription)
        }

        startReceiveLoop(for: webSocketTask)
        startKeepAliveLoop(for: webSocketTask)
    }

    func sendAudio(_ audioData: Data) {
        guard !audioData.isEmpty, !isStopping, let webSocketTask else {
            return
        }

        let previousSend = sendChain
        sendChain = Task {
            do {
                _ = try await previousSend?.value
                try await webSocketTask.send(.data(audioData))
            } catch {
                self.handleStreamingError(DeepgramLiveTranscriptionError.sendFailed(error))
                throw error
            }
        }
    }

    func stop() async {
        isStopping = true

        let pendingSend = sendChain
        sendChain = nil

        do {
            _ = try await pendingSend?.value
        } catch {
            handleStreamingError(DeepgramLiveTranscriptionError.sendFailed(error))
        }

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

    private func startReceiveLoop(for webSocketTask: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(for: webSocketTask)
        }
    }

    private func startKeepAliveLoop(for webSocketTask: URLSessionWebSocketTask) {
        keepAliveTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self.sendKeepAlive(on: webSocketTask)
            }
        }
    }

    private func receiveLoop(for webSocketTask: URLSessionWebSocketTask) async {
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

                handleStreamingError(DeepgramLiveTranscriptionError.receiveFailed(error))
                break
            }
        }
    }

    private func sendKeepAlive(on webSocketTask: URLSessionWebSocketTask) async {
        guard !isStopping else {
            return
        }

        do {
            try await webSocketTask.send(.string(#"{"type":"KeepAlive"}"#))
        } catch {
            handleStreamingError(DeepgramLiveTranscriptionError.sendFailed(error))
        }
    }

    private func handleIncomingTextMessage(_ text: String) async throws {
        guard let data = text.data(using: .utf8) else {
            return
        }

        let envelope = try JSONDecoder().decode(DeepgramMessageEnvelope.self, from: data)

        switch envelope.type {
        case "Results":
            let results = try JSONDecoder().decode(DeepgramResultsMessage.self, from: data)
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
        guard !isStopping else {
            return
        }

        errorHandler?(error.localizedDescription)
    }

    private func cleanup() {
        receiveTask?.cancel()
        keepAliveTask?.cancel()
        receiveTask = nil
        keepAliveTask = nil
        webSocketTask = nil
        eventHandler = nil
        errorHandler = nil
        isStopping = false
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
                URLQueryItem(name: "diarize", value: diarize ? "true" : "false"),
                URLQueryItem(name: "utterances", value: utterances ? "true" : "false"),
                URLQueryItem(name: "vad_events", value: "true"),
                URLQueryItem(name: "endpointing", value: "500"),
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
    let utterances: [DeepgramUtterance]?

    enum CodingKeys: String, CodingKey {
        case type
        case channel
        case isFinal = "is_final"
        case speechFinal = "speech_final"
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
