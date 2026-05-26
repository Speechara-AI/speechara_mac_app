import Foundation

struct SpeecharaChatMessage: Codable, Equatable {
    let role: String
    let content: String
}

struct SpeecharaChatCompletionRequest: Encodable {
    let model: String
    let messages: [SpeecharaChatMessage]
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

struct SpeecharaChatCompletionResponse: Decodable {
    let choices: [SpeecharaChatCompletionChoice]
}

struct SpeecharaChatCompletionChoice: Decodable {
    let message: SpeecharaChatCompletionChoiceMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

struct SpeecharaChatCompletionChoiceMessage: Decodable {
    let content: String?
}

enum SpeecharaBackendProxyError: LocalizedError {
    case authenticationRequired
    case invalidBackendBaseURL(String)
    case invalidRequest
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Sign in to use Speechara AI and live transcription features."
        case .invalidBackendBaseURL(let value):
            return "The saved Speechara backend URL is invalid: \(value)"
        case .invalidRequest:
            return "Speechara could not create the backend proxy request."
        case .invalidResponse:
            return "The Speechara backend returned a response the app could not understand."
        case .serverError(let message):
            return message
        }
    }
}

actor SpeecharaBackendProxyService {
    private struct ProxyContext {
        let baseURL: URL
        let accessToken: String
        let refreshToken: String
        let origin: String
    }

    private struct ProxyErrorEnvelope: Decodable {
        let error: ProxyErrorBody
    }

    private struct ProxyErrorBody: Decodable {
        let message: String?
    }

    private let session: URLSession
    private let authService: AuthService
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        session: URLSession = .shared,
        authService: AuthService = .shared
    ) {
        self.session = session
        self.authService = authService
    }

    func performChatCompletion(
        _ requestBody: SpeecharaChatCompletionRequest
    ) async throws -> SpeecharaChatCompletionResponse {
        let context = try await proxyContext()
        let url = try makeURL(
            baseURL: context.baseURL,
            path: "/api/ai/deepseek/chat/completions"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(context.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(data: data, response: response)

        guard !data.isEmpty else {
            throw SpeecharaBackendProxyError.invalidResponse
        }

        do {
            return try decoder.decode(SpeecharaChatCompletionResponse.self, from: data)
        } catch {
            throw SpeecharaBackendProxyError.invalidResponse
        }
    }

    func makeWebSocketRequest(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> URLRequest {
        let context = try await proxyContext()
        let url = try makeURL(
            baseURL: context.baseURL,
            path: path,
            schemeOverride: context.baseURL.scheme == "https" ? "wss" : "ws",
            queryItems: queryItems
        )

        var request = URLRequest(url: url)
        request.setValue("speechara_refresh_token=\(context.refreshToken)", forHTTPHeaderField: "Cookie")
        request.setValue(context.origin, forHTTPHeaderField: "Origin")
        return request
    }

    private func proxyContext() async throws -> ProxyContext {
        let authSession: AuthSession
        do {
            authSession = try await authService.activeSession()
        } catch {
            throw SpeecharaBackendProxyError.authenticationRequired
        }

        guard let rawBaseURL = AppConfigurationStore.shared.resolvedValue(for: .authBackendBaseURL),
              let baseURL = URL(string: rawBaseURL),
              let origin = Self.preferredWebSocketOrigin(from: baseURL) else {
            let value = AppConfigurationStore.shared.resolvedValue(for: .authBackendBaseURL) ?? ""
            throw SpeecharaBackendProxyError.invalidBackendBaseURL(value)
        }

        return ProxyContext(
            baseURL: baseURL,
            accessToken: authSession.accessToken,
            refreshToken: authSession.refreshToken,
            origin: origin
        )
    }

    private func makeURL(
        baseURL: URL,
        path: String,
        schemeOverride: String? = nil,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw SpeecharaBackendProxyError.invalidRequest
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, endpointPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        if let schemeOverride {
            components.scheme = schemeOverride
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw SpeecharaBackendProxyError.invalidRequest
        }

        return url
    }

    private func validateHTTPResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeecharaBackendProxyError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let message = parsedErrorMessage(from: data) {
                throw SpeecharaBackendProxyError.serverError(message)
            }

            throw SpeecharaBackendProxyError.serverError(
                "Speechara backend request failed with status \(httpResponse.statusCode)."
            )
        }
    }

    private func parsedErrorMessage(from data: Data) -> String? {
        if let envelope = try? decoder.decode(ProxyErrorEnvelope.self, from: data),
           let message = envelope.error.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }

        if let bodyText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !bodyText.isEmpty {
            return bodyText
        }

        return nil
    }

    private static func preferredWebSocketOrigin(from url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        if let host = components.host, host.hasPrefix("api.") {
            components.host = String(host.dropFirst(4))
        }

        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.string
    }

}

struct SpeecharaBillingSummary: Decodable, Equatable {
    let serverTime: Date
    let subscription: SpeecharaBillingSubscription
    let usage: SpeecharaBillingUsage
}

struct SpeecharaBillingSubscription: Decodable, Equatable {
    let planCode: String?
    let planName: String?
    let status: String
    let startedAt: Date?
    let lastSuccessfulPaymentAt: Date?
    let currentPeriodStart: Date?
    let currentPeriodEnd: Date?
    let cancelAtPeriodEnd: Bool
}

struct SpeecharaBillingUsage: Decodable, Equatable {
    let meteringUnit: String
    let includedSeconds: Int
    let usedSeconds: Int
    let remainingSeconds: Int
    let includedMinutes: Int
    let usedMinutes: Int
    let remainingMinutes: Int
    let isLimitReached: Bool
    let canUseTranscription: Bool
}

struct SpeecharaBillingUsageEvent: Encodable, Equatable {
    let eventId: String
    let meetingSessionId: String?
    let clientSessionId: String
    let sourceApp: String
    let usageType: String
    let startedAt: String
    let endedAt: String
    let durationSeconds: Int
}

struct SpeecharaBillingUsageBatchResponse: Decodable, Equatable {
    let acceptedEvents: Int
    let duplicateEvents: Int
    let rejectedEvents: [SpeecharaBillingRejectedEvent]
    let serverTime: Date
    let subscription: SpeecharaBillingSubscription
    let usage: SpeecharaBillingUsage
}

struct SpeecharaBillingRejectedEvent: Decodable, Equatable {
    let eventId: String?
    let reason: String?
    let detail: String?
}

enum SpeecharaBillingServiceError: LocalizedError {
    case authenticationRequired
    case invalidBackendBaseURL(String)
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Sign in to load billing data."
        case .invalidBackendBaseURL(let value):
            return "The saved Speechara backend URL is invalid: \(value)"
        case .invalidResponse:
            return "The billing backend returned a response Speechara could not understand."
        case .requestFailed(let message):
            return message
        }
    }
}

final class SpeecharaBillingService {
    private struct Configuration {
        let baseURL: URL
        let accessToken: String
    }

    private struct ProblemDetail: Decodable {
        let title: String?
        let detail: String?
        let status: Int?

        var resolvedMessage: String? {
            let normalizedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let normalizedDetail, !normalizedDetail.isEmpty,
               let normalizedTitle, !normalizedTitle.isEmpty {
                return "\(normalizedTitle): \(normalizedDetail)"
            }

            if let normalizedDetail, !normalizedDetail.isEmpty {
                return normalizedDetail
            }

            if let normalizedTitle, !normalizedTitle.isEmpty {
                return normalizedTitle
            }

            return nil
        }
    }

    private struct UsageEventsRequest: Encodable {
        let events: [SpeecharaBillingUsageEvent]
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
            try SpeecharaBillingService.decodeBackendDate(from: decoder)
        }
        self.decoder = decoder

        self.encoder = JSONEncoder()
    }

    func fetchSummary() async throws -> SpeecharaBillingSummary {
        let configuration = try await makeConfiguration()
        let url = configuration.baseURL.appendingPathComponent("api/billing/summary")
        return try await performRequest(
            url: url,
            method: "GET",
            body: Optional<UsageEventsRequest>.none,
            accessToken: configuration.accessToken
        )
    }

    func reportUsageEvents(_ events: [SpeecharaBillingUsageEvent]) async throws -> SpeecharaBillingUsageBatchResponse {
        let configuration = try await makeConfiguration()
        let url = configuration.baseURL.appendingPathComponent("api/billing/usage-events")
        return try await performRequest(
            url: url,
            method: "POST",
            body: UsageEventsRequest(events: events),
            accessToken: configuration.accessToken
        )
    }

    private func makeConfiguration() async throws -> Configuration {
        let authSession: AuthSession
        do {
            authSession = try await authService.activeSession()
        } catch {
            throw SpeecharaBillingServiceError.authenticationRequired
        }

        guard let rawBaseURL = AppConfigurationStore.shared.resolvedValue(for: .authBackendBaseURL),
              let baseURL = URL(string: rawBaseURL) else {
            let value = AppConfigurationStore.shared.resolvedValue(for: .authBackendBaseURL) ?? ""
            throw SpeecharaBillingServiceError.invalidBackendBaseURL(value)
        }

        return Configuration(
            baseURL: baseURL,
            accessToken: authSession.accessToken
        )
    }

    private func performRequest<Response: Decodable, Body: Encodable>(
        url: URL,
        method: String,
        body: Body?,
        accessToken: String
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeecharaBillingServiceError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let problem = try? decoder.decode(ProblemDetail.self, from: data),
               let message = problem.resolvedMessage {
                throw SpeecharaBillingServiceError.requestFailed(message)
            }

            if let bodyText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !bodyText.isEmpty {
                throw SpeecharaBillingServiceError.requestFailed(bodyText)
            }

            throw SpeecharaBillingServiceError.requestFailed(
                "Billing request failed with status \(httpResponse.statusCode)."
            )
        }

        guard !data.isEmpty else {
            throw SpeecharaBillingServiceError.invalidResponse
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw SpeecharaBillingServiceError.invalidResponse
        }
    }

    private static func decodeBackendDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: rawValue) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: rawValue) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected ISO 8601 date string, got \(rawValue)."
        )
    }
}

enum AppConfigurationKind: CaseIterable, Identifiable {
    case authBackendBaseURL
    case microsoftClientID
    case defaultWorkspaceID

    var id: Self { self }

    var environmentKey: String {
        switch self {
        case .authBackendBaseURL:
            return "SPEECHARA_AUTH_BASE_URL"
        case .microsoftClientID:
            return "SPEECHARA_MICROSOFT_CLIENT_ID"
        case .defaultWorkspaceID:
            return "SPEECHARA_DEFAULT_WORKSPACE_ID"
        }
    }

    var defaultsKey: String {
        switch self {
        case .authBackendBaseURL:
            return "speechara.savedAuthBackendBaseURL"
        case .microsoftClientID:
            return "speechara.savedMicrosoftClientID"
        case .defaultWorkspaceID:
            return "speechara.savedDefaultWorkspaceID"
        }
    }

    var displayName: String {
        switch self {
        case .authBackendBaseURL:
            return "Auth backend URL"
        case .microsoftClientID:
            return "Microsoft client ID"
        case .defaultWorkspaceID:
            return "Default workspace ID"
        }
    }

    var defaultValue: String? {
        switch self {
        case .authBackendBaseURL:
            return "https://api.speechara.ai"
        case .microsoftClientID:
            return nil
        case .defaultWorkspaceID:
            return "2b7f6b0d-5a5e-4f35-9f5d-8e7b4a0c6f21"
        }
    }
}

final class AppConfigurationStore {
    static let shared = AppConfigurationStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        removeLegacyVendorSecrets()
    }

    func resolvedValue(for kind: AppConfigurationKind) -> String? {
        if let environmentValue = environmentValue(for: kind) {
            return environmentValue
        }

        if let savedValue = savedValue(for: kind) {
            return savedValue
        }

        return kind.defaultValue
    }

    func environmentValue(for kind: AppConfigurationKind) -> String? {
        let rawValue = ProcessInfo.processInfo.environment[kind.environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        return rawValue
    }

    func savedValue(for kind: AppConfigurationKind) -> String? {
        let rawValue = defaults.string(forKey: kind.defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        return rawValue
    }

    func save(_ value: String, for kind: AppConfigurationKind) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty {
            defaults.removeObject(forKey: kind.defaultsKey)
            return
        }

        defaults.set(trimmedValue, forKey: kind.defaultsKey)
    }

    private func removeLegacyVendorSecrets() {
        defaults.removeObject(forKey: "speechara.savedDeepgramAPIKey")
        defaults.removeObject(forKey: "speechara.savedDeepSeekAPIKey")
    }
}
