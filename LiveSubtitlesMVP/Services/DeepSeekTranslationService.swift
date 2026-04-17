import Foundation

enum DeepSeekTranslationError: LocalizedError {
    case missingAPIKey
    case invalidRequest
    case invalidResponse
    case requestFailed(Error)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "AI service API key is missing. Add it in Settings and try again."
        case .invalidRequest:
            return "The app could not create the translation request."
        case .invalidResponse:
            return "The AI service returned an empty translation response."
        case .requestFailed(let error):
            return "The app could not translate the final transcript: \(error.localizedDescription)"
        case .serverError(let message):
            return "The AI service returned an error: \(message)"
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
    private let session: URLSession
    private let maxHistoryTurns = 4

    private var apiKey: String?
    private var sourceLanguageName = ""
    private var targetLanguageName = ""
    private var conversationMessages: [DeepSeekChatMessage] = []
    private var pendingTranscriptChunks: [PendingTranslationChunk] = []
    private var isProcessingQueue = false
    private var processingTask: Task<Void, Never>?
    private var eventHandler: (@Sendable (DeepSeekTranslationEvent) -> Void)?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func startSession(
        apiKey: String,
        sourceLanguageName: String,
        targetLanguageName: String,
        eventHandler: @escaping @Sendable (DeepSeekTranslationEvent) -> Void
    ) throws {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw DeepSeekTranslationError.missingAPIKey
        }

        self.apiKey = trimmedAPIKey
        self.sourceLanguageName = sourceLanguageName
        self.targetLanguageName = targetLanguageName
        self.eventHandler = eventHandler
        pendingTranscriptChunks = []
        isProcessingQueue = false
        processingTask?.cancel()
        processingTask = nil
        conversationMessages = [makeSystemMessage()]
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

    func resetSession() {
        processingTask?.cancel()
        processingTask = nil
        conversationMessages = []
        pendingTranscriptChunks = []
        isProcessingQueue = false
        apiKey = nil
        sourceLanguageName = ""
        targetLanguageName = ""
        eventHandler = nil
    }

    func replaceHistory(with turns: [DeepSeekTranslationHistoryTurn]) {
        conversationMessages = [makeSystemMessage()]

        let recentTurns = turns.suffix(maxHistoryTurns)
        for turn in recentTurns {
            let source = turn.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let translation = turn.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty, !translation.isEmpty else {
                continue
            }

            conversationMessages.append(DeepSeekChatMessage(role: "user", content: source))
            conversationMessages.append(DeepSeekChatMessage(role: "assistant", content: translation))
        }
    }

    func translateStableBlock(
        _ transcript: String,
        history: [DeepSeekTranslationHistoryTurn]
    ) async throws -> String {
        guard let apiKey else {
            throw DeepSeekTranslationError.missingAPIKey
        }

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            throw DeepSeekTranslationError.invalidResponse
        }

        let historyMessages = history
            .suffix(maxHistoryTurns)
            .flatMap { turn -> [DeepSeekChatMessage] in
                let source = turn.source.trimmingCharacters(in: .whitespacesAndNewlines)
                let translation = turn.translation.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !source.isEmpty, !translation.isEmpty else {
                    return []
                }

                return [
                    DeepSeekChatMessage(role: "user", content: source),
                    DeepSeekChatMessage(role: "assistant", content: translation),
                ]
            }

        let blockTranscript = """
        Translate this stable dialogue block.
        Return exactly one output line for each input line, in the same order.
        Preserve timestamps like [12:34:56] and preserve speaker labels before a colon.

        \(trimmedTranscript)
        """

        return try await requestCompletedTranslation(
            apiKey: apiKey,
            transcript: blockTranscript,
            messages: [makeSystemMessage()] + historyMessages,
            maxTokens: 768
        )
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
                let translation = try await streamTranslation(
                    for: nextChunk.transcript,
                    turnID: nextChunk.turnID
                )
                let userMessage = DeepSeekChatMessage(role: "user", content: nextChunk.transcript)
                let assistantMessage = DeepSeekChatMessage(role: "assistant", content: translation)

                conversationMessages.append(userMessage)
                conversationMessages.append(assistantMessage)
                trimConversationHistory()

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

    private func streamTranslation(
        for transcript: String,
        turnID: UUID
    ) async throws -> String {
        let (bytes, response) = try await streamingResponse(
            for: transcript,
            messages: conversationMessages,
            maxTokens: 192
        )
        try await validateStreamingResponse(bytes: bytes, response: response)

        var streamedTranslation = ""

        for try await line in bytes.lines {
            if Task.isCancelled {
                throw CancellationError()
            }

            guard line.hasPrefix("data:") else {
                continue
            }

            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" {
                break
            }

            guard let payloadData = payload.data(using: .utf8) else {
                continue
            }

            let chunk = try JSONDecoder().decode(DeepSeekStreamChunk.self, from: payloadData)
            if let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
                streamedTranslation.append(delta)
                eventHandler?(.preview(turnID, streamedTranslation))
            }
        }

        let finalTranslation = streamedTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalTranslation.isEmpty else {
            throw DeepSeekTranslationError.invalidResponse
        }

        return finalTranslation
    }

    private func trimConversationHistory() {
        let systemMessage = conversationMessages.first
        let recentTurns = conversationMessages.dropFirst().suffix(maxHistoryTurns * 2)
        conversationMessages = [systemMessage].compactMap { $0 } + recentTurns
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

    private func makeSystemMessage() -> DeepSeekChatMessage {
        DeepSeekChatMessage(
            role: "system",
            content: """
            Translate new live meeting fragments from \(sourceLanguageName) to \(targetLanguageName).
            Use prior translated turns only as short context. Preserve line breaks and any leading timestamps like [12:34].
            If a line starts with a speaker label before a colon, preserve the label and translate only the spoken content.
            Return only the translated fragment in \(targetLanguageName), with no commentary.
            """
        )
    }

    private func streamingResponse(
        for transcript: String,
        messages: [DeepSeekChatMessage],
        maxTokens: Int
    ) async throws -> (URLSession.AsyncBytes, URLResponse) {
        guard let apiKey else {
            throw DeepSeekTranslationError.missingAPIKey
        }

        let userMessage = DeepSeekChatMessage(role: "user", content: transcript)
        let requestBody = DeepSeekChatCompletionRequest(
            model: "deepseek-chat",
            messages: messages + [userMessage],
            temperature: 0,
            maxTokens: maxTokens,
            stream: true
        )

        guard let request = try makeRequest(apiKey: apiKey, requestBody: requestBody) else {
            throw DeepSeekTranslationError.invalidRequest
        }

        return try await session.bytes(for: request)
    }

    private func requestCompletedTranslation(
        apiKey: String,
        transcript: String,
        messages: [DeepSeekChatMessage],
        maxTokens: Int
    ) async throws -> String {
        let userMessage = DeepSeekChatMessage(role: "user", content: transcript)
        let requestBody = DeepSeekChatCompletionRequest(
            model: "deepseek-chat",
            messages: messages + [userMessage],
            temperature: 0,
            maxTokens: maxTokens,
            stream: false
        )

        guard let request = try makeRequest(apiKey: apiKey, requestBody: requestBody) else {
            throw DeepSeekTranslationError.invalidRequest
        }

        let (data, response) = try await session.data(for: request)
        try validateResponse(data: data, response: response)

        let completion = try JSONDecoder().decode(DeepSeekChatCompletionResponse.self, from: data)
        guard let translation = completion.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !translation.isEmpty else {
            throw DeepSeekTranslationError.invalidResponse
        }

        return translation
    }

    private func makeRequest(
        apiKey: String,
        requestBody: DeepSeekChatCompletionRequest
    ) throws -> URLRequest? {
        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }

    private func validateStreamingResponse(
        bytes: URLSession.AsyncBytes,
        response: URLResponse
    ) async throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekTranslationError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
            }

            let errorMessage = (try? JSONDecoder().decode(DeepSeekErrorResponse.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(httpResponse.statusCode)"
            throw DeepSeekTranslationError.serverError(errorMessage)
        }
    }

    private func validateResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekTranslationError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let errorMessage = (try? JSONDecoder().decode(DeepSeekErrorResponse.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(httpResponse.statusCode)"
            throw DeepSeekTranslationError.serverError(errorMessage)
        }
    }
}

private struct PendingTranslationChunk {
    let turnID: UUID
    var transcript: String
}

private struct DeepSeekChatCompletionRequest: Encodable {
    let model: String
    let messages: [DeepSeekChatMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct DeepSeekChatMessage: Codable {
    let role: String
    let content: String
}

private struct DeepSeekStreamChunk: Decodable {
    let choices: [DeepSeekStreamChoice]
}

private struct DeepSeekStreamChoice: Decodable {
    let delta: DeepSeekStreamDelta
}

private struct DeepSeekStreamDelta: Decodable {
    let content: String?
}

private struct DeepSeekErrorResponse: Decodable {
    let error: DeepSeekErrorBody
}

private struct DeepSeekErrorBody: Decodable {
    let message: String
}

private struct DeepSeekChatCompletionResponse: Decodable {
    let choices: [DeepSeekChatCompletionChoice]
}

private struct DeepSeekChatCompletionChoice: Decodable {
    let message: DeepSeekChatCompletionChoiceMessage
}

private struct DeepSeekChatCompletionChoiceMessage: Decodable {
    let content: String?
}
