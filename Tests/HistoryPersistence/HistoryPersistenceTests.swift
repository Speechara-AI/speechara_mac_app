import Foundation

@main
struct HistoryPersistenceTests {
    static let date = ISO8601DateFormatter().date(from: "2026-11-18T13:36:44Z")!
    static let localID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    static func snapshot() -> MeetingSessionHistorySnapshot {
        MeetingSessionHistorySnapshot(title: nil, startedAt: date, endedAt: date.addingTimeInterval(1644), durationSeconds: 1644, status: .completed, inputLanguage: "en", translationLanguage: "ru", translationEnabled: true, recordingEnabled: false, microphoneLabel: nil,
            transcriptBlocks: [.init(id: "turn-1", seq: 1, timestamp: "08:36:44", speakerLabel: nil, text: "Saved words")],
            translationBlocks: [.init(transcriptBlockId: "turn-1", seq: 1, language: "ru", text: "Сохранённые слова")], summaryText: nil, protocolText: nil, suggestedAnswerText: nil,
            sessionParams: .init(client: "macos", source: "system_audio", appVersion: "test", focusMode: false, localSessionID: localID.uuidString.lowercased()))
    }
    static func row(id: String = "today", revision: Int = 1, text: String = "", localID: String? = nil) -> [String: Any] {
        var params: [String: Any] = ["client": "macos", "source": "system_audio"]
        if let localID { params["localSessionID"] = localID }
        return ["id": id, "revision": revision, "status": "active", "startedAt": "2026-11-18T13:36:20Z", "updatedAt": "2026-11-18T13:36:20Z", "processedByApp": "macos", "translationEnabled": true, "recordingEnabled": false, "wordCount": 0, "lineCount": 0, "hasSummary": false, "hasProtocol": false, "hasSuggestedAnswer": false, "transcriptText": text, "sessionParams": params]
    }
    static func service(rows: [[String: Any]], nextCursor: String? = nil) -> MeetingSessionHistoryService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockHistoryTransport.self]
        MockHistoryTransport.handler = { request in
            let query = request["query"] as! String
            if query.contains("query MeetingSessions(") {
                var connection: [String: Any] = ["items": rows]
                if let nextCursor { connection["nextCursor"] = nextCursor }
                return ["data": ["meetingSessions": connection]]
            }
            let vars = request["variables"] as! [String: Any]
            return ["data": ["meetingSession": rows.first { $0["id"] as? String == vars["id"] as? String }!]]
        }
        return MeetingSessionHistoryService(session: URLSession(configuration: configuration))
    }

    static func main() async throws {
        let draft = SessionDraft(turns: [.init(id: localID, speakerLabel: nil, text: "words", translationSpeakerLabel: nil, translationText: "слова", timestamp: date, isClosed: true)], subtitlesText: "words", translatedText: "слова", transcriptSummaryText: "", translationSummaryText: "", transcriptProtocolText: "", translationProtocolText: "", transcriptAnswerText: "", translationAnswerText: "")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var legacyJSON = try JSONSerialization.jsonObject(with: encoder.encode(draft)) as! [String: Any]
        legacyJSON.removeValue(forKey: "history")
        var restored = try decoder.decode(SessionDraft.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        check(restored.history == nil && restored.turns[0].id == localID && restored.turns[0].translationText == "слова", "Legacy draft must retain original turn IDs, text and translation")
        restored.history = MeetingHistoryCheckpoint(sessionID: "today", revision: 7, startedAt: date, endedAt: date.addingTimeInterval(1644), source: "system_audio+microphone", conversationID: localID, authUserID: "owner", needsLegacyRecovery: false, inputLanguage: "en", translationLanguage: "ru", translationEnabled: true, recordingEnabled: false)
        let roundtrip = try decoder.decode(SessionDraft.self, from: encoder.encode(restored))
        check(roundtrip.history == restored.history, "Restart must retain remote ID, revision, owner, dates and configuration")
        print("PASS legacy draft migration and checkpoint roundtrip")

        let recovered = try await service(rows: [row()]).findRecoverableSession(snapshot: snapshot(), allowLegacyRecovery: true)
        check(recovered?.id == "today" && recovered?.revision == 1, "Recover today's empty original row")
        let fresh = try await service(rows: [row()]).findRecoverableSession(snapshot: snapshot())
        check(fresh == nil, "A new meeting must not adopt a nearby legacy row")
        let filled = try await service(rows: [row(revision: 2, text: "Other meeting")]).findRecoverableSession(snapshot: snapshot(), allowLegacyRecovery: true)
        check(filled == nil, "Never overwrite another meeting's content")
        let same = try await service(rows: [row(revision: 8, text: "words", localID: localID.uuidString.lowercased())]).findRecoverableSession(snapshot: snapshot())
        check(same?.revision == 8, "Recover same client ID after a lost create response")
        print("PASS recovery identity and overwrite protection")

        do {
            _ = try await service(rows: [row(id: "a"), row(id: "b")]).findRecoverableSession(snapshot: snapshot(), allowLegacyRecovery: true)
            preconditionFailure("Ambiguous recovery must fail")
        } catch MeetingSessionHistoryServiceError.graphqlRequestFailed { }
        do {
            _ = try await service(rows: [row()], nextCursor: "more").findRecoverableSession(snapshot: snapshot(), allowLegacyRecovery: true)
            preconditionFailure("Partial candidate list must fail")
        } catch MeetingSessionHistoryServiceError.graphqlRequestFailed { }
        print("PASS ambiguous and paginated recovery fails safely")

        let api = service(rows: [])
        var revisions = [Int]()
        MockHistoryTransport.handler = { request in
            let query = request["query"] as! String
            if query.contains("mutation UpdateMeetingSession") {
                let vars = request["variables"] as! [String: Any]
                let input = vars["input"] as! [String: Any]
                let revision = input["revision"] as! Int
                revisions.append(revision)
                check(input["status"] as? String == "completed", "Stop must save completed status")
                check(input["durationSeconds"] as? Int == 1644, "Duration must use the original stop time")
                check((input["transcriptJson"] as! [[String: Any]])[0]["text"] as? String == "Saved words", "Upload transcript")
                check((input["translationJson"] as! [[String: Any]])[0]["text"] as? String == "Сохранённые слова", "Upload translation")
                if revision == 1 { return ["errors": [["message": "Meeting session has an outdated revision"]]] }
                return ["data": ["updateMeetingSession": ["id": "today", "revision": 10]]]
            }
            return ["data": ["meetingSession": ["id": "today", "revision": 9]]]
        }
        let saved = try await api.updateSession(id: "today", revision: 1, snapshot: snapshot())
        check(saved.revision == 10 && revisions == [1, 9], "Fetch latest revision and retry the same content")
        print("PASS completion payload and revision-conflict retry")
    }
}
