import Foundation

enum MeetingSessionHistoryStatus: String {
    case active
    case completed
}

struct MeetingSessionHistorySessionParams: Codable, Equatable {
    let client: String
    let source: String
    let appVersion: String?
    let focusMode: Bool?
}

struct MeetingSessionTranscriptBlock: Codable, Equatable {
    let id: String
    let seq: Int
    let timestamp: String
    let speakerLabel: String?
    let text: String
}

struct MeetingSessionTranslationBlock: Codable, Equatable {
    let transcriptBlockId: String
    let seq: Int
    let language: String
    let text: String
}

struct MeetingSessionHistoryListQuery: Equatable {
    let limit: Int
    let cursor: String?
    let searchQuery: String?
    let dateFrom: Date?
    let dateTo: Date?

    init(
        limit: Int = 20,
        cursor: String? = nil,
        searchQuery: String? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil
    ) {
        self.limit = min(max(limit, 1), 100)
        self.cursor = cursor
        self.searchQuery = searchQuery
        self.dateFrom = dateFrom
        self.dateTo = dateTo
    }
}

struct MeetingSessionHistoryListPage: Equatable {
    let items: [MeetingSessionHistoryListItem]
    let nextCursor: String?
}

struct MeetingSessionHistoryListItem: Decodable, Equatable, Identifiable {
    let id: String
    let title: String?
    let status: String
    let startedAt: Date
    let updatedAt: Date
    let durationSeconds: Int?
    let processedByApp: String?
    let previewText: String?
    let inputLanguage: String?
    let translationLanguage: String?
    let translationEnabled: Bool
    let recordingEnabled: Bool
    let wordCount: Int?
    let lineCount: Int?
    let hasSummary: Bool
    let hasProtocol: Bool
    let hasSuggestedAnswer: Bool
}

struct MeetingSessionHistoryStats: Decodable, Equatable {
    let wordCount: Int?
    let lineCount: Int?
    let hasSummary: Bool?
    let hasProtocol: Bool?
    let hasSuggestedAnswer: Bool?
}

struct MeetingSessionHistoryDetail: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String?
    let title: String?
    let status: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int?
    let processedByApp: String?
    let inputLanguage: String?
    let translationLanguage: String?
    let translationEnabled: Bool
    let recordingEnabled: Bool
    let microphoneLabel: String?
    let previewText: String?
    let transcriptText: String?
    let transcriptJson: [MeetingSessionTranscriptBlock]?
    let translationText: String?
    let translationJson: [MeetingSessionTranslationBlock]?
    let summaryText: String?
    let protocolText: String?
    let suggestedAnswerText: String?
    let sessionParams: MeetingSessionHistorySessionParams?
    let statsJson: MeetingSessionHistoryStats?
    let wordCount: Int?
    let lineCount: Int?
    let revision: Int
    let createdAt: Date?
    let updatedAt: Date
    let deletedAt: Date?
    let hasSummary: Bool
    let hasProtocol: Bool
    let hasSuggestedAnswer: Bool
}

struct MeetingSessionHistorySnapshot: Equatable {
    let title: String?
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int?
    let status: MeetingSessionHistoryStatus
    let inputLanguage: String
    let translationLanguage: String?
    let translationEnabled: Bool
    let recordingEnabled: Bool
    let microphoneLabel: String?
    let transcriptBlocks: [MeetingSessionTranscriptBlock]
    let translationBlocks: [MeetingSessionTranslationBlock]
    let summaryText: String?
    let protocolText: String?
    let suggestedAnswerText: String?
    let sessionParams: MeetingSessionHistorySessionParams

    var signature: String {
        [
            title ?? "",
            status.rawValue,
            startedAt.iso8601String,
            endedAt?.iso8601String ?? "",
            String(durationSeconds ?? 0),
            inputLanguage,
            translationLanguage ?? "",
            String(translationEnabled),
            String(recordingEnabled),
            microphoneLabel ?? "",
            summaryText ?? "",
            protocolText ?? "",
            suggestedAnswerText ?? "",
            sessionParams.client,
            sessionParams.source,
            sessionParams.appVersion ?? "",
            sessionParams.focusMode.map(String.init) ?? "",
            transcriptBlocks
                .map { "\($0.id)|\($0.seq)|\($0.timestamp)|\($0.speakerLabel ?? "")|\($0.text)" }
                .joined(separator: "||"),
            translationBlocks
                .map { "\($0.transcriptBlockId)|\($0.seq)|\($0.language)|\($0.text)" }
                .joined(separator: "||"),
        ]
        .joined(separator: "::")
    }
}

struct MeetingSessionHistoryRemoteState: Equatable {
    let id: String
    let revision: Int
}

enum MeetingSessionHistoryServiceError: LocalizedError {
    case missingAuthSession
    case invalidBackendBaseURL(String)
    case invalidResponse
    case graphqlRequestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAuthSession:
            return "Sign in to sync meeting history."
        case .invalidBackendBaseURL(let value):
            return "The meeting history backend URL is invalid: \(value)"
        case .invalidResponse:
            return "The meeting history backend returned a response Speechara could not understand."
        case .graphqlRequestFailed(let message):
            return message
        }
    }
}

final class MeetingSessionHistoryService {
    private struct Configuration {
        let graphQLEndpoint: URL
        let workspaceID: String
    }

    private struct GraphQLErrorPayload: Decodable {
        let message: String?
    }

    private struct GraphQLEnvelope<DataPayload: Decodable>: Decodable {
        let data: DataPayload?
        let errors: [GraphQLErrorPayload]?
    }

    fileprivate struct StartMeetingSessionInput: Encodable {
        let workspaceId: String
        let title: String?
        let startedAt: String
        let processedByApp: String
        let inputLanguage: String
        let translationLanguage: String?
        let translationEnabled: Bool
        let recordingEnabled: Bool
        let microphoneLabel: String?
        let sessionParams: MeetingSessionHistorySessionParams
    }

    fileprivate struct UpdateMeetingSessionInput: Encodable {
        let revision: Int
        let status: String
        let processedByApp: String
        let transcriptJson: [MeetingSessionTranscriptBlock]
        let translationJson: [MeetingSessionTranslationBlock]
        let summaryText: String?
        let protocolText: String?
        let suggestedAnswerText: String?
        let inputLanguage: String
        let translationLanguage: String?
        let translationEnabled: Bool
        let recordingEnabled: Bool
        let microphoneLabel: String?
        let durationSeconds: Int?
        let endedAt: String?
        let sessionParams: MeetingSessionHistorySessionParams
    }

    fileprivate struct RemoteSessionResponse: Decodable {
        let id: String
        let revision: Int
    }

    private let session: URLSession
    private let authService: AuthService
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        session: URLSession = .shared,
        authService: AuthService = .shared
    ) {
        self.session = session
        self.authService = authService

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try MeetingSessionHistoryService.decodeBackendDate(from: decoder)
        }
        self.decoder = decoder

        self.encoder = JSONEncoder()
    }

    func fetchSessions(
        query listQuery: MeetingSessionHistoryListQuery = MeetingSessionHistoryListQuery()
    ) async throws -> MeetingSessionHistoryListPage {
        let activeSession = try await resolvedAuthSession()
        let configuration = try makeConfiguration(for: activeSession)

        let data = try await performGraphQLRequest(
            endpoint: configuration.graphQLEndpoint,
            accessToken: activeSession.accessToken,
            query: """
            query MeetingSessions($workspaceId: ID!, $limit: Int, $cursor: String, $q: String, $dateFrom: String, $dateTo: String) {
              meetingSessions(workspaceId: $workspaceId, limit: $limit, cursor: $cursor, q: $q, dateFrom: $dateFrom, dateTo: $dateTo) {
                items {
                  id
                  title
                  status
                  startedAt
                  updatedAt
                  durationSeconds
                  processedByApp
                  previewText
                  inputLanguage
                  translationLanguage
                  translationEnabled
                  recordingEnabled
                  wordCount
                  lineCount
                  hasSummary
                  hasProtocol
                  hasSuggestedAnswer
                }
                nextCursor
              }
            }
            """,
            variables: MeetingSessionsVariables(
                workspaceId: configuration.workspaceID,
                limit: listQuery.limit,
                cursor: listQuery.cursor?.trimmedOrNil,
                q: listQuery.searchQuery?.trimmedOrNil,
                dateFrom: listQuery.dateFrom?.iso8601String,
                dateTo: listQuery.dateTo?.iso8601String
            ),
            responseType: MeetingSessionsResponse.self
        )

        return MeetingSessionHistoryListPage(
            items: data.meetingSessions.items,
            nextCursor: data.meetingSessions.nextCursor
        )
    }

    func fetchSessionDetail(id: String) async throws -> MeetingSessionHistoryDetail {
        let activeSession = try await resolvedAuthSession()
        let configuration = try makeConfiguration(for: activeSession)

        let data = try await performGraphQLRequest(
            endpoint: configuration.graphQLEndpoint,
            accessToken: activeSession.accessToken,
            query: """
            query MeetingSession($id: ID!) {
              meetingSession(id: $id) {
                id
                workspaceId
                title
                status
                startedAt
                endedAt
                durationSeconds
                processedByApp
                inputLanguage
                translationLanguage
                translationEnabled
                recordingEnabled
                microphoneLabel
                previewText
                transcriptText
                transcriptJson
                translationText
                translationJson
                summaryText
                protocolText
                suggestedAnswerText
                sessionParams
                statsJson
                wordCount
                lineCount
                revision
                createdAt
                updatedAt
                deletedAt
                hasSummary
                hasProtocol
                hasSuggestedAnswer
              }
            }
            """,
            variables: MeetingSessionVariables(id: id),
            responseType: MeetingSessionDetailResponse.self
        )

        return data.meetingSession
    }

    func startSession(snapshot: MeetingSessionHistorySnapshot) async throws -> MeetingSessionHistoryRemoteState {
        let activeSession = try await resolvedAuthSession()
        let configuration = try makeConfiguration(for: activeSession)

        let data = try await performGraphQLRequest(
            endpoint: configuration.graphQLEndpoint,
            accessToken: activeSession.accessToken,
            query: """
            mutation StartMeetingSession($input: StartMeetingSessionInput!) {
              startMeetingSession(input: $input) {
                id
                revision
              }
            }
            """,
            variables: StartMeetingSessionVariables(
                input: StartMeetingSessionInput(
                    workspaceId: configuration.workspaceID,
                    title: snapshot.title,
                    startedAt: snapshot.startedAt.iso8601String,
                    processedByApp: "macos",
                    inputLanguage: snapshot.inputLanguage,
                    translationLanguage: snapshot.translationLanguage,
                    translationEnabled: snapshot.translationEnabled,
                    recordingEnabled: snapshot.recordingEnabled,
                    microphoneLabel: snapshot.microphoneLabel,
                    sessionParams: snapshot.sessionParams
                )
            ),
            responseType: StartMeetingSessionResponse.self
        )

        return MeetingSessionHistoryRemoteState(
            id: data.startMeetingSession.id,
            revision: data.startMeetingSession.revision
        )
    }

    func updateSession(
        id: String,
        revision: Int,
        snapshot: MeetingSessionHistorySnapshot
    ) async throws -> MeetingSessionHistoryRemoteState {
        let activeSession = try await resolvedAuthSession()
        let configuration = try makeConfiguration(for: activeSession)

        do {
            return try await updateSession(
                endpoint: configuration.graphQLEndpoint,
                accessToken: activeSession.accessToken,
                id: id,
                revision: revision,
                snapshot: snapshot
            )
        } catch {
            guard isOutdatedRevisionError(error) else {
                throw error
            }

            let latestState = try await fetchRemoteState(
                endpoint: configuration.graphQLEndpoint,
                accessToken: activeSession.accessToken,
                id: id
            )

            return try await updateSession(
                endpoint: configuration.graphQLEndpoint,
                accessToken: activeSession.accessToken,
                id: id,
                revision: latestState.revision,
                snapshot: snapshot
            )
        }
    }

    func isOutdatedRevisionError(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("revision is outdated")
    }

    private func updateSession(
        endpoint: URL,
        accessToken: String,
        id: String,
        revision: Int,
        snapshot: MeetingSessionHistorySnapshot
    ) async throws -> MeetingSessionHistoryRemoteState {
        let data = try await performGraphQLRequest(
            endpoint: endpoint,
            accessToken: accessToken,
            query: """
            mutation UpdateMeetingSession($id: ID!, $input: UpdateMeetingSessionInput!) {
              updateMeetingSession(id: $id, input: $input) {
                id
                revision
              }
            }
            """,
            variables: UpdateMeetingSessionVariables(
                id: id,
                input: UpdateMeetingSessionInput(
                    revision: revision,
                    status: snapshot.status.rawValue,
                    processedByApp: "macos",
                    transcriptJson: snapshot.transcriptBlocks,
                    translationJson: snapshot.translationBlocks,
                    summaryText: snapshot.summaryText,
                    protocolText: snapshot.protocolText,
                    suggestedAnswerText: snapshot.suggestedAnswerText,
                    inputLanguage: snapshot.inputLanguage,
                    translationLanguage: snapshot.translationLanguage,
                    translationEnabled: snapshot.translationEnabled,
                    recordingEnabled: snapshot.recordingEnabled,
                    microphoneLabel: snapshot.microphoneLabel,
                    durationSeconds: snapshot.durationSeconds,
                    endedAt: snapshot.endedAt?.iso8601String,
                    sessionParams: snapshot.sessionParams
                )
            ),
            responseType: UpdateMeetingSessionResponse.self
        )

        return MeetingSessionHistoryRemoteState(
            id: data.updateMeetingSession.id,
            revision: data.updateMeetingSession.revision
        )
    }

    private func fetchRemoteState(
        endpoint: URL,
        accessToken: String,
        id: String
    ) async throws -> MeetingSessionHistoryRemoteState {
        let data = try await performGraphQLRequest(
            endpoint: endpoint,
            accessToken: accessToken,
            query: """
            query MeetingSession($id: ID!) {
              meetingSession(id: $id) {
                id
                revision
              }
            }
            """,
            variables: MeetingSessionVariables(id: id),
            responseType: MeetingSessionStateResponse.self
        )

        return MeetingSessionHistoryRemoteState(
            id: data.meetingSession.id,
            revision: data.meetingSession.revision
        )
    }

    private func resolvedAuthSession() async throws -> AuthSession {
        do {
            return try await authService.activeSession()
        } catch {
            if let authError = error as? AuthServiceError,
               case .requestFailed = authError {
                throw MeetingSessionHistoryServiceError.missingAuthSession
            }

            throw error
        }
    }

    private func makeConfiguration(for session: AuthSession) throws -> Configuration {
        guard let rawBaseURL = AppConfigurationStore.shared.resolvedValue(for: .authBackendBaseURL),
              let baseURL = URL(string: rawBaseURL) else {
            let value = AppConfigurationStore.shared.resolvedValue(for: .authBackendBaseURL) ?? ""
            throw MeetingSessionHistoryServiceError.invalidBackendBaseURL(value)
        }

        let workspaceID = resolvedWorkspaceID(from: session)
        return Configuration(
            graphQLEndpoint: baseURL.appendingPathComponent("graphql"),
            workspaceID: workspaceID
        )
    }

    private func resolvedWorkspaceID(from session: AuthSession) -> String {
        let candidates: [String?] = [
            session.user.currentWorkspaceID,
            session.user.defaultWorkspaceID,
            session.user.workspaceID,
            session.user.currentWorkspace?.id,
            session.user.defaultWorkspace?.id,
            session.user.workspace?.id,
            session.user.workspaces?.first?.id,
            AppConfigurationStore.shared.resolvedValue(for: .defaultWorkspaceID),
        ]

        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return AppConfigurationKind.defaultWorkspaceID.defaultValue ?? ""
    }

    private func performGraphQLRequest<ResponseType: Decodable, Variables: Encodable>(
        endpoint: URL,
        accessToken: String,
        query: String,
        variables: Variables,
        responseType: ResponseType.Type
    ) async throws -> ResponseType {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(GraphQLRequest(query: query, variables: variables))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeetingSessionHistoryServiceError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let message = graphqlErrorMessage(from: data) {
                throw MeetingSessionHistoryServiceError.graphqlRequestFailed(message)
            }

            throw MeetingSessionHistoryServiceError.invalidResponse
        }

        let payload = try decoder.decode(GraphQLEnvelope<ResponseType>.self, from: data)
        if let errors = payload.errors, !errors.isEmpty {
            let message = errors.compactMap(\.message).first ?? "GraphQL request failed."
            throw MeetingSessionHistoryServiceError.graphqlRequestFailed(message)
        }

        guard let responseData = payload.data else {
            throw MeetingSessionHistoryServiceError.invalidResponse
        }

        return responseData
    }

    private func graphqlErrorMessage(from data: Data) -> String? {
        guard let payload = try? decoder.decode(GraphQLEnvelope<EmptyGraphQLData>.self, from: data) else {
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return payload.errors?.compactMap(\.message).first
    }

    private static func decodeBackendDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        let standardFormatter = ISO8601DateFormatter()
        if let date = standardFormatter.date(from: rawValue) {
            return date
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: rawValue) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected ISO 8601 date string, got \(rawValue)."
        )
    }
}

private struct GraphQLRequest<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables
}

private struct EmptyGraphQLData: Decodable {}

private struct MeetingSessionsConnection: Decodable {
    let items: [MeetingSessionHistoryListItem]
    let nextCursor: String?
}

private struct MeetingSessionsResponse: Decodable {
    let meetingSessions: MeetingSessionsConnection
}

private struct MeetingSessionDetailResponse: Decodable {
    let meetingSession: MeetingSessionHistoryDetail
}

private struct StartMeetingSessionResponse: Decodable {
    let startMeetingSession: MeetingSessionHistoryService.RemoteSessionResponse
}

private struct UpdateMeetingSessionResponse: Decodable {
    let updateMeetingSession: MeetingSessionHistoryService.RemoteSessionResponse
}

private struct MeetingSessionStateResponse: Decodable {
    let meetingSession: MeetingSessionHistoryService.RemoteSessionResponse
}

private struct MeetingSessionsVariables: Encodable {
    let workspaceId: String
    let limit: Int
    let cursor: String?
    let q: String?
    let dateFrom: String?
    let dateTo: String?
}

private struct StartMeetingSessionVariables: Encodable {
    let input: MeetingSessionHistoryService.StartMeetingSessionInput
}

private struct UpdateMeetingSessionVariables: Encodable {
    let id: String
    let input: MeetingSessionHistoryService.UpdateMeetingSessionInput
}

private struct MeetingSessionVariables: Encodable {
    let id: String
}

private extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Date {
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: self)
    }
}
