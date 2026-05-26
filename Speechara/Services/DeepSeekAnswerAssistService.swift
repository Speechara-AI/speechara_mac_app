import Foundation

enum DeepSeekAnswerAssistError: LocalizedError {
    case invalidResponse
    case requestFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The AI backend returned an empty answer suggestion."
        case .requestFailed(let error):
            return "The app could not draft an answer: \(error.localizedDescription)"
        }
    }
}

actor DeepSeekAnswerAssistService {
    private let proxyService: SpeecharaBackendProxyService

    init(proxyService: SpeecharaBackendProxyService = SpeecharaBackendProxyService()) {
        self.proxyService = proxyService
    }

    func suggestAnswer(
        transcript: String,
        inputLanguageName: String,
        outputLanguageName: String
    ) async throws -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            throw DeepSeekAnswerAssistError.invalidResponse
        }

        do {
            let completion = try await proxyService.performChatCompletion(
                SpeecharaChatCompletionRequest(
                    model: "deepseek-chat",
                    messages: [
                        SpeecharaChatMessage(
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
                        SpeecharaChatMessage(
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
            )

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
}
