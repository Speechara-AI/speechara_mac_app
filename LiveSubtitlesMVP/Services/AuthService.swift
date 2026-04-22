import AppKit
import Combine
import CryptoKit
import Foundation
import Network
import Security

struct AuthenticatedUser: Codable, Equatable {
    struct WorkspaceReference: Codable, Equatable {
        let id: String
    }

    let id: String
    let email: String
    let displayName: String
    let avatarURL: String?
    let workspaceID: String?
    let defaultWorkspaceID: String?
    let currentWorkspaceID: String?
    let newbie: Bool?
    let workspace: WorkspaceReference?
    let defaultWorkspace: WorkspaceReference?
    let currentWorkspace: WorkspaceReference?
    let workspaces: [WorkspaceReference]?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case workspaceID = "workspaceId"
        case defaultWorkspaceID = "defaultWorkspaceId"
        case currentWorkspaceID = "currentWorkspaceId"
        case newbie
        case workspace
        case defaultWorkspace
        case currentWorkspace
        case workspaces
    }

    var initials: String {
        let components = displayName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap { $0.first }

        let value = String(components)
        if !value.isEmpty {
            return value.uppercased()
        }

        return String(email.prefix(1)).uppercased()
    }

    var isNewbie: Bool {
        newbie ?? false
    }

    fileprivate func updating(with profile: CurrentUserProfileResponse) -> AuthenticatedUser {
        AuthenticatedUser(
            id: profile.id.nonEmptyTrimmed ?? id,
            email: profile.email.nonEmptyTrimmed ?? email,
            displayName: profile.displayName.nonEmptyTrimmed ?? displayName,
            avatarURL: profile.avatarURL.nonEmptyTrimmed ?? avatarURL,
            workspaceID: workspaceID,
            defaultWorkspaceID: defaultWorkspaceID,
            currentWorkspaceID: currentWorkspaceID,
            newbie: profile.newbie ?? newbie,
            workspace: workspace,
            defaultWorkspace: defaultWorkspace,
            currentWorkspace: currentWorkspace,
            workspaces: workspaces
        )
    }
}

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresAt: Date
    let user: AuthenticatedUser

    var needsRefresh: Bool {
        expiresAt.timeIntervalSinceNow <= 60
    }

    func updating(user: AuthenticatedUser) -> AuthSession {
        AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresAt: expiresAt,
            user: user
        )
    }
}

private struct CurrentUserProfileResponse: Decodable, Equatable {
    let id: String?
    let email: String?
    let displayName: String?
    let avatarURL: String?
    let newbie: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case newbie
    }
}

private extension Optional where Wrapped == String {
    var nonEmptyTrimmed: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }
}

enum AuthServiceError: LocalizedError {
    case missingBackendBaseURL
    case invalidBackendBaseURL(String)
    case browserOpenFailed
    case invalidCallback
    case callbackStateMismatch
    case callbackMissingCode
    case callbackReturnedError(String)
    case requestFailed(String)
    case invalidResponse
    case timedOutWaitingForGoogle
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .missingBackendBaseURL:
            return "Google sign-in is not configured yet. Add the auth backend URL in Settings first."
        case .invalidBackendBaseURL(let value):
            return "The saved auth backend URL is invalid: \(value)"
        case .browserOpenFailed:
            return "Speechara could not open the system browser for Google sign-in."
        case .invalidCallback:
            return "Speechara received an invalid OAuth callback."
        case .callbackStateMismatch:
            return "The Google sign-in callback did not match the original request."
        case .callbackMissingCode:
            return "Google sign-in completed without an authorization code."
        case .callbackReturnedError(let message):
            return message
        case .requestFailed(let message):
            return message
        case .invalidResponse:
            return "The auth backend returned a response Speechara could not understand."
        case .timedOutWaitingForGoogle:
            return "Google sign-in timed out before Speechara received the browser callback."
        case .userCancelled:
            return "Google sign-in was canceled."
        }
    }
}

final class AuthService {
    static let shared = AuthService()

    private struct Configuration {
        let baseURL: URL
    }

    private struct DeviceInfo: Codable {
        let platform: String
        let deviceName: String
        let appVersion: String
        let buildNumber: String
    }

    private struct AuthorizationStartRequest: Encodable {
        let redirectURI: String
        let state: String
        let codeChallenge: String
        let codeChallengeMethod: String
        let device: DeviceInfo

        enum CodingKeys: String, CodingKey {
            case redirectURI = "redirect_uri"
            case state
            case codeChallenge = "code_challenge"
            case codeChallengeMethod = "code_challenge_method"
            case device
        }
    }

    private struct AuthorizationStartResponse: Decodable {
        let authorizationURL: String

        enum CodingKeys: String, CodingKey {
            case authorizationURL = "authorization_url"
        }
    }

    private struct TokenExchangeRequest: Encodable {
        let code: String
        let state: String
        let codeVerifier: String
        let redirectURI: String
        let device: DeviceInfo

        enum CodingKeys: String, CodingKey {
            case code
            case state
            case codeVerifier = "code_verifier"
            case redirectURI = "redirect_uri"
            case device
        }
    }

    private struct RefreshRequest: Encodable {
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
        }
    }

    private struct LogoutRequest: Encodable {
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
        }
    }

    private struct UpdateCurrentUserRequest: Encodable {
        let newbie: Bool
    }

    private struct SessionResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let tokenType: String
        let expiresAt: Date
        let user: AuthenticatedUser

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case tokenType = "token_type"
            case expiresAt = "expires_at"
            case user
        }

        var session: AuthSession {
            AuthSession(
                accessToken: accessToken,
                refreshToken: refreshToken,
                tokenType: tokenType,
                expiresAt: expiresAt,
                user: user
            )
        }
    }

    private struct APIErrorResponse: Decodable {
        let error: String?
        let message: String?
        let detail: String?
        let title: String?

        var resolvedMessage: String? {
            if let message, !message.isEmpty {
                return message
            }

            if let detail, !detail.isEmpty {
                return detail
            }

            if let error, !error.isEmpty {
                return error
            }

            if let title, !title.isEmpty {
                return title
            }

            return nil
        }
    }

    private struct CallbackPayload {
        let code: String
        let state: String

        init(url: URL) throws {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw AuthServiceError.invalidCallback
            }

            let items = Dictionary(uniqueKeysWithValues: components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])

            if let error = items["error"], !error.isEmpty {
                let description = items["error_description"]?.replacingOccurrences(of: "+", with: " ") ?? error
                throw AuthServiceError.callbackReturnedError(description)
            }

            guard let code = items["code"], !code.isEmpty else {
                throw AuthServiceError.callbackMissingCode
            }

            guard let state = items["state"], !state.isEmpty else {
                throw AuthServiceError.invalidCallback
            }

            self.code = code
            self.state = state
        }
    }

    private struct GoogleAuthTransaction {
        let state: String
        let codeVerifier: String

        init() {
            state = Self.randomURLSafeString(length: 32)
            codeVerifier = Self.randomURLSafeString(length: 64)
        }

        var codeChallenge: String {
            let digest = SHA256.hash(data: Data(codeVerifier.utf8))
            return Data(digest).base64URLEncodedString()
        }

        private static func randomURLSafeString(length: Int) -> String {
            let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            var combined = raw

            while combined.count < length {
                combined.append(UUID().uuidString.replacingOccurrences(of: "-", with: ""))
            }

            return String(combined.prefix(length))
        }
    }

    private let session: URLSession
    private let keychainStore: KeychainStore
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let sessionAccount = "speechara.auth.session"
    private var activeRedirectServer: LoopbackOAuthRedirectServer?

    private init(
        session: URLSession = .shared,
        keychainStore: KeychainStore = KeychainStore(service: "com.alexdem.speechara.auth")
    ) {
        self.session = session
        self.keychainStore = keychainStore

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try AuthService.decodeBackendDate(from: decoder)
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func loadSavedSession() -> AuthSession? {
        guard let data = keychainStore.load(account: sessionAccount) else {
            return nil
        }

        return try? decoder.decode(AuthSession.self, from: data)
    }

    func clearSavedSession() {
        keychainStore.delete(account: sessionAccount)
    }

    func cancelActiveAuthentication() {
        activeRedirectServer?.cancel()
        activeRedirectServer = nil
    }

    func signInWithGoogle() async throws -> AuthSession {
        let configuration = try makeConfiguration()
        let transaction = GoogleAuthTransaction()
        let redirectServer = try LoopbackOAuthRedirectServer(callbackPath: "/oauth/google/callback")

        activeRedirectServer = redirectServer
        defer {
            redirectServer.cancel()
            activeRedirectServer = nil
        }

        try await redirectServer.start()

        let authorizationURL = try await requestAuthorizationURL(
            configuration: configuration,
            transaction: transaction,
            redirectURI: redirectServer.redirectURL
        )

        let didOpenBrowser = await MainActor.run {
            NSWorkspace.shared.open(authorizationURL)
        }

        guard didOpenBrowser else {
            throw AuthServiceError.browserOpenFailed
        }

        let callbackURL = try await redirectServer.waitForCallback(timeout: 300)

        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }

        let payload = try CallbackPayload(url: callbackURL)

        guard payload.state == transaction.state else {
            throw AuthServiceError.callbackStateMismatch
        }

        let authenticatedSession = try await exchangeCode(
            configuration: configuration,
            code: payload.code,
            state: payload.state,
            codeVerifier: transaction.codeVerifier,
            redirectURI: redirectServer.redirectURL
        )

        try persistSession(authenticatedSession)

        return authenticatedSession
    }

    func refreshSession(using refreshToken: String) async throws -> AuthSession {
        let configuration = try makeConfiguration()
        let requestBody = RefreshRequest(refreshToken: refreshToken)
        let response: SessionResponse = try await performJSONRequest(
            url: configuration.baseURL.appendingPathComponent("v1/auth/session/refresh"),
            method: "POST",
            body: requestBody,
            bearerToken: nil
        )

        let refreshedSession = response.session
        try persistSession(refreshedSession)
        return refreshedSession
    }

    func logout(accessToken: String?, refreshToken: String?) async {
        defer {
            clearSavedSession()
        }

        guard let configuration = try? makeConfiguration() else {
            return
        }

        let requestBody = LogoutRequest(refreshToken: refreshToken)

        do {
            let _: EmptyResponse = try await performJSONRequest(
                url: configuration.baseURL.appendingPathComponent("v1/auth/logout"),
                method: "POST",
                body: requestBody,
                bearerToken: accessToken
            )
        } catch {
            // Local logout should still succeed even if the backend call fails.
        }
    }

    func refreshCurrentUserProfile() async throws -> AuthSession {
        let currentSession = try await activeSession()
        let response: CurrentUserProfileResponse = try await performJSONRequest(
            url: makeCurrentUserURL(),
            method: "GET",
            bearerToken: currentSession.accessToken
        )

        let updatedSession = currentSession.updating(
            user: currentSession.user.updating(with: response)
        )
        try persistSession(updatedSession)
        return updatedSession
    }

    func updateCurrentUser(newbie: Bool) async throws -> AuthSession {
        let currentSession = try await activeSession()
        let response: CurrentUserProfileResponse = try await performJSONRequest(
            url: makeCurrentUserURL(),
            method: "PATCH",
            body: UpdateCurrentUserRequest(newbie: newbie),
            bearerToken: currentSession.accessToken
        )

        let updatedSession = currentSession.updating(
            user: currentSession.user.updating(with: response)
        )
        try persistSession(updatedSession)
        return updatedSession
    }

    private func requestAuthorizationURL(
        configuration: Configuration,
        transaction: GoogleAuthTransaction,
        redirectURI: URL
    ) async throws -> URL {
        let requestBody = AuthorizationStartRequest(
            redirectURI: redirectURI.absoluteString,
            state: transaction.state,
            codeChallenge: transaction.codeChallenge,
            codeChallengeMethod: "S256",
            device: Self.currentDeviceInfo
        )

        let response: AuthorizationStartResponse = try await performJSONRequest(
            url: configuration.baseURL.appendingPathComponent("v1/auth/google/native/start"),
            method: "POST",
            body: requestBody,
            bearerToken: nil
        )

        guard let url = URL(string: response.authorizationURL) else {
            throw AuthServiceError.invalidResponse
        }

        return url
    }

    private func exchangeCode(
        configuration: Configuration,
        code: String,
        state: String,
        codeVerifier: String,
        redirectURI: URL
    ) async throws -> AuthSession {
        let requestBody = TokenExchangeRequest(
            code: code,
            state: state,
            codeVerifier: codeVerifier,
            redirectURI: redirectURI.absoluteString,
            device: Self.currentDeviceInfo
        )

        let response: SessionResponse = try await performJSONRequest(
            url: configuration.baseURL.appendingPathComponent("v1/auth/google/native/exchange"),
            method: "POST",
            body: requestBody,
            bearerToken: nil
        )

        return response.session
    }

    private func makeConfiguration() throws -> Configuration {
        guard let rawValue = AppConfigurationStore.shared.resolvedValue(for: .authBackendBaseURL) else {
            throw AuthServiceError.missingBackendBaseURL
        }

        guard let url = URL(string: rawValue) else {
            throw AuthServiceError.invalidBackendBaseURL(rawValue)
        }

        return Configuration(baseURL: url)
    }

    private func makeCurrentUserURL() throws -> URL {
        try makeConfiguration()
            .baseURL
            .appendingPathComponent("v1/auth/me")
    }

    private func persistSession(_ session: AuthSession) throws {
        let data = try encoder.encode(session)
        try keychainStore.save(data, account: sessionAccount)
    }

    func activeSession() async throws -> AuthSession {
        guard let savedSession = loadSavedSession() else {
            throw AuthServiceError.requestFailed("Sign in to sync meeting history.")
        }

        if savedSession.needsRefresh {
            return try await refreshSession(using: savedSession.refreshToken)
        }

        return savedSession
    }

    private func performJSONRequest<Response: Decodable, Body: Encodable>(
        url: URL,
        method: String,
        body: Body?,
        bearerToken: String?
    ) async throws -> Response {
        let bodyData = try body.map { try encoder.encode($0) }
        return try await performJSONRequest(
            url: url,
            method: method,
            bodyData: bodyData,
            bearerToken: bearerToken
        )
    }

    private func performJSONRequest<Response: Decodable>(
        url: URL,
        method: String,
        bearerToken: String?
    ) async throws -> Response {
        try await performJSONRequest(
            url: url,
            method: method,
            bodyData: nil,
            bearerToken: bearerToken
        )
    }

    private func performJSONRequest<Response: Decodable>(
        url: URL,
        method: String,
        bodyData: Data?,
        bearerToken: String?
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        if let bodyData {
            request.httpBody = bodyData
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let apiError = try? decoder.decode(APIErrorResponse.self, from: data),
               let message = apiError.resolvedMessage {
                throw AuthServiceError.requestFailed(message)
            }

            if let bodyText = String(data: data, encoding: .utf8),
               !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AuthServiceError.requestFailed(bodyText)
            }

            throw AuthServiceError.requestFailed("Auth backend request failed with status \(httpResponse.statusCode).")
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        guard !data.isEmpty else {
            throw AuthServiceError.invalidResponse
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw AuthServiceError.invalidResponse
        }
    }

    private static var currentDeviceInfo: DeviceInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"

        return DeviceInfo(
            platform: "macOS",
            deviceName: Host.current().localizedName ?? "Mac",
            appVersion: version,
            buildNumber: build
        )
    }

    private static func decodeBackendDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: rawValue) {
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

@MainActor
final class AuthSessionStore: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var isRestoringSession = true
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isSigningOut = false
    @Published private(set) var errorMessage: String?

    private let authService: AuthService
    private var authenticationTask: Task<Void, Never>?

    init(authService: AuthService = .shared) {
        self.authService = authService

        Task {
            await restoreSession()
        }
    }

    var isAuthenticated: Bool {
        session != nil
    }

    var currentUser: AuthenticatedUser? {
        session?.user
    }

    var signedInEmail: String? {
        session?.user.email
    }

    var signedInDisplayName: String? {
        session?.user.displayName
    }

    func refreshCurrentUserProfile() async throws {
        session = try await authService.refreshCurrentUserProfile()
    }

    func updateCurrentUser(newbie: Bool) async throws {
        session = try await authService.updateCurrentUser(newbie: newbie)
    }

    func signInWithGoogle() {
        guard !isAuthenticating else {
            return
        }

        errorMessage = nil
        isAuthenticating = true

        authenticationTask = Task {
            defer {
                isAuthenticating = false
                authenticationTask = nil
            }

            do {
                let authenticatedSession = try await authService.signInWithGoogle()
                session = authenticatedSession
            } catch is CancellationError {
                errorMessage = AuthServiceError.userCancelled.localizedDescription
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelGoogleSignIn() {
        guard isAuthenticating else {
            return
        }

        authService.cancelActiveAuthentication()
        authenticationTask?.cancel()
        isAuthenticating = false
        errorMessage = AuthServiceError.userCancelled.localizedDescription
    }

    func signOut() {
        guard !isSigningOut else {
            return
        }

        let currentSession = session
        isSigningOut = true
        errorMessage = nil

        Task {
            defer {
                isSigningOut = false
            }

            await authService.logout(
                accessToken: currentSession?.accessToken,
                refreshToken: currentSession?.refreshToken
            )

            session = nil
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func restoreSession() async {
        defer {
            isRestoringSession = false
        }

        guard let savedSession = authService.loadSavedSession() else {
            return
        }

        if savedSession.needsRefresh {
            do {
                session = try await authService.refreshSession(using: savedSession.refreshToken)
            } catch {
                authService.clearSavedSession()
                errorMessage = "Your previous login expired. Sign in again to continue."
                session = nil
            }
        } else {
            session = savedSession
        }
    }
}

private struct EmptyResponse: Decodable {}

private final class KeychainStore {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func save(_ data: Data, account: String) throws {
        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthServiceError.requestFailed("Speechara could not save the auth session in the Keychain.")
        }
    }

    func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            return nil
        }

        return item as? Data
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(query as CFDictionary)
    }
}

private final class LoopbackOAuthRedirectServer {
    private let callbackPath: String
    private let port: UInt16
    private let queue = DispatchQueue(label: "com.alexdem.speechara.auth.loopback")
    private var listener: NWListener?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var bufferedCallbackURL: URL?
    private var terminalError: Error?

    var redirectURL: URL {
        URL(string: "http://127.0.0.1:\(port)\(callbackPath)")!
    }

    init(callbackPath: String) throws {
        self.callbackPath = callbackPath.hasPrefix("/") ? callbackPath : "/\(callbackPath)"

        let (listener, port) = try Self.makeListener()
        self.listener = listener
        self.port = port
    }

    func start() async throws {
        guard let listener else {
            throw AuthServiceError.invalidResponse
        }

        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else {
                    return
                }

                switch state {
                case .ready:
                    self.startContinuation?.resume()
                    self.startContinuation = nil
                case .failed(let error):
                    self.startContinuation?.resume(throwing: error)
                    self.startContinuation = nil
                    self.finishCallback(with: .failure(error))
                case .cancelled:
                    self.startContinuation?.resume(throwing: CancellationError())
                    self.startContinuation = nil
                    self.finishCallback(with: .failure(CancellationError()))
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener.start(queue: queue)
        }
    }

    func waitForCallback(timeout: TimeInterval) async throws -> URL {
        if let bufferedCallbackURL {
            return bufferedCallbackURL
        }

        if let terminalError {
            throw terminalError
        }

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: URL.self) { group in
                group.addTask { [weak self] in
                    try await withCheckedThrowingContinuation { continuation in
                        self?.callbackContinuation = continuation
                    }
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw AuthServiceError.timedOutWaitingForGoogle
                }

                let callbackURL = try await group.next() ?? {
                    throw AuthServiceError.invalidCallback
                }()

                group.cancelAll()
                return callbackURL
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        listener?.cancel()
        finishCallback(with: .failure(CancellationError()))
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveNextChunk(on: connection, bufferedData: Data())
    }

    private func receiveNextChunk(on connection: NWConnection, bufferedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }

            if error != nil {
                connection.cancel()
                return
            }

            var combinedData = bufferedData
            if let data {
                combinedData.append(data)
            }

            if let requestText = String(data: combinedData, encoding: .utf8),
               requestText.contains("\r\n\r\n") {
                self.handleRequestText(requestText, on: connection)
                return
            }

            if isComplete {
                self.sendHTMLResponse(
                    on: connection,
                    statusCode: 400,
                    body: Self.callbackHTML(
                        title: "Sign-in failed",
                        message: "Speechara received an incomplete OAuth callback.",
                        kind: .failure
                    )
                )
                return
            }

            self.receiveNextChunk(on: connection, bufferedData: combinedData)
        }
    }

    private func handleRequestText(_ requestText: String, on connection: NWConnection) {
        guard let requestLine = requestText.components(separatedBy: "\r\n").first else {
            sendInvalidRequest(on: connection)
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            sendInvalidRequest(on: connection)
            return
        }

        let target = String(parts[1])
        guard let requestURL = URL(string: "http://127.0.0.1:\(port)\(target)"),
              let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              components.path == callbackPath else {
            sendInvalidRequest(on: connection)
            return
        }

        let items = Dictionary(uniqueKeysWithValues: components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])

        if let error = items["error"], !error.isEmpty {
            let description = items["error_description"]?.replacingOccurrences(of: "+", with: " ") ?? error
            sendHTMLResponse(
                on: connection,
                statusCode: 200,
                body: Self.callbackHTML(
                    title: "Sign-in failed",
                    message: description,
                    kind: .failure
                )
            )
            finishCallback(with: .failure(AuthServiceError.callbackReturnedError(description)))
            return
        }

        sendHTMLResponse(
            on: connection,
            statusCode: 200,
            body: Self.callbackHTML(
                title: "Signed in to Speechara",
                message: "You may now close this page.",
                kind: .success
            )
        )
        finishCallback(with: .success(requestURL))
    }

    private func sendInvalidRequest(on connection: NWConnection) {
        sendHTMLResponse(
            on: connection,
            statusCode: 404,
            body: Self.callbackHTML(
                title: "Sign-in failed",
                message: "This callback URL is not recognized by Speechara.",
                kind: .failure
            )
        )
    }

    private func sendHTMLResponse(on connection: NWConnection, statusCode: Int, body: String) {
        let bodyData = Data(body.utf8)
        let header = """
        HTTP/1.1 \(statusCode) \(Self.reasonPhrase(for: statusCode))\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(bodyData.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r
        """

        var responseData = Data(header.utf8)
        responseData.append(bodyData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finishCallback(with result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            if let callbackContinuation {
                self.callbackContinuation = nil
                callbackContinuation.resume(returning: url)
            } else {
                bufferedCallbackURL = url
            }
        case .failure(let error):
            if let callbackContinuation {
                self.callbackContinuation = nil
                callbackContinuation.resume(throwing: error)
            } else {
                terminalError = error
            }
        }

        listener?.cancel()
        listener = nil
    }

    private static func makeListener() throws -> (NWListener, UInt16) {
        for _ in 0..<20 {
            let port = UInt16.random(in: 49_152...65_000)
            do {
                let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
                return (listener, port)
            } catch {
                continue
            }
        }

        throw AuthServiceError.requestFailed("Speechara could not reserve a local OAuth callback port.")
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200:
            return "OK"
        case 400:
            return "Bad Request"
        case 404:
            return "Not Found"
        default:
            return "Internal Server Error"
        }
    }

    private enum CallbackPageKind {
        case success
        case failure

        var bodyClassName: String {
            switch self {
            case .success:
                return "success"
            case .failure:
                return "failure"
            }
        }
    }

    private static func callbackHTML(title: String, message: String, kind: CallbackPageKind) -> String {
        let safeTitle = htmlEscaped(title)
        let safeMessage = htmlEscaped(message)

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'">
          <title>\(safeTitle)</title>
          <style>
            :root { color-scheme: light; }
            html {
              height: 100%;
            }
            body {
              margin: 0;
              min-height: 100%;
              display: flex;
              align-items: center;
              justify-content: center;
              background:
                radial-gradient(circle at top, rgba(255,255,255,0.95), rgba(247,245,240,0.95)),
                linear-gradient(180deg, #fbfaf8 0%, #f5f3ee 100%);
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              color: #171717;
              -webkit-font-smoothing: antialiased;
              text-rendering: optimizeLegibility;
            }
            main {
              width: min(420px, calc(100vw - 48px));
              padding: 56px 24px;
              text-align: center;
            }
            .icon-tile {
              width: 72px;
              height: 72px;
              margin: 0 auto 28px;
              border-radius: 18px;
              background: rgba(255,255,255,0.94);
              border: 1px solid rgba(17,17,17,0.08);
              box-shadow:
                0 14px 36px rgba(17,17,17,0.10),
                inset 0 1px 0 rgba(255,255,255,0.92);
              display: flex;
              align-items: center;
              justify-content: center;
            }
            .icon-tile svg {
              width: 38px;
              height: 38px;
              display: block;
            }
            h1 {
              margin: 0 0 12px;
              font-size: clamp(28px, 5vw, 30px);
              line-height: 1.1;
              letter-spacing: -0.03em;
              font-weight: 600;
            }
            p {
              margin: 0;
              color: #6a6a6a;
              font-size: 16px;
              line-height: 1.5;
            }
            body.failure {
              background:
                radial-gradient(circle at top, rgba(255,255,255,0.94), rgba(251,242,240,0.97)),
                linear-gradient(180deg, #fff9f7 0%, #fff3f0 100%);
            }
            body.failure .icon-tile {
              border-color: rgba(180,35,24,0.12);
              box-shadow:
                0 14px 36px rgba(180,35,24,0.12),
                inset 0 1px 0 rgba(255,255,255,0.92);
            }
            body.failure h1 {
              color: #7a271a;
            }
            body.failure p {
              color: #8a5c56;
            }
          </style>
        </head>
        <body class="\(kind.bodyClassName)">
          <main>
            <div class="icon-tile" aria-hidden="true">
              \(iconMarkup(for: kind))
            </div>
            <h1>\(safeTitle)</h1>
            <p>\(safeMessage)</p>
          </main>
        </body>
        </html>
        """
    }

    private static func iconMarkup(for kind: CallbackPageKind) -> String {
        switch kind {
        case .success:
            return """
            <svg viewBox="0 0 40 40" fill="none" xmlns="http://www.w3.org/2000/svg">
              <circle cx="20" cy="20" r="13.5" stroke="#111111" stroke-width="2.4"/>
              <path d="M13.7 15.5L10.5 19.7L13.7 23.9" stroke="#111111" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>
              <path d="M24.5 25.4H29.6" stroke="#111111" stroke-width="2.4" stroke-linecap="round"/>
              <path d="M20 12.8C22.3 13.6 24.3 15.3 25.4 17.7" stroke="#111111" stroke-width="2.4" stroke-linecap="round"/>
            </svg>
            """
        case .failure:
            return """
            <svg viewBox="0 0 40 40" fill="none" xmlns="http://www.w3.org/2000/svg">
              <circle cx="20" cy="20" r="13.5" stroke="#B42318" stroke-width="2.4"/>
              <path d="M15 15L25 25" stroke="#B42318" stroke-width="2.4" stroke-linecap="round"/>
              <path d="M25 15L15 25" stroke="#B42318" stroke-width="2.4" stroke-linecap="round"/>
            </svg>
            """
        }
    }

    private static func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
