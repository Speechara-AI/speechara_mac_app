import Foundation

struct SessionDraft: Codable {
    struct DraftTurn: Codable {
        let id: UUID
        let speakerLabel: String?
        let text: String
        let translationSpeakerLabel: String?
        let translationText: String
        let timestamp: Date
        let isClosed: Bool
    }

    // Optional so drafts written before history checkpoints remain readable.
    var history: MeetingHistoryCheckpoint? = nil
    let turns: [DraftTurn]
    let subtitlesText: String
    let translatedText: String
    let transcriptSummaryText: String
    let translationSummaryText: String
    let transcriptProtocolText: String
    let translationProtocolText: String
    let transcriptAnswerText: String
    let translationAnswerText: String
}

struct MeetingHistoryCheckpoint: Codable, Equatable {
    var sessionID: String?
    var revision: Int?
    var startedAt: Date?
    var endedAt: Date?
    var source: String
    var conversationID: UUID
    var authUserID: String?
    var needsLegacyRecovery: Bool? = nil
    var inputLanguage: String
    var translationLanguage: String
    var translationEnabled: Bool
    var recordingEnabled: Bool
}
