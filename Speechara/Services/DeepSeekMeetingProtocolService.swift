import Foundation

enum DeepSeekMeetingProtocolError: LocalizedError {
    case invalidResponse
    case incompleteResponse
    case requestFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The AI backend returned an empty meeting protocol response."
        case .incompleteResponse:
            return "The AI backend returned a truncated meeting protocol response."
        case .requestFailed(let error):
            return "The app could not generate a meeting protocol: \(error.localizedDescription)"
        }
    }
}

actor DeepSeekMeetingProtocolService {
    private static let initialMaxTokens = 2200
    private static let retryMaxTokens = 3600

    private let proxyService: SpeecharaBackendProxyService

    init(proxyService: SpeecharaBackendProxyService = SpeecharaBackendProxyService()) {
        self.proxyService = proxyService
    }

    func generateProtocol(
        transcript: String,
        languageName: String
    ) async throws -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            throw DeepSeekMeetingProtocolError.invalidResponse
        }

        do {
            return try await requestProtocol(
                transcript: trimmedTranscript,
                languageName: languageName,
                maxTokens: Self.initialMaxTokens
            )
        } catch DeepSeekMeetingProtocolError.incompleteResponse {
            return try await requestProtocol(
                transcript: trimmedTranscript,
                languageName: languageName,
                maxTokens: Self.retryMaxTokens
            )
        } catch {
            throw DeepSeekMeetingProtocolError.requestFailed(error)
        }
    }

    private func requestProtocol(
        transcript: String,
        languageName: String,
        maxTokens: Int
    ) async throws -> String {
        let completion = try await proxyService.performChatCompletion(
            SpeecharaChatCompletionRequest(
                model: "deepseek-chat",
                messages: [
                    SpeecharaChatMessage(
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
        )

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
}
