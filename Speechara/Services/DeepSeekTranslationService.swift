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
    private static let maxLiveTranslationAttempts = 2
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
        SpeecharaDiagnostics.translation.notice("startSession requested source=\(sourceLanguageCode) target=\(targetLanguageCode)")
        guard webSocketTask == nil else {
            SpeecharaDiagnostics.translation.error("startSession rejected: websocket already exists")
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
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return
        }

        // Live drafts are revisions of one turn, not durable queue items. Sending them
        // immediately prevents an obsolete draft from blocking the newest text for 8s.
        if webSocketTask != nil, translationSocketReady {
            enqueuedChunkCount += 1
            Task { [weak self] in
                await self?.sendInterimRevisionImmediately(trimmedTranscript, turnID: turnID)
            }
            return
        }

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

    private func sendInterimRevisionImmediately(_ transcript: String, turnID: UUID) async {
        do {
            try await sendSocketMessage(
                TranslationTurnMessage(
                    type: "translate_turn",
                    turnId: turnID.uuidString,
                    transcript: transcript,
                    isFinal: false,
                    sourceLanguage: sourceLanguageCode
                )
            )
        } catch {
            droppedChunkCount += 1
            SpeecharaDiagnostics.translation.warning(
                "live interim send failed turn=\(turnID.uuidString) error=\(error.localizedDescription)"
            )
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
                    try await handleIncomingTextMessage(text, from: webSocketTask)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        try await handleIncomingTextMessage(text, from: webSocketTask)
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

    private func handleIncomingTextMessage(
        _ text: String,
        from sourceWebSocketTask: URLSessionWebSocketTask
    ) async throws {
        guard let currentWebSocketTask = webSocketTask,
              currentWebSocketTask === sourceWebSocketTask else {
            SpeecharaDiagnostics.translation.debug("ignored message from stale websocket bytes=\(text.utf8.count)")
            return
        }

        SpeecharaDiagnostics.translation.debug("incoming message bytes=\(text.utf8.count) summary=\(SpeecharaDiagnostics.textSummary(text))")
        guard let data = text.data(using: .utf8) else {
            return
        }

        let envelope = try JSONDecoder().decode(TranslationMessageEnvelope.self, from: data)

        switch envelope.type {
        case "ready":
            SpeecharaDiagnostics.translation.notice("socket ready session=\(self.liveSessionID)")
            translationSocketReady = true
            readyContinuation?.resume()
            readyContinuation = nil
        case "translation_revision":
            let revision = try JSONDecoder().decode(TranslationRevisionMessage.self, from: data)
            guard UUID(uuidString: revision.turnId) != nil else {
                SpeecharaDiagnostics.translation.error("ignored revision with invalid turnId=\(revision.turnId)")
                return
            }

            let trimmedText = revision.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                SpeecharaDiagnostics.translation.error("ignored empty translation revision turn=\(revision.turnId) revision=\(revision.revision)")
                return
            }

            let previousRevision = latestTranslationRevisionByTurn[revision.turnId] ?? 0
            guard revision.revision > previousRevision,
                  !finalizedTranslationTurnIDs.contains(revision.turnId) else {
                SpeecharaDiagnostics.translation.error("ignored stale/finalized revision turn=\(revision.turnId) revision=\(revision.revision) previous=\(previousRevision) finalized=\(self.finalizedTranslationTurnIDs.contains(revision.turnId))")
                return
            }
            latestTranslationRevisionByTurn[revision.turnId] = revision.revision

            if revision.isFinal {
                finalizedTranslationTurnIDs.insert(revision.turnId)
                resumePendingTurn(revision.turnId, with: .success(trimmedText))
            } else {
                eventHandler?(.preview(UUID(uuidString: revision.turnId)!, trimmedText))
                resumePendingInterimTurnIfNeeded(revision.turnId, with: trimmedText)
            }
        case "error":
            let errorMessage = (try? JSONDecoder().decode(TranslationSocketErrorMessage.self, from: data))?.message
                ?? "Unknown translation service error."
            SpeecharaDiagnostics.translation.error("backend error message=\(errorMessage)")
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
            SpeecharaDiagnostics.translation.debug("socket failure ignored during intentional stop error=\(error.localizedDescription)")
            return
        }

        SpeecharaDiagnostics.translation.error("socket failure error=\(error.localizedDescription) pendingTurns=\(self.pendingTurnContinuations.count)")

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

// MARK: - Durable live translation protocol v2

private enum TranslationV2WebSocketOpenError: LocalizedError {
    case timedOut
    case closed(URLSessionWebSocketTask.CloseCode, String?)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "The v2 translation WebSocket upgrade did not complete in time."
        case .closed(let code, let reason):
            if let reason, !reason.isEmpty {
                return "The v2 translation WebSocket closed during setup (code \(code.rawValue)): \(reason)"
            }
            return "The v2 translation WebSocket closed during setup (code \(code.rawValue))."
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

private final class TranslationV2WebSocketOpenObserver: NSObject, URLSessionWebSocketDelegate, URLSessionTaskDelegate {
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

    func waitForOpen(taskIdentifier: Int, timeout: TimeInterval = 4) async throws {
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
                    with: .failure(TranslationV2WebSocketOpenError.timedOut)
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
            with: .failure(TranslationV2WebSocketOpenError.closed(closeCode, reasonText))
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
            with: .failure(TranslationV2WebSocketOpenError.transport(error))
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

actor SpeecharaLiveTranslationV2Service {
    private static let logger = Logger(subsystem: "ai.speechara.mac", category: "TranslationV2")
    private static let emergencyPreviewDebounceNanoseconds: UInt64 = 180_000_000
    private static let reconnectDelays: [UInt64] = [
        250_000_000,
        750_000_000,
        2_000_000_000,
        5_000_000_000,
    ]

    private let session: URLSession
    private let webSocketOpenObserver: TranslationV2WebSocketOpenObserver?
    private let proxyService: SpeecharaBackendProxyService
    private let legacyFallbackService: DeepSeekTranslationService
    private var sourceLanguageCode = ""
    private var sourceLanguageName = ""
    private var targetLanguageCode = ""
    private var targetLanguageName = ""
    private var eventHandler: (@Sendable (DeepSeekTranslationEvent) -> Void)?

    private var logicalSessionID = UUID().uuidString
    private var connectionID: String?
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var helloContinuation: CheckedContinuation<Void, Error>?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var receivedHello = false
    private var isReady = false
    private var hasConfiguredSession = false
    private var isStopping = false
    private var isUsingLegacyFallback = false

    private var clientRevisionByTurn = [String: Int]()
    private var latestPreviewByTurn = [String: String]()
    private var previewInFlightRevisionByTurn = [String: Int]()
    private var lastSentPreviewTextByTurn = [String: String]()
    private var finalizedTurnIDs = Set<String>()
    private var pendingFinals = [String: V2PendingFinal]()
    private var nextPendingFinalSequence = 0
    private var emergencyPreviewTask: Task<Void, Never>?
    private var emergencyPreviewGeneration = 0
    private var emergencyPreviewTurnID: String?
    private var emergencyHistory: [DeepSeekTranslationHistoryTurn] = []
    private var emergencyFinalTask: Task<Void, Never>?
    private var emergencyFinalTurnID: String?
    private var emergencyFinalAttempts = [String: Int]()
    private var emergencyCompletedFinalTurnIDs = Set<String>()

    init(
        session: URLSession? = nil,
        proxyService: SpeecharaBackendProxyService = SpeecharaBackendProxyService(),
        legacyFallbackService: DeepSeekTranslationService = DeepSeekTranslationService()
    ) {
        if let session {
            self.session = session
            self.webSocketOpenObserver = nil
        } else {
            let observer = TranslationV2WebSocketOpenObserver()
            self.webSocketOpenObserver = observer
            self.session = URLSession(configuration: .default, delegate: observer, delegateQueue: nil)
        }
        self.proxyService = proxyService
        self.legacyFallbackService = legacyFallbackService
    }

    func startSession(
        sourceLanguageCode: String,
        sourceLanguageName: String,
        targetLanguageCode: String,
        targetLanguageName: String,
        eventHandler: @escaping @Sendable (DeepSeekTranslationEvent) -> Void
    ) async throws {
        let sourceCode = sourceLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetCode = targetLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines)

        if (isReady || webSocketTask != nil || reconnectTask != nil || isUsingLegacyFallback),
           self.sourceLanguageCode == sourceCode,
           self.targetLanguageCode == targetCode {
            self.eventHandler = eventHandler
            return
        }

        guard webSocketTask == nil else {
            throw DeepSeekTranslationError.alreadyConnected
        }

        self.sourceLanguageCode = sourceCode
        self.sourceLanguageName = sourceLanguageName
        self.targetLanguageCode = targetCode
        self.targetLanguageName = targetLanguageName
        self.eventHandler = eventHandler
        logicalSessionID = UUID().uuidString
        connectionID = nil
        clientRevisionByTurn.removeAll()
        latestPreviewByTurn.removeAll()
        previewInFlightRevisionByTurn.removeAll()
        lastSentPreviewTextByTurn.removeAll()
        finalizedTurnIDs.removeAll()
        pendingFinals.removeAll()
        nextPendingFinalSequence = 0
        cancelEmergencyPreviews()
        cancelEmergencyFinalTask()
        emergencyHistory.removeAll()
        emergencyFinalAttempts.removeAll()
        emergencyCompletedFinalTurnIDs.removeAll()
        hasConfiguredSession = false
        isStopping = false
        isUsingLegacyFallback = false

        Self.logger.notice(
            "starting v2 session id=\(self.logicalSessionID, privacy: .public) source=\(sourceCode, privacy: .public) target=\(targetCode, privacy: .public)"
        )
        // Translation readiness must never delay audio capture. From this point on,
        // previews and finals are accepted into the local latest-wins/durable queues;
        // the reconnect loop flushes them as soon as the server confirms `ready`.
        // Do not silently fall back to v1: its FIFO revisions are exactly what makes
        // the visible translation drift behind the current conversation.
        scheduleReconnectIfNeeded()
    }

    func enqueueInterimChunk(_ transcript: String, turnID: UUID) async {
        if isUsingLegacyFallback {
            await legacyFallbackService.enqueueInterimChunk(transcript, turnID: turnID)
            return
        }

        let sourceText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            return
        }

        let turnKey = turnID.uuidString
        guard !finalizedTurnIDs.contains(turnKey) else {
            return
        }

        latestPreviewByTurn[turnKey] = sourceText

        guard isReady else {
            scheduleEmergencyPreview(for: turnKey)
            scheduleReconnectIfNeeded()
            return
        }

        do {
            try await sendLatestPreviewIfNeeded(turnID: turnKey)
        } catch {
            Self.logger.warning(
                "preview send failed turn=\(turnKey, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            socketDidFail(error)
        }
    }

    func enqueueFinalChunk(_ transcript: String, turnID: UUID) async {
        if isUsingLegacyFallback {
            await legacyFallbackService.enqueueFinalChunk(transcript, turnID: turnID)
            return
        }

        let sourceText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            return
        }

        let turnKey = turnID.uuidString
        guard !finalizedTurnIDs.contains(turnKey) else {
            return
        }

        latestPreviewByTurn.removeValue(forKey: turnKey)
        previewInFlightRevisionByTurn.removeValue(forKey: turnKey)
        lastSentPreviewTextByTurn.removeValue(forKey: turnKey)
        let revision = nextRevision(for: turnKey)
        let enqueueSequence = nextPendingFinalSequence
        nextPendingFinalSequence += 1
        pendingFinals[turnKey] = V2PendingFinal(
            turnID: turnKey,
            clientRevision: revision,
            sourceText: sourceText,
            enqueueSequence: enqueueSequence,
            acknowledged: false
        )

        guard isReady else {
            cancelEmergencyPreview(for: turnKey)
            scheduleEmergencyFinalIfNeeded()
            scheduleReconnectIfNeeded()
            return
        }

        do {
            try await sendFinal(pendingFinals[turnKey]!)
        } catch {
            Self.logger.warning(
                "final send failed turn=\(turnKey, privacy: .public) revision=\(revision, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            socketDidFail(error)
        }
    }

    func replaceHistory(with turns: [DeepSeekTranslationHistoryTurn]) async {
        emergencyHistory = Array(turns.suffix(4))
        if isUsingLegacyFallback {
            await legacyFallbackService.replaceHistory(with: turns)
        }
        // v2 owns context durably and builds it only from completed final turns.
    }

    func resetSession() async {
        guard webSocketTask != nil || reconnectTask != nil || isReady || isUsingLegacyFallback else {
            return
        }

        isStopping = true
        await legacyFallbackService.resetSession()
        isUsingLegacyFallback = false
        reconnectTask?.cancel()
        reconnectTask = nil

        if isReady {
            try? await sendMessage(V2CompleteSessionMessage(type: "complete_session", sessionId: logicalSessionID))
        }

        failHandshakeContinuations(with: CancellationError())
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isReady = false
        receivedHello = false
        connectionID = nil
        eventHandler = nil
        pendingFinals.removeAll()
        latestPreviewByTurn.removeAll()
        previewInFlightRevisionByTurn.removeAll()
        lastSentPreviewTextByTurn.removeAll()
        finalizedTurnIDs.removeAll()
        clientRevisionByTurn.removeAll()
        nextPendingFinalSequence = 0
        cancelEmergencyPreviews()
        cancelEmergencyFinalTask()
        emergencyHistory.removeAll()
        emergencyFinalAttempts.removeAll()
        emergencyCompletedFinalTurnIDs.removeAll()
        hasConfiguredSession = false
        isStopping = false
    }

    func translateStableBlock(
        _ transcript: String,
        history: [DeepSeekTranslationHistoryTurn]
    ) async throws -> String {
        let sourceText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            throw DeepSeekTranslationError.invalidResponse
        }

        let historyMessages = history.suffix(4).flatMap { turn -> [SpeecharaChatMessage] in
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

        let completion = try await proxyService.performChatCompletion(
            SpeecharaChatCompletionRequest(
                model: "deepseek-chat",
                messages: [
                    SpeecharaChatMessage(
                        role: "system",
                        content: "Translate from \(sourceLanguageName) to \(targetLanguageName). Preserve timestamps, speaker labels, and line order. Return only the translation."
                    ),
                ] + historyMessages + [
                    SpeecharaChatMessage(role: "user", content: sourceText),
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

    private func establishSocket(resume: Bool) async throws {
        guard webSocketTask == nil else {
            return
        }

        receivedHello = false
        isReady = false
        let request = try await makeRequest()
        if let url = request.url {
            Self.logger.notice(
                "opening v2 websocket scheme=\(url.scheme ?? "", privacy: .public) host=\(url.host ?? "", privacy: .public) path=\(url.path, privacy: .public) resume=\(resume, privacy: .public)"
            )
        }
        let socket = session.webSocketTask(with: request)
        webSocketOpenObserver?.prepare(for: socket.taskIdentifier)
        webSocketTask = socket
        socket.resume()

        do {
            try await webSocketOpenObserver?.waitForOpen(taskIdentifier: socket.taskIdentifier)
            Self.logger.notice("v2 websocket upgrade completed task=\(socket.taskIdentifier, privacy: .public)")
            startReceiveLoop(for: socket)

            // Follow the protocol lifecycle strictly: hello -> configure/resume ->
            // ready. This also removes a race with the server registering its
            // connection state immediately after the WebSocket upgrade.
            try await waitForHello()
            if resume && hasConfiguredSession {
                try await sendResume()
            } else {
                try await sendConfigure()
            }
            Self.logger.notice("v2 configure sent; waiting for ready")
            try await waitForReady()
            try await flushPendingWork()
        } catch {
            Self.logger.error(
                "v2 websocket setup failed task=\(socket.taskIdentifier, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            closeCurrentSocket()
            throw error
        }
    }

    private func makeRequest() async throws -> URLRequest {
        do {
            return try await proxyService.makeWebSocketRequest(path: "/api/v2/ai/translation/live")
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

    private func sendConfigure() async throws {
        try await sendMessage(
            V2ConfigureMessage(
                type: "configure",
                protocolVersion: 2,
                sessionId: logicalSessionID,
                sourceLanguage: sourceLanguageCode,
                targetLanguage: targetLanguageCode
            )
        )
    }

    private func sendResume() async throws {
        let finals = pendingFinals.values.sorted(by: { $0.enqueueSequence < $1.enqueueSequence }).map {
            V2PendingFinalReference(turnId: $0.turnID, clientRevision: $0.clientRevision)
        }
        try await sendMessage(
            V2ResumeMessage(
                type: "resume",
                protocolVersion: 2,
                sessionId: logicalSessionID,
                sourceLanguage: sourceLanguageCode,
                targetLanguage: targetLanguageCode,
                pendingFinals: finals
            )
        )
    }

    private func sendPreview(turnID: String, revision: Int, sourceText: String) async throws {
        try await sendMessage(
            V2PreviewMessage(
                type: "translate_preview",
                sessionId: logicalSessionID,
                turnId: turnID,
                clientRevision: revision,
                sourceText: sourceText
            )
        )
    }

    private func sendLatestPreviewIfNeeded(turnID: String) async throws {
        guard isReady,
              !finalizedTurnIDs.contains(turnID),
              pendingFinals[turnID] == nil,
              previewInFlightRevisionByTurn[turnID] == nil,
              let sourceText = latestPreviewByTurn[turnID],
              !sourceText.isEmpty,
              lastSentPreviewTextByTurn[turnID] != sourceText else {
            return
        }

        let revision = nextRevision(for: turnID)
        previewInFlightRevisionByTurn[turnID] = revision
        lastSentPreviewTextByTurn[turnID] = sourceText
        try await sendPreview(turnID: turnID, revision: revision, sourceText: sourceText)
    }

    private func sendFinal(_ final: V2PendingFinal) async throws {
        try await sendMessage(
            V2FinalMessage(
                type: "translate_final",
                sessionId: logicalSessionID,
                turnId: final.turnID,
                clientRevision: final.clientRevision,
                sourceText: final.sourceText
            )
        )
    }

    private func flushPendingWork() async throws {
        for final in pendingFinals.values.sorted(by: { $0.enqueueSequence < $1.enqueueSequence }) {
            try await sendFinal(final)
        }
        for turnID in latestPreviewByTurn.keys.sorted() where !finalizedTurnIDs.contains(turnID) {
            try await sendLatestPreviewIfNeeded(turnID: turnID)
        }
    }

    private func startReceiveLoop(for socket: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(from: socket)
        }
    }

    private func receiveLoop(from socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                let text: String?
                switch message {
                case .string(let value):
                    text = value
                case .data(let data):
                    text = String(data: data, encoding: .utf8)
                @unknown default:
                    text = nil
                }
                if let text {
                    try await handleMessage(text, from: socket)
                }
            } catch {
                guard !isStopping, !Task.isCancelled else {
                    return
                }
                guard webSocketTask === socket else {
                    return
                }
                Self.logger.error("v2 receive failed error=\(error.localizedDescription, privacy: .public)")
                socketDidFail(error)
                return
            }
        }
    }

    private func handleMessage(_ text: String, from socket: URLSessionWebSocketTask) async throws {
        guard webSocketTask === socket else {
            Self.logger.debug("ignored v2 message from stale socket")
            return
        }
        guard let data = text.data(using: .utf8) else {
            return
        }
        let envelope = try JSONDecoder().decode(V2Envelope.self, from: data)

        switch envelope.type {
        case "hello":
            let hello = try JSONDecoder().decode(V2HelloMessage.self, from: data)
            connectionID = hello.connectionId
            receivedHello = true
            helloContinuation?.resume()
            helloContinuation = nil
            Self.logger.notice("v2 hello connection=\(hello.connectionId, privacy: .public)")
        case "ready":
            let ready = try JSONDecoder().decode(V2ReadyMessage.self, from: data)
            guard ready.sessionId == logicalSessionID else {
                return
            }
            connectionID = ready.connectionId
            isReady = true
            hasConfiguredSession = true
            cancelEmergencyPreviews()
            cancelEmergencyFinalTask()
            readyContinuation?.resume()
            readyContinuation = nil
            Self.logger.notice(
                "v2 ready session=\(ready.sessionId, privacy: .public) connection=\(ready.connectionId, privacy: .public) resumed=\(ready.resumed, privacy: .public)"
            )
        case "preview_ack":
            let ack = try JSONDecoder().decode(V2AckMessage.self, from: data)
            Self.logger.debug(
                "preview ack turn=\(ack.turnId, privacy: .public) revision=\(ack.clientRevision, privacy: .public) status=\(ack.status, privacy: .public)"
            )
        case "final_ack":
            let ack = try JSONDecoder().decode(V2AckMessage.self, from: data)
            if var pending = pendingFinals[ack.turnId], pending.clientRevision == ack.clientRevision {
                pending.acknowledged = true
                pendingFinals[ack.turnId] = pending
            }
            Self.logger.notice(
                "final ack turn=\(ack.turnId, privacy: .public) revision=\(ack.clientRevision, privacy: .public) status=\(ack.status, privacy: .public)"
            )
        case "translation_preview":
            let result = try JSONDecoder().decode(V2TranslationResult.self, from: data)
            guard result.sessionId == logicalSessionID,
                  result.connectionId == connectionID,
                  !finalizedTurnIDs.contains(result.turnId),
                  pendingFinals[result.turnId] == nil,
                  result.clientRevision == previewInFlightRevisionByTurn[result.turnId],
                  let turnID = UUID(uuidString: result.turnId) else {
                return
            }
            previewInFlightRevisionByTurn.removeValue(forKey: result.turnId)
            eventHandler?(.preview(turnID, result.text))
            logTiming(result.timing, lane: "preview", turnID: result.turnId, revision: result.clientRevision)
            do {
                try await sendLatestPreviewIfNeeded(turnID: result.turnId)
            } catch {
                socketDidFail(error)
            }
        case "translation_final":
            let result = try JSONDecoder().decode(V2TranslationResult.self, from: data)
            guard result.sessionId == logicalSessionID,
                  result.connectionId == connectionID,
                  let pending = pendingFinals[result.turnId],
                  pending.clientRevision == result.clientRevision,
                  let turnID = UUID(uuidString: result.turnId) else {
                return
            }
            finalizedTurnIDs.insert(result.turnId)
            cancelEmergencyPreview(for: result.turnId)
            if emergencyFinalTurnID == result.turnId {
                cancelEmergencyFinalTask()
            }
            emergencyCompletedFinalTurnIDs.insert(result.turnId)
            latestPreviewByTurn.removeValue(forKey: result.turnId)
            pendingFinals.removeValue(forKey: result.turnId)
            eventHandler?(.completed(turnID, result.text))
            logTiming(result.timing, lane: "final", turnID: result.turnId, revision: result.clientRevision)
        case "final_missing":
            let missing = try JSONDecoder().decode(V2TurnMessage.self, from: data)
            if let pending = pendingFinals[missing.turnId], pending.clientRevision == missing.clientRevision {
                try await sendFinal(pending)
            }
        case "final_failed":
            let failed = try JSONDecoder().decode(V2TurnMessage.self, from: data)
            pendingFinals.removeValue(forKey: failed.turnId)
            eventHandler?(.failed("Final translation failed for turn \(failed.turnId)."))
        case "error":
            let error = try JSONDecoder().decode(V2ErrorMessage.self, from: data)
            handleProtocolError(error)
        case "ping":
            try await sendMessage(
                V2PingMessage(type: "ping", clientTime: ISO8601DateFormatter().string(from: Date()))
            )
        case "pong", "session_completed":
            break
        default:
            Self.logger.debug("ignored unsupported v2 server message type=\(envelope.type, privacy: .public)")
        }
    }

    private func handleProtocolError(_ error: V2ErrorMessage) {
        Self.logger.error(
            "v2 protocol error code=\(error.code, privacy: .public) scope=\(error.scope, privacy: .public) recoverable=\(error.recoverable, privacy: .public) message=\(error.message, privacy: .public)"
        )

        if !isReady, error.scope == "connection" || error.scope == "session" {
            let setupError = DeepSeekTranslationError.serverError(error.message)
            failHandshakeContinuations(with: setupError)
            closeCurrentSocket()
            return
        }

        switch error.scope {
        case "preview":
            if let turnID = error.turnId,
               error.clientRevision == previewInFlightRevisionByTurn[turnID] {
                previewInFlightRevisionByTurn.removeValue(forKey: turnID)
                lastSentPreviewTextByTurn.removeValue(forKey: turnID)
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await self?.retryLatestPreview(turnID: turnID)
                }
            }
            return
        case "final":
            if !error.recoverable, let turnID = error.turnId {
                pendingFinals.removeValue(forKey: turnID)
                eventHandler?(.failed(error.message))
            }
        case "connection", "session":
            if error.recoverable {
                socketDidFail(DeepSeekTranslationError.serverError(error.message))
            } else {
                eventHandler?(.failed(error.message))
            }
        default:
            break
        }
    }

    private func retryLatestPreview(turnID: String) async {
        guard !Task.isCancelled, !isStopping, isReady else {
            return
        }
        do {
            try await sendLatestPreviewIfNeeded(turnID: turnID)
        } catch {
            socketDidFail(error)
        }
    }

    private func socketDidFail(_ error: Error) {
        guard !isStopping else {
            return
        }
        failHandshakeContinuations(with: error)
        closeCurrentSocket()
        scheduleEmergencyFinalIfNeeded()
        if let latestTurnID = latestPreviewByTurn.keys.sorted().last {
            scheduleEmergencyPreview(for: latestTurnID)
        }
        scheduleReconnectIfNeeded()
    }

    private func scheduleReconnectIfNeeded() {
        guard !isStopping,
              !isUsingLegacyFallback,
              reconnectTask == nil,
              hasConfiguredSession || eventHandler != nil else {
            return
        }
        reconnectTask = Task { [weak self] in
            await self?.runReconnectLoop()
        }
    }

    private func runReconnectLoop() async {
        defer {
            reconnectTask = nil
        }
        var attempt = 0
        while !Task.isCancelled, !isStopping {
            let delay = Self.reconnectDelays[min(attempt, Self.reconnectDelays.count - 1)]
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, !isStopping else {
                return
            }
            do {
                try await establishSocket(resume: hasConfiguredSession)
                return
            } catch {
                if !isRecoverableConnectionError(error) {
                    Self.logger.error(
                        "v2 connection stopped after non-recoverable error=\(error.localizedDescription, privacy: .public)"
                    )
                    eventHandler?(.failed(error.localizedDescription))
                    return
                }
                attempt += 1
                Self.logger.warning(
                    "v2 reconnect failed attempt=\(attempt, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func isRecoverableConnectionError(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        guard let translationError = error as? DeepSeekTranslationError else {
            return true
        }
        switch translationError {
        case .authenticationRequired, .invalidRequest:
            return false
        case .invalidResponse, .requestFailed, .serverError, .alreadyConnected, .timedOut:
            return true
        }
    }

    private func closeCurrentSocket() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isReady = false
        receivedHello = false
        connectionID = nil
        previewInFlightRevisionByTurn.removeAll()
        lastSentPreviewTextByTurn.removeAll()
    }

    private func waitForHello() async throws {
        if receivedHello {
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            helloContinuation = continuation
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await self?.timeoutHelloIfNeeded()
            }
        }
    }

    private func waitForReady() async throws {
        if isReady {
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            Task { [weak self] in
                // Live UI uses a bounded latest-wins HTTP preview while v2 is not
                // ready. Give a slow production configure enough time to complete
                // instead of piling another DB-backed session attempt every 12s.
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                await self?.timeoutReadyIfNeeded()
            }
        }
    }

    private func scheduleEmergencyPreview(for turnID: String) {
        guard !isReady, !isStopping, eventHandler != nil else {
            return
        }

        // The emergency lane is global latest-wins, not one queue per turn. If a
        // newer turn arrives while an older request is running, its result is
        // discarded so the translation pane can never jump backwards.
        emergencyPreviewGeneration += 1
        emergencyPreviewTurnID = turnID
        startEmergencyPreviewTaskIfNeeded()
    }

    private func startEmergencyPreviewTaskIfNeeded() {
        guard emergencyPreviewTask == nil,
              emergencyPreviewTurnID != nil else {
            return
        }

        emergencyPreviewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.emergencyPreviewDebounceNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            await self?.runEmergencyPreview()
        }
    }

    private func runEmergencyPreview() async {
        guard !Task.isCancelled,
              !isReady,
              !isStopping,
              let turnID = emergencyPreviewTurnID,
              !finalizedTurnIDs.contains(turnID),
              let sourceText = emergencySourceText(for: turnID),
              !sourceText.isEmpty else {
            emergencyPreviewTask = nil
            return
        }

        let generation = emergencyPreviewGeneration
        let history = emergencyHistory
        let startedAt = Date()

        do {
            let translation = try await translateStableBlock(sourceText, history: history)
            guard !Task.isCancelled,
                  !isReady,
                  !isStopping,
                  !finalizedTurnIDs.contains(turnID),
                  emergencyPreviewTurnID == turnID,
                  let turnUUID = UUID(uuidString: turnID) else {
                Self.logger.debug(
                    "discarded stale emergency preview turn=\(turnID, privacy: .public) generation=\(generation, privacy: .public)"
                )
                finishEmergencyPreview(completedGeneration: generation)
                return
            }

            eventHandler?(.preview(turnUUID, translation))
            Self.logger.notice(
                "emergency preview completed turn=\(turnID, privacy: .public) generation=\(generation, privacy: .public) currentGeneration=\(self.emergencyPreviewGeneration, privacy: .public) durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1_000), privacy: .public)"
            )
        } catch is CancellationError {
            // Expected when v2 becomes ready or the listening session stops.
        } catch {
            Self.logger.warning(
                "emergency preview failed turn=\(turnID, privacy: .public) generation=\(generation, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }

        finishEmergencyPreview(completedGeneration: generation)
    }

    private func finishEmergencyPreview(completedGeneration: Int) {
        emergencyPreviewTask = nil
        guard !isReady,
              !isStopping,
              let turnID = emergencyPreviewTurnID,
              !finalizedTurnIDs.contains(turnID),
              emergencySourceText(for: turnID) != nil,
              emergencyPreviewGeneration != completedGeneration else {
            return
        }
        startEmergencyPreviewTaskIfNeeded()
    }

    private func emergencySourceText(for turnID: String) -> String? {
        if let pendingFinal = pendingFinals[turnID] {
            return pendingFinal.sourceText
        }
        return latestPreviewByTurn[turnID]
    }

    private func cancelEmergencyPreview(for turnID: String) {
        guard emergencyPreviewTurnID == turnID else {
            return
        }
        emergencyPreviewGeneration += 1
        emergencyPreviewTurnID = nil
        emergencyPreviewTask?.cancel()
        emergencyPreviewTask = nil
    }

    private func cancelEmergencyPreviews() {
        emergencyPreviewGeneration += 1
        emergencyPreviewTurnID = nil
        emergencyPreviewTask?.cancel()
        emergencyPreviewTask = nil
    }

    private func scheduleEmergencyFinalIfNeeded() {
        guard !isReady,
              !isStopping,
              emergencyFinalTask == nil,
              let pending = pendingFinals.values
                .filter({
                    !finalizedTurnIDs.contains($0.turnID)
                        && !emergencyCompletedFinalTurnIDs.contains($0.turnID)
                        && (emergencyFinalAttempts[$0.turnID] ?? 0) < 2
                })
                .min(by: { $0.enqueueSequence < $1.enqueueSequence }) else {
            return
        }

        emergencyFinalTurnID = pending.turnID
        emergencyFinalAttempts[pending.turnID, default: 0] += 1
        emergencyFinalTask = Task { [weak self] in
            await self?.runEmergencyFinal(pending)
        }
    }

    private func runEmergencyFinal(_ pending: V2PendingFinal) async {
        let startedAt = Date()
        do {
            let translation = try await translateStableBlock(pending.sourceText, history: emergencyHistory)
            guard !Task.isCancelled,
                  !isReady,
                  !isStopping,
                  !finalizedTurnIDs.contains(pending.turnID),
                  let current = pendingFinals[pending.turnID],
                  current.clientRevision == pending.clientRevision,
                  current.sourceText == pending.sourceText,
                  let turnUUID = UUID(uuidString: pending.turnID) else {
                finishEmergencyFinal()
                return
            }

            emergencyCompletedFinalTurnIDs.insert(pending.turnID)
            cancelEmergencyPreview(for: pending.turnID)
            eventHandler?(.completed(turnUUID, translation))
            Self.logger.notice(
                "emergency final completed turn=\(pending.turnID, privacy: .public) revision=\(pending.clientRevision, privacy: .public) durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1_000), privacy: .public)"
            )
        } catch is CancellationError {
            // Expected when v2 becomes ready or the listening session stops.
        } catch {
            Self.logger.warning(
                "emergency final failed turn=\(pending.turnID, privacy: .public) revision=\(pending.clientRevision, privacy: .public) attempt=\(self.emergencyFinalAttempts[pending.turnID] ?? 0, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }

        finishEmergencyFinal()
    }

    private func finishEmergencyFinal() {
        emergencyFinalTask = nil
        emergencyFinalTurnID = nil
        scheduleEmergencyFinalIfNeeded()
    }

    private func cancelEmergencyFinalTask() {
        emergencyFinalTask?.cancel()
        emergencyFinalTask = nil
        emergencyFinalTurnID = nil
    }

    private func timeoutHelloIfNeeded() {
        guard let continuation = helloContinuation else {
            return
        }
        helloContinuation = nil
        continuation.resume(throwing: DeepSeekTranslationError.timedOut)
    }

    private func timeoutReadyIfNeeded() {
        guard let continuation = readyContinuation else {
            return
        }
        readyContinuation = nil
        continuation.resume(throwing: DeepSeekTranslationError.timedOut)
    }

    private func sendMessage<Message: Encodable>(_ message: Message) async throws {
        guard let socket = webSocketTask else {
            throw DeepSeekTranslationError.requestFailed(URLError(.networkConnectionLost))
        }
        let data = try JSONEncoder().encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DeepSeekTranslationError.invalidRequest
        }
        try await socket.send(.string(text))
    }

    private func nextRevision(for turnID: String) -> Int {
        let revision = (clientRevisionByTurn[turnID] ?? 0) + 1
        clientRevisionByTurn[turnID] = revision
        return revision
    }

    private func failHandshakeContinuations(with error: Error) {
        helloContinuation?.resume(throwing: error)
        helloContinuation = nil
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
    }

    private func logTiming(_ timing: V2Timing?, lane: String, turnID: String, revision: Int) {
        guard let timing else {
            return
        }
        Self.logger.info(
            "v2 timing lane=\(lane, privacy: .public) turn=\(turnID, privacy: .public) revision=\(revision, privacy: .public) queueMs=\(timing.queueMs, privacy: .public) providerMs=\(timing.providerTotalMs, privacy: .public) totalMs=\(timing.totalMs, privacy: .public)"
        )
    }
}

private struct V2PendingFinal {
    let turnID: String
    let clientRevision: Int
    let sourceText: String
    let enqueueSequence: Int
    var acknowledged: Bool
}

private struct V2Envelope: Decodable { let type: String }
private struct V2HelloMessage: Decodable { let type: String; let connectionId: String }
private struct V2ReadyMessage: Decodable {
    let type: String
    let sessionId: String
    let connectionId: String
    let resumed: Bool
}
private struct V2ConfigureMessage: Encodable {
    let type: String
    let protocolVersion: Int
    let sessionId: String
    let sourceLanguage: String
    let targetLanguage: String
}
private struct V2ResumeMessage: Encodable {
    let type: String
    let protocolVersion: Int
    let sessionId: String
    let sourceLanguage: String
    let targetLanguage: String
    let pendingFinals: [V2PendingFinalReference]
}
private struct V2PendingFinalReference: Encodable {
    let turnId: String
    let clientRevision: Int
}
private struct V2PreviewMessage: Encodable {
    let type: String
    let sessionId: String
    let turnId: String
    let clientRevision: Int
    let sourceText: String
}
private struct V2FinalMessage: Encodable {
    let type: String
    let sessionId: String
    let turnId: String
    let clientRevision: Int
    let sourceText: String
}
private struct V2CompleteSessionMessage: Encodable { let type: String; let sessionId: String }
private struct V2PingMessage: Encodable { let type: String; let clientTime: String }
private struct V2AckMessage: Decodable {
    let type: String
    let turnId: String
    let clientRevision: Int
    let status: String
}
private struct V2TurnMessage: Decodable {
    let type: String
    let turnId: String
    let clientRevision: Int
}
private struct V2TranslationResult: Decodable {
    let type: String
    let sessionId: String
    let connectionId: String
    let turnId: String
    let clientRevision: Int
    let serverRevision: Int
    let text: String
    let isFinal: Bool
    let timing: V2Timing?
}
private struct V2Timing: Decodable {
    let queueMs: Int
    let providerFirstTokenMs: Int
    let providerTotalMs: Int
    let totalMs: Int
}
private struct V2ErrorMessage: Decodable {
    let type: String
    let code: String
    let message: String
    let recoverable: Bool
    let scope: String
    let turnId: String?
    let clientRevision: Int?
}
