import Foundation

enum DeepSeekTranslationError: LocalizedError {
    case authenticationRequired
    case invalidRequest
    case invalidResponse
    case requestFailed(Error)
    case serverError(String)
    case alreadyConnected

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Sign in to use live translation."
        case .invalidRequest:
            return "The app could not create the translation request."
        case .invalidResponse:
            return "The AI backend returned an empty translation response."
        case .requestFailed(let error):
            return "The app could not translate the final transcript: \(error.localizedDescription)"
        case .serverError(let message):
            return "The AI backend returned an error: \(message)"
        case .alreadyConnected:
            return "Live translation is already connected."
        }
    }
}

enum DeepSeekTranslationEvent {
    case preview(UUID, String)
    case completed(UUID, String)
    case failed(String)
}

struct DeepSeekTranslationHistoryTurn: Sendable {
    let source: String
    let translation: String
}

actor DeepSeekTranslationService {
    private let maxHistoryTurns = 4
    private let session: URLSession
    private let proxyService: SpeecharaBackendProxyService

    private var sourceLanguageName = ""
    private var targetLanguageName = ""
    private var sourceLanguageCode = ""
    private var targetLanguageCode = ""
    private var recentHistoryTurns: [DeepSeekTranslationHistoryTurn] = []
    private var pendingTranscriptChunks: [PendingTranslationChunk] = []
    private var isProcessingQueue = false
    private var processingTask: Task<Void, Never>?
    private var eventHandler: (@Sendable (DeepSeekTranslationEvent) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var pendingTurnContinuations = [String: CheckedContinuation<String, Error>]()
    private var translationSocketReady = false
    private var isStopping = false
    private var liveSessionID = UUID().uuidString

    init(
        session: URLSession = .shared,
        proxyService: SpeecharaBackendProxyService = SpeecharaBackendProxyService()
    ) {
        self.session = session
        self.proxyService = proxyService
    }

    func startSession(
        sourceLanguageCode: String,
        sourceLanguageName: String,
        targetLanguageCode: String,
        targetLanguageName: String,
        eventHandler: @escaping @Sendable (DeepSeekTranslationEvent) -> Void
    ) async throws {
        guard webSocketTask == nil else {
            throw DeepSeekTranslationError.alreadyConnected
        }

        self.sourceLanguageCode = sourceLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceLanguageName = sourceLanguageName
        self.targetLanguageCode = targetLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.targetLanguageName = targetLanguageName
        self.eventHandler = eventHandler
        pendingTranscriptChunks = []
        isProcessingQueue = false
        processingTask?.cancel()
        processingTask = nil
        translationSocketReady = false
        isStopping = false
        liveSessionID = UUID().uuidString

        let request: URLRequest
        do {
            request = try await proxyService.makeWebSocketRequest(path: "/api/ai/translation/live")
        } catch let error as SpeecharaBackendProxyError {
            switch error {
            case .authenticationRequired:
                throw DeepSeekTranslationError.authenticationRequired
            case .invalidRequest, .invalidBackendBaseURL:
                throw DeepSeekTranslationError.invalidRequest
            case .invalidResponse, .serverError:
                throw DeepSeekTranslationError.serverError(error.localizedDescription)
            }
        }

        let webSocketTask = session.webSocketTask(with: request)
        self.webSocketTask = webSocketTask
        webSocketTask.resume()

        startReceiveLoop(for: webSocketTask)
        startKeepAliveLoop(for: webSocketTask)

        do {
            try await waitForReadySignal()
            try await sendSocketMessage(
                TranslationConfigureMessage(
                    type: "configure",
                    sessionId: liveSessionID,
                    sourceLanguage: self.sourceLanguageCode,
                    targetLanguage: self.targetLanguageCode
                )
            )
        } catch {
            await resetSession()
            throw error
        }
    }

    func enqueueFinalChunk(_ transcript: String, turnID: UUID) {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return
        }

        if let lastIndex = pendingTranscriptChunks.indices.last,
           pendingTranscriptChunks[lastIndex].turnID == turnID {
            pendingTranscriptChunks[lastIndex].transcript = mergedTranscriptChunk(
                existing: pendingTranscriptChunks[lastIndex].transcript,
                addition: trimmedTranscript
            )
        } else {
            pendingTranscriptChunks.append(
                PendingTranslationChunk(turnID: turnID, transcript: trimmedTranscript)
            )
        }

        guard !isProcessingQueue else {
            return
        }

        isProcessingQueue = true
        processingTask = Task {
            await processPendingChunks()
        }
    }

    func resetSession() async {
        isStopping = true

        processingTask?.cancel()
        processingTask = nil
        pendingTranscriptChunks.removeAll()
        isProcessingQueue = false
        recentHistoryTurns = []

        failReadyIfNeeded(with: CancellationError())
        failAllPendingTurns(with: CancellationError())

        receiveTask?.cancel()
        keepAliveTask?.cancel()
        receiveTask = nil
        keepAliveTask = nil

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        translationSocketReady = false
        sourceLanguageName = ""
        targetLanguageName = ""
        sourceLanguageCode = ""
        targetLanguageCode = ""
        eventHandler = nil
        isStopping = false
        liveSessionID = UUID().uuidString
    }

    func replaceHistory(with turns: [DeepSeekTranslationHistoryTurn]) {
        recentHistoryTurns = Array(turns.suffix(maxHistoryTurns))
    }

    func translateStableBlock(
        _ transcript: String,
        history: [DeepSeekTranslationHistoryTurn]
    ) async throws -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            throw DeepSeekTranslationError.invalidResponse
        }

        let historyMessages = history
            .suffix(maxHistoryTurns)
            .flatMap { turn -> [SpeecharaChatMessage] in
                let source = turn.source.trimmingCharacters(in: .whitespacesAndNewlines)
                let translation = turn.translation.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !source.isEmpty, !translation.isEmpty else {
                    return []
                }

                return [
                    SpeecharaChatMessage(role: "user", content: source),
                    SpeecharaChatMessage(role: "assistant", content: translation),
                ]
            }

        let blockTranscript = """
        Translate this stable dialogue block.
        Return exactly one output line for each input line, in the same order.
        Preserve timestamps like [12:34:56] and preserve speaker labels before a colon.

        \(trimmedTranscript)
        """

        let completion = try await proxyService.performChatCompletion(
            SpeecharaChatCompletionRequest(
                model: "deepseek-chat",
                messages: [makeSystemMessage()] + historyMessages + [
                    SpeecharaChatMessage(role: "user", content: blockTranscript),
                ],
                temperature: 0,
                maxTokens: 768,
                stream: false
            )
        )

        guard let translation = completion.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !translation.isEmpty else {
            throw DeepSeekTranslationError.invalidResponse
        }

        return translation
    }

    private func processPendingChunks() async {
        defer {
            isProcessingQueue = false
            processingTask = nil
        }

        while let nextChunk = nextPendingChunk() {
            if Task.isCancelled {
                pendingTranscriptChunks.removeAll()
                return
            }

            do {
                let translation = try await requestLiveTranslation(
                    for: nextChunk.transcript,
                    turnID: nextChunk.turnID
                )
                recentHistoryTurns.append(
                    DeepSeekTranslationHistoryTurn(
                        source: nextChunk.transcript,
                        translation: translation
                    )
                )
                recentHistoryTurns = Array(recentHistoryTurns.suffix(maxHistoryTurns))
                eventHandler?(.completed(nextChunk.turnID, translation))
            } catch is CancellationError {
                pendingTranscriptChunks.removeAll()
                return
            } catch let error as DeepSeekTranslationError {
                pendingTranscriptChunks.removeAll()
                eventHandler?(.failed(error.localizedDescription))
                return
            } catch {
                pendingTranscriptChunks.removeAll()
                eventHandler?(.failed(DeepSeekTranslationError.requestFailed(error).localizedDescription))
                return
            }
        }
    }

    private func nextPendingChunk() -> PendingTranslationChunk? {
        guard !pendingTranscriptChunks.isEmpty else {
            return nil
        }

        return pendingTranscriptChunks.removeFirst()
    }

    private func requestLiveTranslation(
        for transcript: String,
        turnID: UUID
    ) async throws -> String {
        guard webSocketTask != nil, translationSocketReady else {
            throw DeepSeekTranslationError.authenticationRequired
        }

        let turnKey = turnID.uuidString

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingTurnContinuations[turnKey] = continuation

                Task { [weak self] in
                    await self?.sendTranslateTurn(
                        transcript: transcript,
                        turnKey: turnKey
                    )
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.failPendingTurn(
                    turnKey,
                    with: CancellationError()
                )
            }
        }
    }

    private func sendTranslateTurn(
        transcript: String,
        turnKey: String
    ) async {
        do {
            try await sendSocketMessage(
                TranslationTurnMessage(
                    type: "translate_turn",
                    turnId: turnKey,
                    transcript: transcript,
                    isFinal: true,
                    sourceLanguage: sourceLanguageCode
                )
            )
        } catch {
            failPendingTurn(turnKey, with: error)
        }
    }

    private func startReceiveLoop(for webSocketTask: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(for: webSocketTask)
        }
    }

    private func startKeepAliveLoop(for webSocketTask: URLSessionWebSocketTask) {
        keepAliveTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await self.sendPing(on: webSocketTask)
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

                await handleSocketFailure(DeepSeekTranslationError.requestFailed(error))
                break
            }
        }
    }

    private func sendPing(on webSocketTask: URLSessionWebSocketTask) async {
        guard !isStopping else {
            return
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                webSocketTask.sendPing { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        } catch {
            await handleSocketFailure(DeepSeekTranslationError.requestFailed(error))
        }
    }

    private func waitForReadySignal() async throws {
        if translationSocketReady {
            return
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.awaitReadySignal()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                throw DeepSeekTranslationError.invalidResponse
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func awaitReadySignal() async throws {
        if translationSocketReady {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
        }
    }

    private func sendSocketMessage<Message: Encodable>(_ payload: Message) async throws {
        guard let webSocketTask else {
            throw DeepSeekTranslationError.authenticationRequired
        }

        let data = try JSONEncoder().encode(payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DeepSeekTranslationError.invalidRequest
        }

        try await webSocketTask.send(.string(text))
    }

    private func handleIncomingTextMessage(_ text: String) async throws {
        guard let data = text.data(using: .utf8) else {
            return
        }

        let envelope = try JSONDecoder().decode(TranslationMessageEnvelope.self, from: data)

        switch envelope.type {
        case "ready":
            translationSocketReady = true
            readyContinuation?.resume()
            readyContinuation = nil
        case "translation_revision":
            let revision = try JSONDecoder().decode(TranslationRevisionMessage.self, from: data)
            guard let turnID = UUID(uuidString: revision.turnId) else {
                return
            }

            let trimmedText = revision.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                return
            }

            if revision.isFinal {
                resumePendingTurn(revision.turnId, with: .success(trimmedText))
            } else {
                eventHandler?(.preview(turnID, trimmedText))
            }
        case "error":
            let errorMessage = (try? JSONDecoder().decode(TranslationSocketErrorMessage.self, from: data))?.message
                ?? "Unknown translation service error."
            throw DeepSeekTranslationError.serverError(errorMessage)
        default:
            return
        }
    }

    private func handleSocketFailure(_ error: Error) async {
        if isStopping {
            return
        }

        let shouldEmitFailure = pendingTurnContinuations.isEmpty && pendingTranscriptChunks.isEmpty
        failReadyIfNeeded(with: error)
        failAllPendingTurns(with: error)

        receiveTask?.cancel()
        keepAliveTask?.cancel()
        receiveTask = nil
        keepAliveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        translationSocketReady = false

        if shouldEmitFailure {
            eventHandler?(.failed(error.localizedDescription))
        }
    }

    private func failReadyIfNeeded(with error: Error) {
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
    }

    private func failAllPendingTurns(with error: Error) {
        let continuations = pendingTurnContinuations.values
        pendingTurnContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func failPendingTurn(_ turnKey: String, with error: Error) {
        guard let continuation = pendingTurnContinuations.removeValue(forKey: turnKey) else {
            return
        }

        continuation.resume(throwing: error)
    }

    private func resumePendingTurn(_ turnKey: String, with result: Result<String, Error>) {
        guard let continuation = pendingTurnContinuations.removeValue(forKey: turnKey) else {
            return
        }

        continuation.resume(with: result)
    }

    private func makeSystemMessage() -> SpeecharaChatMessage {
        SpeecharaChatMessage(
            role: "system",
            content: """
            Translate new live meeting fragments from \(sourceLanguageName) to \(targetLanguageName).
            Use prior translated turns only as short context. Preserve line breaks and any leading timestamps like [12:34].
            If a line starts with a speaker label before a colon, preserve the label and translate only the spoken content.
            Return only the translated fragment in \(targetLanguageName), with no commentary.
            """
        )
    }

    private func mergedTranscriptChunk(existing: String, addition: String) -> String {
        let trimmedExisting = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddition = addition.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedExisting.isEmpty else {
            return trimmedAddition
        }

        guard !trimmedAddition.isEmpty else {
            return trimmedExisting
        }

        let joinsWithoutSpace = trimmedAddition.first.map {
            [".", ",", "!", "?", ":", ";", "…"].contains(String($0))
        } ?? false

        if joinsWithoutSpace || trimmedExisting.hasSuffix(" ") {
            return "\(trimmedExisting)\(trimmedAddition)"
        }

        return "\(trimmedExisting) \(trimmedAddition)"
    }
}

private struct PendingTranslationChunk {
    let turnID: UUID
    var transcript: String
}

private struct TranslationMessageEnvelope: Decodable {
    let type: String
}

private struct TranslationConfigureMessage: Encodable {
    let type: String
    let sessionId: String
    let sourceLanguage: String
    let targetLanguage: String
}

private struct TranslationTurnMessage: Encodable {
    let type: String
    let turnId: String
    let transcript: String
    let isFinal: Bool
    let sourceLanguage: String
}

private struct TranslationRevisionMessage: Decodable {
    let type: String
    let turnId: String
    let revision: Int
    let text: String
    let isFinal: Bool
    let targetLanguage: String?
}

private struct TranslationSocketErrorMessage: Decodable {
    let type: String
    let message: String?
}
