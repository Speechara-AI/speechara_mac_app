import Foundation
import OSLog

enum DeepSeekTranslationError: LocalizedError {
    case authenticationRequired
    case invalidRequest
    case invalidResponse
    case requestFailed(Error)
    case serverError(String)
    case alreadyConnected
    case timedOut

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
        case .timedOut:
            return "Live translation did not respond in time."
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
    private static let maxLiveTranslationAttempts = 1
    // Mirrors the web client: never let a lost backend response block the live queue forever.
    private static let liveTranslationTurnTimeoutNanoseconds: UInt64 = 8_000_000_000
    private static let diagnosticsInterval: TimeInterval = 5
    private static let logger = Logger(subsystem: "ai.speechara.mac", category: "DeepSeekTranslation")
    private static let reconnectDelayNanoseconds: [UInt64] = [
        400_000_000,
        1_200_000_000,
        2_500_000_000,
    ]

    private let maxHistoryTurns = 4
    private let session: URLSession
    private let proxyService: SpeecharaBackendProxyService

    private var sourceLanguageName = ""
    private var targetLanguageName = ""
    private var sourceLanguageCode = ""
    private var targetLanguageCode = ""
    private var recentHistoryTurns: [DeepSeekTranslationHistoryTurn] = []
    private var pendingTranscriptChunks: [PendingTranslationChunk] = []
    private var shouldDispatchLiveChunkNext = true
    private var isProcessingQueue = false
    private var processingTask: Task<Void, Never>?
    private var eventHandler: (@Sendable (DeepSeekTranslationEvent) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var pendingTurnContinuations = [String: PendingTranslationContinuation]()
    private var latestTranslationRevisionByTurn = [String: Int]()
    private var finalizedTranslationTurnIDs = Set<String>()
    private var translationSocketReady = false
    private var isStopping = false
    private var liveSessionID = UUID().uuidString
    private var lastDiagnosticsLogDate = Date()
    private var enqueuedChunkCount = 0
    private var completedChunkCount = 0
    private var droppedChunkCount = 0
    private var maxPendingChunkCount = 0
    private var translationDurationTotalMilliseconds = 0.0
    private var translationDurationSampleCount = 0

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
        shouldDispatchLiveChunkNext = true
        latestTranslationRevisionByTurn = [:]
        finalizedTranslationTurnIDs = []
        isProcessingQueue = false
        processingTask?.cancel()
        processingTask = nil
        translationSocketReady = false
        isStopping = false
        liveSessionID = UUID().uuidString
        resetDiagnostics()

        do {
            try await establishTranslationSocket()
        } catch {
            await resetSession()
            throw error
        }
    }

    func enqueueInterimChunk(_ transcript: String, turnID: UUID) {
        enqueueChunk(transcript, turnID: turnID, isFinal: false)
    }

    func enqueueFinalChunk(_ transcript: String, turnID: UUID) {
        enqueueChunk(transcript, turnID: turnID, isFinal: true)
    }

    private func enqueueChunk(_ transcript: String, turnID: UUID, isFinal: Bool) {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return
        }

        if let existingIndex = pendingTranscriptChunks.lastIndex(where: { $0.turnID == turnID }) {
            pendingTranscriptChunks[existingIndex].transcript = trimmedTranscript
            pendingTranscriptChunks[existingIndex].isFinal = pendingTranscriptChunks[existingIndex].isFinal || isFinal
        } else {
            pendingTranscriptChunks.append(
                PendingTranslationChunk(turnID: turnID, transcript: trimmedTranscript, isFinal: isFinal)
            )
        }

        enqueuedChunkCount += 1
        maxPendingChunkCount = max(maxPendingChunkCount, pendingTranscriptChunks.count)

        logDiagnosticsIfNeeded(reason: "enqueue")
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
        shouldDispatchLiveChunkNext = true
        latestTranslationRevisionByTurn.removeAll()
        finalizedTranslationTurnIDs.removeAll()
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
        resetDiagnostics()
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
                let startedAt = Date()
                let translation = try await requestLiveTranslationWithReconnect(
                    for: nextChunk.transcript,
                    turnID: nextChunk.turnID,
                    isFinal: nextChunk.isFinal
                )
                let elapsedMilliseconds = Date().timeIntervalSince(startedAt) * 1_000
                completedChunkCount += 1
                translationDurationTotalMilliseconds += elapsedMilliseconds
                translationDurationSampleCount += 1
                if nextChunk.isFinal {
                    recentHistoryTurns.append(
                        DeepSeekTranslationHistoryTurn(
                            source: nextChunk.transcript,
                            translation: translation
                        )
                    )
                    recentHistoryTurns = Array(recentHistoryTurns.suffix(maxHistoryTurns))
                    eventHandler?(.completed(nextChunk.turnID, translation))
                } else {
                    eventHandler?(.preview(nextChunk.turnID, translation))
                }
                logDiagnosticsIfNeeded(reason: "completed")
            } catch is CancellationError {
                pendingTranscriptChunks.removeAll()
                return
            } catch DeepSeekTranslationError.timedOut where !nextChunk.isFinal {
                // A draft is disposable because a newer draft for the same turn is already
                // queued (or will arrive shortly). Reconnecting lets that newest text through.
                droppedChunkCount += 1
                Self.logger.warning(
                    "Dropped stalled interim translation turnId=\(nextChunk.turnID.uuidString, privacy: .public)"
                )
                logDiagnosticsIfNeeded(reason: "interim-timeout")
                continue
            } catch let error as DeepSeekTranslationError where isRecoverableTranslationError(error) {
                // A temporary backend or network failure must never pause translation for
                // the user. Keep the completed turn for a later retry and let newer live
                // text take priority as soon as it arrives.
                requeueForRecovery(nextChunk)
                Self.logger.warning(
                    "Retrying live translation after recoverable error=\(error.localizedDescription, privacy: .public)"
                )
                try? await Task.sleep(nanoseconds: Self.reconnectDelayNanoseconds[0])
                continue
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

        let newestLiveIndex = pendingTranscriptChunks.lastIndex(where: { !$0.isFinal })
        let newestFinalIndex = pendingTranscriptChunks.lastIndex(where: \.isFinal)

        // Keep two independent priorities on the single live connection. A preview must
        // remain current, while a completed phrase must not be starved by ongoing speech.
        // Alternating the lanes bounds both delays to one model request.
        let nextIndex: Int
        if shouldDispatchLiveChunkNext, let newestLiveIndex {
            nextIndex = newestLiveIndex
            shouldDispatchLiveChunkNext = false
        } else if let newestFinalIndex {
            nextIndex = newestFinalIndex
            shouldDispatchLiveChunkNext = true
        } else if let newestLiveIndex {
            nextIndex = newestLiveIndex
            shouldDispatchLiveChunkNext = false
        } else {
            return nil
        }

        return pendingTranscriptChunks.remove(at: nextIndex)
    }

    private func requeueForRecovery(_ chunk: PendingTranslationChunk) {
        if let index = pendingTranscriptChunks.lastIndex(where: { $0.turnID == chunk.turnID }) {
            pendingTranscriptChunks[index].transcript = chunk.transcript
            pendingTranscriptChunks[index].isFinal = pendingTranscriptChunks[index].isFinal || chunk.isFinal
        } else {
            pendingTranscriptChunks.insert(chunk, at: 0)
        }
    }

    private func resetDiagnostics() {
        lastDiagnosticsLogDate = Date()
        enqueuedChunkCount = 0
        completedChunkCount = 0
        droppedChunkCount = 0
        maxPendingChunkCount = 0
        translationDurationTotalMilliseconds = 0
        translationDurationSampleCount = 0
    }

    private func logDiagnosticsIfNeeded(reason: String) {
        let now = Date()
        guard now.timeIntervalSince(lastDiagnosticsLogDate) >= Self.diagnosticsInterval else {
            return
        }

        let averageTranslationMilliseconds = translationDurationSampleCount > 0
            ? translationDurationTotalMilliseconds / Double(translationDurationSampleCount)
            : 0

        Self.logger.info(
            "Translation queue diagnostics reason=\(reason, privacy: .public) pendingChunks=\(self.pendingTranscriptChunks.count, privacy: .public) maxPendingChunks=\(self.maxPendingChunkCount, privacy: .public) enqueued=\(self.enqueuedChunkCount, privacy: .public) completed=\(self.completedChunkCount, privacy: .public) dropped=\(self.droppedChunkCount, privacy: .public) avgTranslationMs=\(averageTranslationMilliseconds, privacy: .public)"
        )

        lastDiagnosticsLogDate = now
        enqueuedChunkCount = 0
        completedChunkCount = 0
        droppedChunkCount = 0
        maxPendingChunkCount = pendingTranscriptChunks.count
        translationDurationTotalMilliseconds = 0
        translationDurationSampleCount = 0
    }

    private func requestLiveTranslationWithReconnect(
        for transcript: String,
        turnID: UUID,
        isFinal: Bool
    ) async throws -> String {
        var attempt = 0
        var lastError: Error?

        while attempt < Self.maxLiveTranslationAttempts {
            if Task.isCancelled {
                throw CancellationError()
            }

            do {
                try await ensureTranslationSocketReady()
                return try await requestLiveTranslationWithTimeout(
                    for: transcript,
                    turnID: turnID,
                    isFinal: isFinal
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch DeepSeekTranslationError.timedOut {
                // The server can keep a WebSocket open after its upstream model stalls.
                // Discard an obsolete preview; preserve a final turn by retrying it below.
                await closeSocketForReconnect()
                guard isFinal else {
                    throw DeepSeekTranslationError.timedOut
                }

                lastError = DeepSeekTranslationError.timedOut
                attempt += 1

                guard attempt < Self.maxLiveTranslationAttempts else {
                    throw DeepSeekTranslationError.timedOut
                }

                let delayIndex = min(attempt - 1, Self.reconnectDelayNanoseconds.count - 1)
                try await Task.sleep(nanoseconds: Self.reconnectDelayNanoseconds[delayIndex])
            } catch {
                lastError = error
                attempt += 1

                // Do not reuse a socket that has already failed a request. The outer
                // recovery loop will keep the session alive and dispatch fresh text.
                await closeSocketForReconnect()

                guard attempt < Self.maxLiveTranslationAttempts,
                      isRecoverableTranslationError(error) else {
                    throw error
                }

                let delayIndex = min(attempt - 1, Self.reconnectDelayNanoseconds.count - 1)
                try await Task.sleep(nanoseconds: Self.reconnectDelayNanoseconds[delayIndex])
            }
        }

        throw lastError ?? DeepSeekTranslationError.invalidResponse
    }

    private func ensureTranslationSocketReady() async throws {
        guard webSocketTask == nil || !translationSocketReady else {
            return
        }

        await closeSocketForReconnect()
        try await establishTranslationSocket()
    }

    private func establishTranslationSocket() async throws {
        guard webSocketTask == nil else {
            return
        }

        translationSocketReady = false

        let request = try await makeLiveTranslationWebSocketRequest()
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
            await closeSocketForReconnect()
            throw error
        }
    }

    private func makeLiveTranslationWebSocketRequest() async throws -> URLRequest {
        do {
            return try await proxyService.makeWebSocketRequest(path: "/api/ai/translation/live")
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
    }

    private func isRecoverableTranslationError(_ error: Error) -> Bool {
        guard let translationError = error as? DeepSeekTranslationError else {
            return true
        }

        switch translationError {
        case .requestFailed, .invalidResponse, .serverError, .timedOut:
            return true
        case .authenticationRequired, .invalidRequest, .alreadyConnected:
            return false
        }
    }

    private func closeSocketForReconnect() async {
        isStopping = true

        failReadyIfNeeded(with: DeepSeekTranslationError.requestFailed(CancellationError()))
        failAllPendingTurns(with: DeepSeekTranslationError.requestFailed(CancellationError()))

        receiveTask?.cancel()
        keepAliveTask?.cancel()
        receiveTask = nil
        keepAliveTask = nil

        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
        self.webSocketTask = nil
        translationSocketReady = false
        isStopping = false
    }

    private func requestLiveTranslation(
        for transcript: String,
        turnID: UUID,
        isFinal: Bool
    ) async throws -> String {
        guard webSocketTask != nil, translationSocketReady else {
            throw DeepSeekTranslationError.requestFailed(URLError(.networkConnectionLost))
        }

        let turnKey = turnID.uuidString

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingTurnContinuations[turnKey] = PendingTranslationContinuation(
                    continuation: continuation,
                    expectsFinalRevision: isFinal
                )

                Task { [weak self] in
                    await self?.sendTranslateTurn(
                        transcript: transcript,
                        turnKey: turnKey,
                        isFinal: isFinal
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

    private func requestLiveTranslationWithTimeout(
        for transcript: String,
        turnID: UUID,
        isFinal: Bool
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.requestLiveTranslation(
                    for: transcript,
                    turnID: turnID,
                    isFinal: isFinal
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.liveTranslationTurnTimeoutNanoseconds)
                throw DeepSeekTranslationError.timedOut
            }

            defer {
                group.cancelAll()
            }

            guard let result = try await group.next() else {
                throw DeepSeekTranslationError.invalidResponse
            }
            return result
        }
    }

    private func sendTranslateTurn(
        transcript: String,
        turnKey: String,
        isFinal: Bool
    ) async {
        do {
            try await sendSocketMessage(
                TranslationTurnMessage(
                    type: "translate_turn",
                    turnId: turnKey,
                    transcript: transcript,
                    isFinal: isFinal,
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

                await handleSocketFailure(
                    DeepSeekTranslationError.requestFailed(error),
                    for: webSocketTask
                )
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
            await handleSocketFailure(
                DeepSeekTranslationError.requestFailed(error),
                for: webSocketTask
            )
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
            guard UUID(uuidString: revision.turnId) != nil else {
                return
            }

            let trimmedText = revision.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                return
            }

            let previousRevision = latestTranslationRevisionByTurn[revision.turnId] ?? 0
            guard revision.revision > previousRevision,
                  !finalizedTranslationTurnIDs.contains(revision.turnId) else {
                return
            }
            latestTranslationRevisionByTurn[revision.turnId] = revision.revision

            if revision.isFinal {
                finalizedTranslationTurnIDs.insert(revision.turnId)
                resumePendingTurn(revision.turnId, with: .success(trimmedText))
            } else {
                resumePendingInterimTurnIfNeeded(revision.turnId, with: trimmedText)
            }
        case "error":
            let errorMessage = (try? JSONDecoder().decode(TranslationSocketErrorMessage.self, from: data))?.message
                ?? "Unknown translation service error."
            throw DeepSeekTranslationError.serverError(errorMessage)
        default:
            return
        }
    }

    private func handleSocketFailure(
        _ error: Error,
        for webSocketTask: URLSessionWebSocketTask
    ) async {
        if isStopping {
            return
        }

        guard let currentWebSocketTask = self.webSocketTask,
              currentWebSocketTask === webSocketTask else {
            return
        }

        failReadyIfNeeded(with: error)
        failAllPendingTurns(with: error)

        receiveTask?.cancel()
        keepAliveTask?.cancel()
        receiveTask = nil
        keepAliveTask = nil
        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
        self.webSocketTask = nil
        translationSocketReady = false
    }

    private func failReadyIfNeeded(with error: Error) {
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
    }

    private func failAllPendingTurns(with error: Error) {
        let continuations = pendingTurnContinuations.values
        pendingTurnContinuations.removeAll()
        for pending in continuations {
            pending.continuation.resume(throwing: error)
        }
    }

    private func failPendingTurn(_ turnKey: String, with error: Error) {
        guard let pending = pendingTurnContinuations.removeValue(forKey: turnKey) else {
            return
        }

        pending.continuation.resume(throwing: error)
    }

    private func resumePendingTurn(_ turnKey: String, with result: Result<String, Error>) {
        guard let pending = pendingTurnContinuations.removeValue(forKey: turnKey) else {
            return
        }

        pending.continuation.resume(with: result)
    }

    private func resumePendingInterimTurnIfNeeded(_ turnKey: String, with translation: String) {
        guard let pending = pendingTurnContinuations[turnKey],
              !pending.expectsFinalRevision else {
            return
        }

        pendingTurnContinuations.removeValue(forKey: turnKey)
        pending.continuation.resume(returning: translation)
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
    var isFinal: Bool
}

private struct PendingTranslationContinuation {
    let continuation: CheckedContinuation<String, Error>
    let expectsFinalRevision: Bool
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
