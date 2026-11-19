import Foundation

struct SpeakingNotesServiceError: LocalizedError, Equatable {
    let message: String
    let code: String?

    var errorDescription: String? { message }
    var isConflict: Bool { code == "CONFLICT" || message.localizedCaseInsensitiveContains("revision") }
    var isNotFound: Bool { code == "NOT_FOUND" }
}

final class SpeakingNotesGraphQLService {
    private struct Configuration {
        let endpoint: URL
        let accessToken: String
        let workspaceID: String
    }

    private struct GraphQLErrorPayload: Decodable {
        struct Extensions: Decodable { let code: String? }
        let message: String?
        let extensions: Extensions?
    }

    private struct Envelope<Payload: Decodable>: Decodable {
        let data: Payload?
        let errors: [GraphQLErrorPayload]?
    }

    private struct Request<Variables: Encodable>: Encodable {
        let query: String
        let variables: Variables
    }

    private struct EmptyVariables: Encodable {}
    private struct IDVariables: Encodable { let id: String }
    private struct ListVariables: Encodable { let workspaceId: String; let limit: Int; let cursor: String? }
    private struct NoteResponse: Decodable { let speakingNote: SpeakingNote }
    private struct CreateResponse: Decodable { let createSpeakingNote: SpeakingNote }
    private struct UpdateResponse: Decodable { let updateSpeakingNote: SpeakingNote }
    private struct TransformResponse: Decodable { let transformSpeakingNote: SpeakingNote }
    private struct DuplicateResponse: Decodable { let duplicateSpeakingNote: SpeakingNote }
    private struct DeletePayload: Decodable { let id: String; let revision: Int; let deletedAt: String? }
    private struct DeleteResponse: Decodable { let deleteSpeakingNote: DeletePayload }
    private struct SnapshotResponse: Decodable { let meetingSessionSpeakingNote: MeetingSpeakingNoteSnapshot? }
    private struct AttachResponse: Decodable { let setMeetingSessionSpeakingNote: MeetingSpeakingNoteSnapshot }
    private struct ListConnection: Decodable { let items: [SpeakingNoteListItem]; let nextCursor: String? }
    private struct ListResponse: Decodable { let speakingNotes: ListConnection }

    private struct CreateInput: Encodable {
        let workspaceId: String
        let title: String
        let activeLanguage: SpeakingNoteLanguage
        let activeMode: SpeakingNoteMode
        let content: SpeakingNoteContent
    }

    private struct CreateVariables: Encodable { let input: CreateInput }

    private struct UpdateInput: Encodable {
        let revision: Int
        let title: String
        let activeLanguage: SpeakingNoteLanguage
        let activeMode: SpeakingNoteMode
        let content: SpeakingNoteContent
    }

    private struct UpdateVariables: Encodable { let id: String; let input: UpdateInput }

    private struct TransformInput: Encodable {
        let revision: Int
        let operation: SpeakingNoteTransformOperation
        let sourceLanguage: SpeakingNoteLanguage
        let targetLanguage: SpeakingNoteLanguage?
    }

    private struct TransformVariables: Encodable { let id: String; let input: TransformInput }
    private struct DeleteVariables: Encodable { let id: String; let revision: Int }
    private struct MeetingVariables: Encodable { let meetingSessionId: String }
    private struct AttachVariables: Encodable { let meetingSessionId: String; let speakingNoteId: String }

    private let session: URLSession
    private let authService: AuthService
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared, authService: AuthService = .shared) {
        self.session = session
        self.authService = authService
    }

    func workspaceID() async throws -> String {
        try await configuration().workspaceID
    }

    func list(limit: Int = 50, cursor: String? = nil) async throws -> (items: [SpeakingNoteListItem], nextCursor: String?) {
        let configuration = try await configuration()
        let response: ListResponse = try await request(
            configuration: configuration,
            query: """
            query SpeakingNotes($workspaceId: ID!, $limit: Int, $cursor: String) {
              speakingNotes(workspaceId: $workspaceId, limit: $limit, cursor: $cursor) {
                nextCursor
                items { id title activeLanguage activeMode revision lastUsedAt createdAt updatedAt }
              }
            }
            """,
            variables: ListVariables(workspaceId: configuration.workspaceID, limit: min(max(limit, 1), 100), cursor: cursor)
        )
        return (response.speakingNotes.items, response.speakingNotes.nextCursor)
    }

    func get(id: String) async throws -> SpeakingNote {
        let response: NoteResponse = try await request(
            configuration: try await configuration(),
            query: "query SpeakingNote($id: ID!) { speakingNote(id: $id) { \(Self.noteFields) } }",
            variables: IDVariables(id: id)
        )
        return response.speakingNote
    }

    func create(_ note: SpeakingNote) async throws -> SpeakingNote {
        let configuration = try await configuration()
        let response: CreateResponse = try await request(
            configuration: configuration,
            query: """
            mutation CreateSpeakingNote($input: CreateSpeakingNoteInput!) {
              createSpeakingNote(input: $input) { \(Self.noteFields) }
            }
            """,
            variables: CreateVariables(input: CreateInput(
                workspaceId: configuration.workspaceID,
                title: note.title,
                activeLanguage: note.activeLanguage,
                activeMode: note.activeMode,
                content: note.content
            ))
        )
        return response.createSpeakingNote
    }

    func update(_ note: SpeakingNote) async throws -> SpeakingNote {
        let response: UpdateResponse = try await request(
            configuration: try await configuration(),
            query: """
            mutation UpdateSpeakingNote($id: ID!, $input: UpdateSpeakingNoteInput!) {
              updateSpeakingNote(id: $id, input: $input) { \(Self.noteFields) }
            }
            """,
            variables: UpdateVariables(
                id: note.id,
                input: UpdateInput(
                    revision: note.revision,
                    title: note.title,
                    activeLanguage: note.activeLanguage,
                    activeMode: note.activeMode,
                    content: note.content
                )
            )
        )
        return response.updateSpeakingNote
    }

    func transform(
        id: String,
        revision: Int,
        operation: SpeakingNoteTransformOperation,
        sourceLanguage: SpeakingNoteLanguage,
        targetLanguage: SpeakingNoteLanguage? = nil
    ) async throws -> SpeakingNote {
        let response: TransformResponse = try await request(
            configuration: try await configuration(),
            query: """
            mutation TransformSpeakingNote($id: ID!, $input: TransformSpeakingNoteInput!) {
              transformSpeakingNote(id: $id, input: $input) { \(Self.noteFields) }
            }
            """,
            variables: TransformVariables(
                id: id,
                input: TransformInput(
                    revision: revision,
                    operation: operation,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage
                )
            )
        )
        return response.transformSpeakingNote
    }

    func duplicate(id: String) async throws -> SpeakingNote {
        let response: DuplicateResponse = try await request(
            configuration: try await configuration(),
            query: "mutation DuplicateSpeakingNote($id: ID!) { duplicateSpeakingNote(id: $id) { \(Self.noteFields) } }",
            variables: IDVariables(id: id)
        )
        return response.duplicateSpeakingNote
    }

    func delete(id: String, revision: Int) async throws {
        let _: DeleteResponse = try await request(
            configuration: try await configuration(),
            query: "mutation DeleteSpeakingNote($id: ID!, $revision: Int!) { deleteSpeakingNote(id: $id, revision: $revision) { id revision deletedAt } }",
            variables: DeleteVariables(id: id, revision: revision)
        )
    }

    func attach(noteID: String, to meetingSessionID: String) async throws -> MeetingSpeakingNoteSnapshot {
        let response: AttachResponse = try await request(
            configuration: try await configuration(),
            query: """
            mutation SetMeetingSessionSpeakingNote($meetingSessionId: ID!, $speakingNoteId: ID!) {
              setMeetingSessionSpeakingNote(meetingSessionId: $meetingSessionId, speakingNoteId: $speakingNoteId) {
                \(Self.snapshotFields)
              }
            }
            """,
            variables: AttachVariables(meetingSessionId: meetingSessionID, speakingNoteId: noteID)
        )
        return response.setMeetingSessionSpeakingNote
    }

    func meetingSnapshot(meetingSessionID: String) async throws -> MeetingSpeakingNoteSnapshot? {
        let response: SnapshotResponse = try await request(
            configuration: try await configuration(),
            query: "query MeetingSessionSpeakingNote($meetingSessionId: ID!) { meetingSessionSpeakingNote(meetingSessionId: $meetingSessionId) { \(Self.snapshotFields) } }",
            variables: MeetingVariables(meetingSessionId: meetingSessionID)
        )
        return response.meetingSessionSpeakingNote
    }

    private func configuration() async throws -> Configuration {
        let authSession: AuthSession
        do {
            authSession = try await authService.activeSession()
        } catch {
            throw SpeakingNotesServiceError(message: SL("Sign in to sync speaking notes."), code: "AUTH_REQUIRED")
        }

        guard let rawURL = AppConfigurationStore.shared.resolvedValue(for: .authBackendBaseURL),
              let baseURL = URL(string: rawURL) else {
            throw SpeakingNotesServiceError(message: SL("The Speechara backend URL is invalid."), code: "CONFIGURATION")
        }

        let candidates: [String?] = [
            authSession.user.currentWorkspaceID,
            authSession.user.defaultWorkspaceID,
            authSession.user.workspaceID,
            authSession.user.currentWorkspace?.id,
            authSession.user.defaultWorkspace?.id,
            authSession.user.workspace?.id,
            authSession.user.workspaces?.first?.id,
            AppConfigurationStore.shared.resolvedValue(for: .defaultWorkspaceID),
        ]
        let workspaceID = candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
            ?? AppConfigurationKind.defaultWorkspaceID.defaultValue
            ?? ""

        return Configuration(
            endpoint: baseURL.appendingPathComponent("graphql"),
            accessToken: authSession.accessToken,
            workspaceID: workspaceID
        )
    }

    private func performRequest<Payload: Decodable, Variables: Encodable>(
        configuration configurationValue: Configuration,
        query: String,
        variables: Variables
    ) async throws -> Payload {
        var urlRequest = URLRequest(url: configurationValue.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(configurationValue.accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try encoder.encode(Request(query: query, variables: variables))

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeakingNotesServiceError(message: SL("The speaking notes server returned an invalid response."), code: nil)
        }

        let envelope = try? decoder.decode(Envelope<Payload>.self, from: data)
        if let error = envelope?.errors?.first {
            throw SpeakingNotesServiceError(
                message: error.message ?? SL("Speaking notes request failed."),
                code: error.extensions?.code
            )
        }
        guard (200 ... 299).contains(httpResponse.statusCode), let payload = envelope?.data else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SpeakingNotesServiceError(
                message: message?.isEmpty == false ? message! : SL("Speaking notes request failed."),
                code: nil
            )
        }
        return payload
    }

    private func request<Payload: Decodable, Variables: Encodable>(
        configuration: @autoclosure () async throws -> Configuration,
        query: String,
        variables: Variables
    ) async throws -> Payload {
        try await performRequest(configuration: configuration(), query: query, variables: variables)
    }

    private static let noteFields = """
    id workspaceId title activeLanguage activeMode content revision
    lastUsedAt createdAt updatedAt archivedAt deletedAt
    """

    private static let snapshotFields = """
    meetingSessionId speakingNoteId speakingNoteRevision title activeLanguage activeMode
    content attachedAt capturedAt
    """
}
