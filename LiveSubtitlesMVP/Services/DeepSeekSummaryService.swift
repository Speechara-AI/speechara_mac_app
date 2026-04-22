import Foundation

enum DeepSeekSummaryError: LocalizedError {
    case invalidResponse
    case incompleteResponse
    case requestFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The AI backend returned an empty summary response."
        case .incompleteResponse:
            return "The AI backend returned a truncated summary response."
        case .requestFailed(let error):
            return "The app could not generate a summary: \(error.localizedDescription)"
        }
    }
}

actor DeepSeekSummaryService {
    private static let initialMaxTokens = 640
    private static let retryMaxTokens = 1100

    private let proxyService: SpeecharaBackendProxyService

    init(proxyService: SpeecharaBackendProxyService = SpeecharaBackendProxyService()) {
        self.proxyService = proxyService
    }

    func summarize(
        transcript: String,
        inputLanguageName: String,
        outputLanguageName: String
    ) async throws -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            throw DeepSeekSummaryError.invalidResponse
        }

        do {
            return try await requestSummary(
                transcript: trimmedTranscript,
                inputLanguageName: inputLanguageName,
                outputLanguageName: outputLanguageName,
                maxTokens: Self.initialMaxTokens
            )
        } catch DeepSeekSummaryError.incompleteResponse {
            return try await requestSummary(
                transcript: trimmedTranscript,
                inputLanguageName: inputLanguageName,
                outputLanguageName: outputLanguageName,
                maxTokens: Self.retryMaxTokens
            )
        } catch {
            throw DeepSeekSummaryError.requestFailed(error)
        }
    }

    private func requestSummary(
        transcript: String,
        inputLanguageName: String,
        outputLanguageName: String,
        maxTokens: Int
    ) async throws -> String {
        let completion = try await proxyService.performChatCompletion(
            SpeecharaChatCompletionRequest(
                model: "deepseek-chat",
                messages: [
                    SpeecharaChatMessage(
                        role: "system",
                        content: "Summarize transcripts in \(outputLanguageName). Keep only explicit facts. Use 8 to 12 concise bullet points. Preserve requests, decisions, dates, names, and next steps. Do not invent details. Do not cut off mid-bullet."
                    ),
                    SpeecharaChatMessage(
                        role: "user",
                        content: "Source language: \(inputLanguageName)\nOutput language: \(outputLanguageName)\n\nTranscript:\n\(transcript)"
                    ),
                ],
                temperature: 0,
                maxTokens: maxTokens,
                stream: false
            )
        )

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
}
