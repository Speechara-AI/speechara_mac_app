import Foundation

enum DeepSeekMeetingProtocolError: LocalizedError {
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
            return "The app could not create the meeting protocol request."
        case .invalidResponse:
            return "The AI service returned an empty meeting protocol response."
        case .incompleteResponse:
            return "The AI service returned a truncated meeting protocol response."
        case .requestFailed(let error):
            return "The app could not generate a meeting protocol: \(error.localizedDescription)"
        case .serverError(let message):
            return "The AI service returned an error: \(message)"
        }
    }
}

actor DeepSeekMeetingProtocolService {
    private static let initialMaxTokens = 2200
    private static let retryMaxTokens = 3600

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generateProtocol(
        apiKey: String,
        transcript: String,
        languageName: String
    ) async throws -> String {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw DeepSeekMeetingProtocolError.missingAPIKey
        }

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            throw DeepSeekMeetingProtocolError.invalidResponse
        }

        do {
            return try await requestProtocol(
                apiKey: trimmedAPIKey,
                transcript: trimmedTranscript,
                languageName: languageName,
                maxTokens: Self.initialMaxTokens
            )
        } catch DeepSeekMeetingProtocolError.incompleteResponse {
            return try await requestProtocol(
                apiKey: trimmedAPIKey,
                transcript: trimmedTranscript,
                languageName: languageName,
                maxTokens: Self.retryMaxTokens
            )
        }
    }

    private func requestProtocol(
        apiKey: String,
        transcript: String,
        languageName: String,
        maxTokens: Int
    ) async throws -> String {
        let requestBody = DeepSeekMeetingProtocolRequest(
            model: "deepseek-chat",
            messages: [
                DeepSeekMeetingProtocolMessage(
                    role: "user",
                    content: """
                    You are given a meeting transcript.

                    Your task is to convert it into a full structured meeting protocol (meeting minutes), not a short summary.

                    Requirements:

                    Capture ALL meaningful topics discussed during the meeting in logical order.
                    Structure the result into sections:
                    Topics discussed
                    Decisions made
                    Agreed actions
                    Responsible persons (if identifiable from the transcript)
                    Open questions / unresolved points
                    Do not omit secondary but meaningful discussions — the protocol must reflect the full meeting, not only the main topic.
                    Remove conversational noise:
                    repetitions
                    interruptions
                    filler phrases
                    emotional or informal fragments that do not affect meaning
                    Preserve meaning precisely:
                    do not invent facts
                    do not add interpretations not present in the transcript
                    if no decision was made, explicitly state that the topic remains open
                    Organize mixed discussions by topic first, even if they were interleaved in conversation.
                    Use professional business style:
                    clear, structured, concise, but sufficiently complete.
                    Output format:
                    Meeting Protocol
                    1. Topics Discussed
                    ...
                    2. Decisions Made
                    ...
                    3. Agreed Actions
                    ...
                    4. Responsible Persons
                    ...
                    5. Open Questions
                    ...
                    Important:
                    Do not compress content too aggressively.
                    The goal is to preserve the full substance of the meeting while making it structured and readable.
                    Inputi and Output language: \(languageName)

                    Below is the transcript:

                    \(transcript)
                    """
                ),
            ],
            temperature: 0,
            maxTokens: maxTokens,
            stream: false
        )

        guard let request = try makeRequest(apiKey: apiKey, requestBody: requestBody) else {
            throw DeepSeekMeetingProtocolError.invalidRequest
        }

        let (data, response) = try await session.data(for: request)
        try validateResponse(data: data, response: response)

        let completion = try JSONDecoder().decode(DeepSeekMeetingProtocolResponse.self, from: data)
        guard let choice = completion.choices.first,
              let protocolText = choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !protocolText.isEmpty else {
            throw DeepSeekMeetingProtocolError.invalidResponse
        }

        if choice.finishReason == "length" {
            throw DeepSeekMeetingProtocolError.incompleteResponse
        }

        return protocolText
    }

    private func makeRequest(
        apiKey: String,
        requestBody: DeepSeekMeetingProtocolRequest
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
            throw DeepSeekMeetingProtocolError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let errorMessage = (try? JSONDecoder().decode(DeepSeekMeetingProtocolErrorResponse.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(httpResponse.statusCode)"
            throw DeepSeekMeetingProtocolError.serverError(errorMessage)
        }
    }
}

private struct DeepSeekMeetingProtocolRequest: Encodable {
    let model: String
    let messages: [DeepSeekMeetingProtocolMessage]
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

private struct DeepSeekMeetingProtocolMessage: Codable {
    let role: String
    let content: String
}

private struct DeepSeekMeetingProtocolResponse: Decodable {
    let choices: [DeepSeekMeetingProtocolChoice]
}

private struct DeepSeekMeetingProtocolChoice: Decodable {
    let message: DeepSeekMeetingProtocolChoiceMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct DeepSeekMeetingProtocolChoiceMessage: Decodable {
    let content: String?
}

private struct DeepSeekMeetingProtocolErrorResponse: Decodable {
    let error: DeepSeekMeetingProtocolErrorBody
}

private struct DeepSeekMeetingProtocolErrorBody: Decodable {
    let message: String
}
