import Foundation

enum DeepSeekSummaryError: LocalizedError {
    case missingAPIKey
    case invalidRequest
    case invalidResponse
    case incompleteResponse
    case requestFailed(Error)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "AI service API key is missing. Add it in Settings and try again."
        case .invalidRequest:
            return "The app could not create the summary request."
        case .invalidResponse:
            return "The AI service returned an empty summary response."
        case .incompleteResponse:
            return "The AI service returned a truncated summary response."
        case .requestFailed(let error):
            return "The app could not generate a summary: \(error.localizedDescription)"
        case .serverError(let message):
            return "The AI service returned an error: \(message)"
        }
    }
}

actor DeepSeekSummaryService {
    private static let initialMaxTokens = 640
    private static let retryMaxTokens = 1100

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func summarize(
        apiKey: String,
        transcript: String,
        inputLanguageName: String,
        outputLanguageName: String
    ) async throws -> String {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw DeepSeekSummaryError.missingAPIKey
        }

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            throw DeepSeekSummaryError.invalidResponse
        }

        do {
            return try await requestSummary(
                apiKey: trimmedAPIKey,
                transcript: trimmedTranscript,
                inputLanguageName: inputLanguageName,
                outputLanguageName: outputLanguageName,
                maxTokens: Self.initialMaxTokens
            )
        } catch DeepSeekSummaryError.incompleteResponse {
            return try await requestSummary(
                apiKey: trimmedAPIKey,
                transcript: trimmedTranscript,
                inputLanguageName: inputLanguageName,
                outputLanguageName: outputLanguageName,
                maxTokens: Self.retryMaxTokens
            )
        }
    }

    private func requestSummary(
        apiKey: String,
        transcript: String,
        inputLanguageName: String,
        outputLanguageName: String,
        maxTokens: Int
    ) async throws -> String {
        let requestBody = DeepSeekSummaryRequest(
            model: "deepseek-chat",
            messages: [
                DeepSeekSummaryMessage(
                    role: "system",
                    content: "Summarize transcripts in \(outputLanguageName). Keep only explicit facts. Use 8 to 12 concise bullet points. Preserve requests, decisions, dates, names, and next steps. Do not invent details. Do not cut off mid-bullet."
                ),
                DeepSeekSummaryMessage(
                    role: "user",
                    content: "Source language: \(inputLanguageName)\nOutput language: \(outputLanguageName)\n\nTranscript:\n\(transcript)"
                ),
            ],
            temperature: 0,
            maxTokens: maxTokens,
            stream: false
        )

        guard let request = try makeRequest(apiKey: apiKey, requestBody: requestBody) else {
            throw DeepSeekSummaryError.invalidRequest
        }

        let (data, response) = try await session.data(for: request)
        try validateResponse(data: data, response: response)

        let completion = try JSONDecoder().decode(DeepSeekSummaryResponse.self, from: data)
        guard let choice = completion.choices.first,
              let summary = choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else {
            throw DeepSeekSummaryError.invalidResponse
        }

        if choice.finishReason == "length" {
            throw DeepSeekSummaryError.incompleteResponse
        }

        return summary
    }

    private func makeRequest(
        apiKey: String,
        requestBody: DeepSeekSummaryRequest
    ) throws -> URLRequest? {
        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }

    private func validateResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekSummaryError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let errorMessage = (try? JSONDecoder().decode(DeepSeekSummaryErrorResponse.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(httpResponse.statusCode)"
            throw DeepSeekSummaryError.serverError(errorMessage)
        }
    }
}

private struct DeepSeekSummaryRequest: Encodable {
    let model: String
    let messages: [DeepSeekSummaryMessage]
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

private struct DeepSeekSummaryMessage: Codable {
    let role: String
    let content: String
}

private struct DeepSeekSummaryResponse: Decodable {
    let choices: [DeepSeekSummaryChoice]
}

private struct DeepSeekSummaryChoice: Decodable {
    let message: DeepSeekSummaryChoiceMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct DeepSeekSummaryChoiceMessage: Decodable {
    let content: String?
}

private struct DeepSeekSummaryErrorResponse: Decodable {
    let error: DeepSeekSummaryErrorBody
}

private struct DeepSeekSummaryErrorBody: Decodable {
    let message: String
}
