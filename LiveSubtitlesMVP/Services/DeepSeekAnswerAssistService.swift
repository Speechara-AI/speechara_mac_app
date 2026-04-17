import Foundation

enum DeepSeekAnswerAssistError: LocalizedError {
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
            return "The app could not create the answer-assist request."
        case .invalidResponse:
            return "The AI service returned an empty answer suggestion."
        case .requestFailed(let error):
            return "The app could not draft an answer: \(error.localizedDescription)"
        case .serverError(let message):
            return "The AI service returned an error: \(message)"
        }
    }
}

actor DeepSeekAnswerAssistService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func suggestAnswer(
        apiKey: String,
        transcript: String,
        inputLanguageName: String,
        outputLanguageName: String
    ) async throws -> String {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw DeepSeekAnswerAssistError.missingAPIKey
        }

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            throw DeepSeekAnswerAssistError.invalidResponse
        }

        let requestBody = DeepSeekAnswerAssistRequest(
            model: "deepseek-chat",
            messages: [
                DeepSeekAnswerAssistMessage(
                    role: "system",
                    content: """
                    You help a user answer naturally during a live meeting. Read the transcript and identify the most recent question asked by another participant.
                    Tags mean: [REMOTE] = other people in the meeting, [YOU] = the local user.
                    Draft a reply in \(outputLanguageName) that sounds like something a real person would say out loud right now.
                    Keep it conversational, clear, and reasonably short. Prefer 1 to 3 natural spoken sentences, not an essay.
                    Use first-person wording when appropriate. Do not sound academic, robotic, or encyclopedic.
                    Do not mention the transcript, the tags, or that you are an assistant.
                    If context is incomplete, make the most reasonable helpful assumption and phrase it naturally, without overexplaining.
                    If there is no clear question yet, say that there is no clear question yet in one short natural sentence.
                    Return only the suggested answer text. No analysis, no labels, no bullet points unless the answer truly needs a tiny list.
                    """
                ),
                DeepSeekAnswerAssistMessage(
                    role: "user",
                    content: """
                    Transcript source language: \(inputLanguageName)
                    Answer language: \(outputLanguageName)

                    Transcript:
                    \(trimmedTranscript)
                    """
                ),
            ],
            temperature: 0.2,
            maxTokens: 420,
            stream: false
        )

        guard let request = try makeRequest(apiKey: trimmedAPIKey, requestBody: requestBody) else {
            throw DeepSeekAnswerAssistError.invalidRequest
        }

        do {
            let (data, response) = try await session.data(for: request)
            try validateResponse(data: data, response: response)

            let completion = try JSONDecoder().decode(DeepSeekAnswerAssistResponse.self, from: data)
            guard let answer = completion.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !answer.isEmpty else {
                throw DeepSeekAnswerAssistError.invalidResponse
            }

            return answer
        } catch let error as DeepSeekAnswerAssistError {
            throw error
        } catch {
            throw DeepSeekAnswerAssistError.requestFailed(error)
        }
    }

    private func makeRequest(
        apiKey: String,
        requestBody: DeepSeekAnswerAssistRequest
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
            throw DeepSeekAnswerAssistError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let errorMessage = (try? JSONDecoder().decode(DeepSeekAnswerAssistErrorResponse.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(httpResponse.statusCode)"
            throw DeepSeekAnswerAssistError.serverError(errorMessage)
        }
    }
}

private struct DeepSeekAnswerAssistRequest: Encodable {
    let model: String
    let messages: [DeepSeekAnswerAssistMessage]
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

private struct DeepSeekAnswerAssistMessage: Codable {
    let role: String
    let content: String
}

private struct DeepSeekAnswerAssistResponse: Decodable {
    let choices: [DeepSeekAnswerAssistChoice]
}

private struct DeepSeekAnswerAssistChoice: Decodable {
    let message: DeepSeekAnswerAssistChoiceMessage
}

private struct DeepSeekAnswerAssistChoiceMessage: Decodable {
    let content: String?
}

private struct DeepSeekAnswerAssistErrorResponse: Decodable {
    let error: DeepSeekAnswerAssistErrorBody
}

private struct DeepSeekAnswerAssistErrorBody: Decodable {
    let message: String
}
