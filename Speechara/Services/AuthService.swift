import AppKit
import AuthenticationServices
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

    init(
        id: String,
        email: String,
        displayName: String,
        avatarURL: String?,
        workspaceID: String?,
        defaultWorkspaceID: String?,
        currentWorkspaceID: String?,
        newbie: Bool?,
        workspace: WorkspaceReference?,
        defaultWorkspace: WorkspaceReference?,
        currentWorkspace: WorkspaceReference?,
        workspaces: [WorkspaceReference]?
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.workspaceID = workspaceID
        self.defaultWorkspaceID = defaultWorkspaceID
        self.currentWorkspaceID = currentWorkspaceID
        self.newbie = newbie
        self.workspace = workspace
        self.defaultWorkspace = defaultWorkspace
        self.currentWorkspace = currentWorkspace
        self.workspaces = workspaces
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        let id = try container.decodeRequiredTrimmedString(forKeys: "id")
        let email = try container.decodeRequiredTrimmedString(forKeys: "email")
        let displayName = try container.decodeTrimmedStringIfPresent(
            forKeys: "display_name",
            "displayName",
            "name"
        ) ?? email

        self.init(
            id: id,
            email: email,
            displayName: displayName,
            avatarURL: try container.decodeTrimmedStringIfPresent(forKeys: "avatar_url", "avatarUrl"),
            workspaceID: try container.decodeTrimmedStringIfPresent(forKeys: "workspaceId", "workspace_id"),
            defaultWorkspaceID: try container.decodeTrimmedStringIfPresent(forKeys: "defaultWorkspaceId", "default_workspace_id"),
            currentWorkspaceID: try container.decodeTrimmedStringIfPresent(forKeys: "currentWorkspaceId", "current_workspace_id"),
            newbie: try container.decodeIfPresent(Bool.self, forKeys: "newbie"),
            workspace: try container.decodeIfPresent(WorkspaceReference.self, forKeys: "workspace"),
            defaultWorkspace: try container.decodeIfPresent(WorkspaceReference.self, forKeys: "defaultWorkspace", "default_workspace"),
            currentWorkspace: try container.decodeIfPresent(WorkspaceReference.self, forKeys: "currentWorkspace", "current_workspace"),
            workspaces: try container.decodeIfPresent([WorkspaceReference].self, forKeys: "workspaces")
        )
    }

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

struct EmailChallenge: Codable, Equatable {
    let challengeId: String
    let email: String
    let maskedEmail: String
    let purpose: String
    let linkedAuthProviders: [String]
    let expiresIn: Int
    let expiresAt: Date
    let resendAfter: Int?
}

struct EmailVerification: Codable, Equatable {
    let challengeId: String
    let email: String
    let maskedEmail: String
    let verified: Bool
    let purpose: String
    let linkedAuthProviders: [String]
    let verificationToken: String
    let expiresIn: Int
    let expiresAt: Date
}

struct TotpSetup: Codable, Equatable {
    let setupId: String
    let otpauthUri: String
    let secret: String
    let qrCodeDataUrl: String?
    let expiresIn: Int
    let expiresAt: Date
}

struct MfaChallenge: Codable, Equatable {
    let challengeId: String
    let email: String
    let maskedEmail: String
    let type: String
    let expiresIn: Int
    let expiresAt: Date
}

enum EmailLoginResult: Equatable {
    case authenticated(AuthSession)
    case mfaRequired(MfaChallenge)
}

struct EmailRegistrationMFA: Encodable, Equatable {
    let type: String
    let setupId: String
    let code: String

    init(setupId: String, code: String) {
        self.type = "totp"
        self.setupId = setupId
        self.code = code
    }
}

struct CompleteEmailRegistrationInput: Encodable, Equatable {
    let challengeId: String
    let email: String
    let name: String
    let password: String
    let verificationToken: String
    let mfa: EmailRegistrationMFA?

    enum CodingKeys: String, CodingKey {
        case challengeId
        case email
        case name
        case password
        case verificationToken
        case mfa
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(email, forKey: .email)
        try container.encode(name, forKey: .name)
        try container.encode(password, forKey: .password)
        try container.encode(verificationToken, forKey: .verificationToken)

        if let mfa {
            try container.encode(mfa, forKey: .mfa)
        } else {
            try container.encodeNil(forKey: .mfa)
        }
    }
}

struct SecurityStatus: Decodable, Equatable {
    struct MFA: Decodable, Equatable {
        let totpEnabled: Bool
        let enabledMethods: [String]
        let enabledAt: Date?
    }

    let passwordLoginEnabled: Bool
    let mfa: MFA
}

struct PasswordChangeResult: Decodable, Equatable {
    let passwordLoginEnabled: Bool
    let changedAt: Date?
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

private extension String {
    var nonEmptyTrimmed: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var sha256HexDigest: String {
        let digest = SHA256.hash(data: Data(utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct FlexibleCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == FlexibleCodingKey {
    func decodeRequiredTrimmedString(forKeys keys: String...) throws -> String {
        if let value = try decodeTrimmedStringIfPresent(forKeys: keys) {
            return value
        }

        throw DecodingError.keyNotFound(
            FlexibleCodingKey(keys.first ?? ""),
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected one of keys: \(keys.joined(separator: ", "))."
            )
        )
    }

    func decodeTrimmedStringIfPresent(forKeys keys: String...) throws -> String? {
        try decodeTrimmedStringIfPresent(forKeys: keys)
    }

    func decodeTrimmedStringIfPresent(forKeys keys: [String]) throws -> String? {
        for key in keys {
            let codingKey = FlexibleCodingKey(key)
            if let value = try decodeIfPresent(String.self, forKey: codingKey)?.nonEmptyTrimmed {
                return value
            }
        }

        return nil
    }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKeys keys: String...) throws -> T? {
        for key in keys {
            let codingKey = FlexibleCodingKey(key)
            if contains(codingKey), let value = try decodeIfPresent(type, forKey: codingKey) {
                return value
            }
        }

        return nil
    }
}

enum AuthServiceError: LocalizedError {
    case missingBackendBaseURL
    case missingMicrosoftClientID
    case invalidBackendBaseURL(String)
    case browserOpenFailed
    case appleCredentialMissingToken
    case microsoftIDTokenMissing
    case invalidCallback
    case callbackStateMismatch
    case callbackMissingCode
    case callbackReturnedError(String)
    case requestFailed(String)
    case invalidResponse
    case timedOutWaitingForGoogle
    case timedOutWaitingForMicrosoft
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .missingBackendBaseURL:
            return "Sign-in is not configured yet. Add the auth backend URL in Settings first."
        case .missingMicrosoftClientID:
            return "Microsoft sign-in is not configured yet. Add the Microsoft client ID in Settings or bundle it with the app build."
        case .invalidBackendBaseURL(let value):
            return "The saved auth backend URL is invalid: \(value)"
        case .browserOpenFailed:
            return "Speechara could not open the system browser for sign-in."
        case .appleCredentialMissingToken:
            return "Apple sign-in completed, but Apple did not return an identity token."
        case .microsoftIDTokenMissing:
            return "Microsoft sign-in completed, but Microsoft did not return an ID token."
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
        case .timedOutWaitingForMicrosoft:
            return "Microsoft sign-in timed out before Speechara received the browser callback."
        case .userCancelled:
            return "Sign-in was canceled."
        }
    }
}

struct MfaRequiredError: Error {
    let challenge: MfaChallenge
}

final class AuthService {
    static let shared = AuthService()

    private struct Configuration {
        let baseURL: URL
    }

    private struct DesktopAuthExchangeRequest: Encodable {
        let code: String
        let state: String
        let codeVerifier: String

        enum CodingKeys: String, CodingKey {
            case code, state
            case codeVerifier = "code_verifier"
        }
    }

    private struct MicrosoftAPIExchangeRequest: Encodable {
        let idToken: String
    }

    private struct AppleAPIExchangeRequest: Encodable {
        struct User: Encodable {
            struct Name: Encodable {
                let firstName: String?
                let lastName: String?
            }

            let name: Name?
            let email: String?
        }

        let idToken: String
        let authorizationCode: String?
        let nonce: String
        let state: String
        let user: User?
    }

    private struct AppleIDTokenDebugClaims: Decodable {
        let issuer: String?
        let audience: Audience?

        enum CodingKeys: String, CodingKey {
            case issuer = "iss"
            case audience = "aud"
        }

        enum Audience: Decodable {
            case string(String)
            case strings([String])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let value = try? container.decode(String.self) {
                    self = .string(value)
                } else {
                    self = .strings(try container.decode([String].self))
                }
            }

            var description: String {
                switch self {
                case .string(let value):
                    return value
                case .strings(let values):
                    return values.joined(separator: ",")
                }
            }
        }
    }

    private struct MicrosoftTokenResponse: Decodable {
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
        }
    }

    private struct EmailRegistrationStartRequest: Encodable {
        let email: String
        let name: String?
    }

    private struct EmailCodeVerificationRequest: Encodable {
        let challengeId: String
        let email: String
        let code: String

        enum CodingKeys: String, CodingKey {
            case challengeId
            case email
            case code
        }
    }

    private struct EmailResendCodeRequest: Encodable {
        let challengeId: String
        let email: String
    }

    private struct RegistrationTotpSetupRequest: Encodable {
        let challengeId: String
        let email: String
        let verificationToken: String
    }

    private struct EmailLoginRequest: Encodable {
        let email: String
        let password: String
    }

    private struct EmailMfaVerificationRequest: Encodable {
        let challengeId: String
        let email: String
        let type: String
        let code: String
    }

    private struct EmailLoginMfaChallengeResponse: Decodable {
        let code: String
        let challengeId: String
        let email: String
        let maskedEmail: String
        let type: String
        let expiresIn: Int
        let expiresAt: Date

        var challenge: MfaChallenge {
            MfaChallenge(
                challengeId: challengeId,
                email: email,
                maskedEmail: maskedEmail,
                type: type,
                expiresIn: expiresIn,
                expiresAt: expiresAt
            )
        }
    }

    private struct ChangePasswordRequest: Encodable {
        let currentPassword: String
        let newPassword: String
    }

    private struct EnableTotpRequest: Encodable {
        let setupId: String
        let code: String
    }

    private struct DisableTotpRequest: Encodable {
        let code: String
    }

    private struct EmptyRequest: Encodable {}

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
        let refreshToken: String?
        let tokenType: String
        let expiresAt: Date
        let user: AuthenticatedUser

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
            accessToken = try container.decodeRequiredTrimmedString(forKeys: "access_token", "accessToken")
            refreshToken = try container.decodeTrimmedStringIfPresent(forKeys: "refresh_token", "refreshToken")
            tokenType = try container.decodeTrimmedStringIfPresent(forKeys: "token_type", "tokenType") ?? "Bearer"

            if let decodedExpiresAt = try container.decodeIfPresent(Date.self, forKeys: "expires_at", "expiresAt") {
                expiresAt = decodedExpiresAt
            } else if let expiresIn = try container.decodeIfPresent(Int.self, forKeys: "expires_in", "expiresIn") {
                expiresAt = Date(timeIntervalSinceNow: TimeInterval(expiresIn))
            } else {
                throw DecodingError.keyNotFound(
                    FlexibleCodingKey("expires_at"),
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected expires_at, expiresAt, expires_in, or expiresIn."
                    )
                )
            }

            user = try container.decode(AuthenticatedUser.self, forKey: FlexibleCodingKey("user"))
        }

        func session(fallbackRefreshToken: String?) throws -> AuthSession {
            guard let resolvedRefreshToken = refreshToken?.nonEmptyTrimmed ?? fallbackRefreshToken?.nonEmptyTrimmed else {
                throw AuthServiceError.invalidResponse
            }

            return AuthSession(
                accessToken: accessToken,
                refreshToken: resolvedRefreshToken,
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
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case message
            case detail
            case title
            case errorDescription = "error_description"
        }

        var resolvedMessage: String? {
            if let errorDescription, !errorDescription.isEmpty {
                return errorDescription
            }

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

            let queryItems = components.queryItems ?? []
            guard Set(queryItems.map(\.name)).count == queryItems.count else {
                throw AuthServiceError.invalidCallback
            }
            let items = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

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

    private struct OAuthPKCETransaction {
        let state: String
        let codeVerifier: String

        init() throws {
            state = try Self.randomURLSafeString(length: 32)
            codeVerifier = try Self.randomURLSafeString(length: 64)
        }

        var codeChallenge: String {
            let digest = SHA256.hash(data: Data(codeVerifier.utf8))
            return Data(digest).base64URLEncodedString()
        }

        private static func randomURLSafeString(length: Int) throws -> String {
            var combined = ""

            while combined.count < length {
                var bytes = [UInt8](repeating: 0, count: 32)
                let byteCount = bytes.count
                let status = bytes.withUnsafeMutableBytes { buffer in
                    guard let baseAddress = buffer.baseAddress else {
                        return errSecParam
                    }
                    return SecRandomCopyBytes(kSecRandomDefault, byteCount, baseAddress)
                }
                guard status == errSecSuccess else {
                    throw AuthServiceError.requestFailed("Speechara could not create secure OAuth randomness.")
                }
                combined.append(Data(bytes).base64URLEncodedString())
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
    private var activeDesktopCallbackWaiter: DesktopOAuthCallbackWaiter?
    private var activeAppleAuthorizationSession: AppleAuthorizationSession?

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
        activeDesktopCallbackWaiter?.cancel()
        activeDesktopCallbackWaiter = nil
        activeAppleAuthorizationSession?.cancel()
        activeAppleAuthorizationSession = nil
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "speechara",
              url.host?.lowercased() == "auth" else {
            return false
        }

        if url.path == "/microsoft/complete" {
            return true
        }

        guard url.path == "/callback" else {
            return false
        }

        activeDesktopCallbackWaiter?.receive(url)
        return true
    }

    func signInWithGoogle() async throws -> AuthSession {
        let configuration = try makeConfiguration()
        let transaction = try OAuthPKCETransaction()
        let callbackWaiter = DesktopOAuthCallbackWaiter()

        activeDesktopCallbackWaiter = callbackWaiter
        defer {
            callbackWaiter.cancel()
            activeDesktopCallbackWaiter = nil
        }

        let authorizationURL = try makeGoogleDesktopAuthorizationURL(
            configuration: configuration,
            state: transaction.state,
            codeChallenge: transaction.codeChallenge
        )

        let didOpenBrowser = await MainActor.run {
            NSWorkspace.shared.open(authorizationURL)
        }

        guard didOpenBrowser else {
            throw AuthServiceError.browserOpenFailed
        }

        let callbackURL = try await callbackWaiter.waitForCallback(
            timeout: 300,
            timeoutError: AuthServiceError.timedOutWaitingForGoogle
        )

        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }

        let payload = try CallbackPayload(url: callbackURL)

        guard payload.state == transaction.state else {
            throw AuthServiceError.callbackStateMismatch
        }

        let authenticatedSession = try await exchangeDesktopAuthCode(
            configuration: configuration,
            code: payload.code,
            state: payload.state,
            codeVerifier: transaction.codeVerifier
        )

        try persistSession(authenticatedSession)

        return authenticatedSession
    }

    func signInWithMicrosoft() async throws -> AuthSession {
        _ = try makeConfiguration()
        let clientID = try makeMicrosoftClientID()
        let transaction = try OAuthPKCETransaction()
        let redirectServer = try LoopbackOAuthRedirectServer(callbackPath: "/oauth/microsoft/callback")

        activeRedirectServer = redirectServer
        defer {
            redirectServer.cancel()
            activeRedirectServer = nil
        }

        try await redirectServer.start()

        let authorizationURL = try makeMicrosoftAuthorizationURL(
            clientID: clientID,
            transaction: transaction,
            redirectURI: redirectServer.redirectURL
        )

        let didOpenBrowser = await MainActor.run {
            NSWorkspace.shared.open(authorizationURL)
        }

        guard didOpenBrowser else {
            throw AuthServiceError.browserOpenFailed
        }

        let callbackURL = try await redirectServer.waitForCallback(
            timeout: 300,
            timeoutError: AuthServiceError.timedOutWaitingForMicrosoft
        )

        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }

        let payload = try CallbackPayload(url: callbackURL)

        guard payload.state == transaction.state else {
            throw AuthServiceError.callbackStateMismatch
        }

        let idToken = try await exchangeMicrosoftAuthorizationCode(
            clientID: clientID,
            code: payload.code,
            codeVerifier: transaction.codeVerifier,
            redirectURI: redirectServer.redirectURL
        )

        let authenticatedSession = try await exchangeMicrosoftIdToken(idToken)
        try persistSession(authenticatedSession)

        return authenticatedSession
    }

    func exchangeMicrosoftIdToken(_ idToken: String) async throws -> AuthSession {
        let configuration = try makeConfiguration()
        let requestBody = MicrosoftAPIExchangeRequest(idToken: idToken)
        let authenticatedSession = try await performAuthSessionRequest(
            url: configuration.baseURL.appendingPathComponent("api/auth/microsoft"),
            method: "POST",
            body: requestBody,
            bearerToken: nil
        )

        try persistSession(authenticatedSession)
        return authenticatedSession
    }

    @MainActor
    func signInWithApple() async throws -> AuthSession {
        let configuration = try makeConfiguration()
        let transaction = try OAuthPKCETransaction()
        let appleSession = AppleAuthorizationSession(
            rawNonce: transaction.codeVerifier,
            state: transaction.state
        )

        activeAppleAuthorizationSession = appleSession
        defer {
            appleSession.cancel()
            activeAppleAuthorizationSession = nil
        }

        let authorization = try await appleSession.start()

        let authenticatedSession = try await exchangeAppleAuthorization(
            configuration: configuration,
            authorization: authorization,
            rawNonce: transaction.codeVerifier,
            state: transaction.state
        )

        try persistSession(authenticatedSession)
        return authenticatedSession
    }

    func startEmailRegistration(email: String, name: String?) async throws -> EmailChallenge {
        let configuration = try makeConfiguration()
        return try await performJSONRequest(
            url: configuration.baseURL.appendingPathComponent("api/auth/email/register"),
            method: "POST",
            body: EmailRegistrationStartRequest(email: email, name: name?.nonEmptyTrimmed),
            bearerToken: nil
        )
    }

    func verifyEmailCode(challengeId: String, email: String, code: String) async throws -> EmailVerification {
        let configuration = try makeConfiguration()
        return try await performJSONRequest(
            url: configuration.baseURL.appendingPathComponent("api/auth/email/verify"),
            method: "POST",
            body: EmailCodeVerificationRequest(challengeId: challengeId, email: email, code: code),
            bearerToken: nil
        )
    }

    func setupRegistrationTotp(
        challengeId: String,
        email: String,
        verificationToken: String
    ) async throws -> TotpSetup {
        let configuration = try makeConfiguration()
        return try await performJSONRequest(
            url: configuration.baseURL.appendingPathComponent("api/auth/email/totp/setup"),
            method: "POST",
            body: RegistrationTotpSetupRequest(
                challengeId: challengeId,
                email: email,
                verificationToken: verificationToken
            ),
            bearerToken: nil
        )
    }

    func completeEmailRegistration(input: CompleteEmailRegistrationInput) async throws -> AuthSession {
        let configuration = try makeConfiguration()
        let authenticatedSession = try await performAuthSessionRequest(
            url: configuration.baseURL.appendingPathComponent("api/auth/email/complete-registration"),
            method: "POST",
            body: input,
            bearerToken: nil
        )

        try persistSession(authenticatedSession)
        return authenticatedSession
    }

    func loginWithEmail(email: String, password: String) async throws -> EmailLoginResult {
        let configuration = try makeConfiguration()
        let (data, response) = try await performRawJSONRequest(
            url: configuration.baseURL.appendingPathComponent("api/auth/email/login"),
            method: "POST",
            bodyData: try encoder.encode(EmailLoginRequest(email: email, password: password)),
            bearerToken: nil
        )

        if let mfaChallenge = try? decoder.decode(EmailLoginMfaChallengeResponse.self, from: data),
           mfaChallenge.code == "MFA_REQUIRED" {
            return .mfaRequired(mfaChallenge.challenge)
        }

        let sessionResponse = try decodeSessionResponse(from: data)
        let authenticatedSession = try sessionResponse.session(
            fallbackRefreshToken: Self.refreshToken(from: response)
        )
        try persistSession(authenticatedSession)
        return .authenticated(authenticatedSession)
    }

    func verifyEmailMfa(challengeId: String, email: String, code: String) async throws -> AuthSession {
        let configuration = try makeConfiguration()
        let authenticatedSession = try await performAuthSessionRequest(
            url: configuration.baseURL.appendingPathComponent("api/auth/email/mfa/verify"),
            method: "POST",
            body: EmailMfaVerificationRequest(
                challengeId: challengeId,
                email: email,
                type: "totp",
                code: code
            ),
            bearerToken: nil
        )

        try persistSession(authenticatedSession)
        return authenticatedSession
    }

    func resendEmailCode(challengeId: String, email: String) async throws -> EmailChallenge {
        let configuration = try makeConfiguration()
        return try await performJSONRequest(
            url: configuration.baseURL.appendingPathComponent("api/auth/email/resend-code"),
            method: "POST",
            body: EmailResendCodeRequest(challengeId: challengeId, email: email),
            bearerToken: nil
        )
    }

    func currentUser() async throws -> AuthenticatedUser {
        let session = try await refreshCurrentUserProfile()
        return session.user
    }

    func securityStatus() async throws -> SecurityStatus {
        let currentSession = try await activeSession()
        return try await performJSONRequest(
            url: try makeConfiguration().baseURL.appendingPathComponent("api/auth/security"),
            method: "GET",
            bearerToken: currentSession.accessToken
        )
    }

    func changePassword(currentPassword: String, newPassword: String) async throws -> PasswordChangeResult {
        let currentSession = try await activeSession()
        return try await performJSONRequest(
            url: try makeConfiguration().baseURL.appendingPathComponent("api/auth/security/password/change"),
            method: "POST",
            body: ChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword),
            bearerToken: currentSession.accessToken,
            refreshCookieToken: currentSession.refreshToken
        )
    }

    func startTotpSetup() async throws -> TotpSetup {
        let currentSession = try await activeSession()
        return try await performJSONRequest(
            url: try makeConfiguration().baseURL.appendingPathComponent("api/auth/security/mfa/totp/setup"),
            method: "POST",
            body: EmptyRequest(),
            bearerToken: currentSession.accessToken
        )
    }

    func enableTotp(setupId: String, code: String) async throws -> SecurityStatus {
        let currentSession = try await activeSession()
        return try await performJSONRequest(
            url: try makeConfiguration().baseURL.appendingPathComponent("api/auth/security/mfa/totp/enable"),
            method: "POST",
            body: EnableTotpRequest(setupId: setupId, code: code),
            bearerToken: currentSession.accessToken
        )
    }

    func disableTotp(code: String) async throws -> SecurityStatus {
        let currentSession = try await activeSession()
        return try await performJSONRequest(
            url: try makeConfiguration().baseURL.appendingPathComponent("api/auth/security/mfa/totp/disable"),
            method: "POST",
            body: DisableTotpRequest(code: code),
            bearerToken: currentSession.accessToken
        )
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

        let refreshedSession = try response.session(fallbackRefreshToken: nil)
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
        return try await refreshCurrentUserProfile(using: currentSession)
    }

    func refreshCurrentUserProfile(using currentSession: AuthSession) async throws -> AuthSession {
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

    private func makeGoogleDesktopAuthorizationURL(
        configuration: Configuration,
        state: String,
        codeChallenge: String
    ) throws -> URL {
        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent("api/auth/google/desktop/start"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let url = components?.url else {
            throw AuthServiceError.invalidResponse
        }

        return url
    }

    private func makeMicrosoftClientID() throws -> String {
        guard let clientID = AppConfigurationStore.shared.resolvedValue(for: .microsoftClientID)?.nonEmptyTrimmed else {
            throw AuthServiceError.missingMicrosoftClientID
        }

        return clientID
    }

    private func makeMicrosoftAuthorizationURL(
        clientID: String,
        transaction: OAuthPKCETransaction,
        redirectURI: URL
    ) throws -> URL {
        var components = URLComponents(
            string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
        )
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: "openid profile email"),
            URLQueryItem(name: "state", value: transaction.state),
            URLQueryItem(name: "code_challenge", value: transaction.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]

        guard let url = components?.url else {
            throw AuthServiceError.invalidResponse
        }

        return url
    }

    private func exchangeMicrosoftAuthorizationCode(
        clientID: String,
        code: String,
        codeVerifier: String,
        redirectURI: URL
    ) async throws -> String {
        let response: MicrosoftTokenResponse = try await performFormRequest(
            url: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            method: "POST",
            formBody: [
                "client_id": clientID,
                "scope": "openid profile email",
                "code": code,
                "redirect_uri": redirectURI.absoluteString,
                "grant_type": "authorization_code",
                "code_verifier": codeVerifier,
            ]
        )

        guard let idToken = response.idToken?.nonEmptyTrimmed else {
            throw AuthServiceError.microsoftIDTokenMissing
        }

        return idToken
    }

    private func exchangeDesktopAuthCode(
        configuration: Configuration,
        code: String,
        state: String,
        codeVerifier: String
    ) async throws -> AuthSession {
        try await performAuthSessionRequest(
            url: configuration.baseURL.appendingPathComponent("api/auth/desktop/exchange"),
            method: "POST",
            body: DesktopAuthExchangeRequest(code: code, state: state, codeVerifier: codeVerifier),
            bearerToken: nil
        )
    }

    private func exchangeAppleAuthorization(
        configuration: Configuration,
        authorization: AppleAuthorizationResult,
        rawNonce: String,
        state: String
    ) async throws -> AuthSession {
        guard let idToken = authorization.idToken.nonEmptyTrimmed else {
            throw AuthServiceError.appleCredentialMissingToken
        }

#if DEBUG
        if let claims = Self.debugClaims(fromAppleIDToken: idToken) {
            print(
                [
                    "Speechara Apple Sign-In debug",
                    "aud=\(claims.audience?.description ?? "<missing>")",
                    "iss=\(claims.issuer ?? "<missing>")",
                    "bundleID=\(Bundle.main.bundleIdentifier ?? "<missing>")",
                    "backend=\(configuration.baseURL.absoluteString)",
                ].joined(separator: " | ")
            )
        } else {
            print(
                [
                    "Speechara Apple Sign-In debug",
                    "could not decode idToken claims",
                    "bundleID=\(Bundle.main.bundleIdentifier ?? "<missing>")",
                    "backend=\(configuration.baseURL.absoluteString)",
                ].joined(separator: " | ")
            )
        }
#endif

        let firstName = authorization.firstName.nonEmptyTrimmed
        let lastName = authorization.lastName.nonEmptyTrimmed
        let email = authorization.email.nonEmptyTrimmed
        let name = firstName != nil || lastName != nil
            ? AppleAPIExchangeRequest.User.Name(firstName: firstName, lastName: lastName)
            : nil
        let user = name != nil || email != nil
            ? AppleAPIExchangeRequest.User(name: name, email: email)
            : nil

        let requestBody = AppleAPIExchangeRequest(
            idToken: idToken,
            authorizationCode: authorization.authorizationCode.nonEmptyTrimmed,
            nonce: rawNonce,
            state: state,
            user: user
        )

        return try await performAuthSessionRequest(
            url: configuration.baseURL.appendingPathComponent("api/auth/apple"),
            method: "POST",
            body: requestBody,
            bearerToken: nil
        )
    }

    private static func debugClaims(fromAppleIDToken idToken: String) -> AppleIDTokenDebugClaims? {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2,
              let payloadData = Data(base64URLEncoded: String(parts[1])) else {
            return nil
        }

        return try? JSONDecoder().decode(AppleIDTokenDebugClaims.self, from: payloadData)
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
        bearerToken: String?,
        refreshCookieToken: String? = nil
    ) async throws -> Response {
        let bodyData = try body.map { try encoder.encode($0) }
        return try await performJSONRequest(
            url: url,
            method: method,
            bodyData: bodyData,
            bearerToken: bearerToken,
            refreshCookieToken: refreshCookieToken
        )
    }

    private func performJSONRequest<Response: Decodable>(
        url: URL,
        method: String,
        bearerToken: String?,
        refreshCookieToken: String? = nil
    ) async throws -> Response {
        try await performJSONRequest(
            url: url,
            method: method,
            bodyData: nil,
            bearerToken: bearerToken,
            refreshCookieToken: refreshCookieToken
        )
    }

    private func performJSONRequest<Response: Decodable>(
        url: URL,
        method: String,
        bodyData: Data?,
        bearerToken: String?,
        refreshCookieToken: String? = nil
    ) async throws -> Response {
        let (data, _) = try await performRawJSONRequest(
            url: url,
            method: method,
            bodyData: bodyData,
            bearerToken: bearerToken,
            refreshCookieToken: refreshCookieToken
        )

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

    private func performAuthSessionRequest<Body: Encodable>(
        url: URL,
        method: String,
        body: Body,
        bearerToken: String?
    ) async throws -> AuthSession {
        let (data, response) = try await performRawJSONRequest(
            url: url,
            method: method,
            bodyData: try encoder.encode(body),
            bearerToken: bearerToken
        )

        let sessionResponse = try decodeSessionResponse(from: data)
        return try sessionResponse.session(
            fallbackRefreshToken: Self.refreshToken(from: response)
        )
    }

    private func performRawJSONRequest(
        url: URL,
        method: String,
        bodyData: Data?,
        bearerToken: String?,
        refreshCookieToken: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        if let refreshCookieToken = refreshCookieToken?.nonEmptyTrimmed {
            request.setValue("speechara_refresh_token=\(refreshCookieToken)", forHTTPHeaderField: "Cookie")
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

        return (data, httpResponse)
    }

    private func performFormRequest<Response: Decodable>(
        url: URL,
        method: String,
        formBody: [String: String]
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody.formURLEncodedData

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

            throw AuthServiceError.requestFailed("Microsoft token request failed with status \(httpResponse.statusCode).")
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

    private func decodeSessionResponse(from data: Data) throws -> SessionResponse {
        if let challenge = try? decoder.decode(EmailLoginMfaChallengeResponse.self, from: data),
           challenge.code == "MFA_REQUIRED" {
            throw MfaRequiredError(challenge: challenge.challenge)
        }
        guard !data.isEmpty else {
            throw AuthServiceError.invalidResponse
        }

        do {
            return try decoder.decode(SessionResponse.self, from: data)
        } catch {
            throw AuthServiceError.invalidResponse
        }
    }

    private static func refreshToken(from response: HTTPURLResponse) -> String? {
        if let url = response.url,
           let cookieToken = HTTPCookieStorage.shared
            .cookies(for: url)?
            .first(where: { $0.name == "speechara_refresh_token" })?
            .value
            .nonEmptyTrimmed {
            return cookieToken
        }

        for (key, value) in response.allHeaderFields {
            guard String(describing: key).lowercased() == "set-cookie" else {
                continue
            }

            let headerValue = String(describing: value)
            let cookieParts = headerValue.components(separatedBy: ",")
            for cookiePart in cookieParts {
                let trimmedPart = cookiePart.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedPart.hasPrefix("speechara_refresh_token=") else {
                    continue
                }

                let tokenPart = trimmedPart
                    .dropFirst("speechara_refresh_token=".count)
                    .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
                    .first
                    .map(String.init)

                if let token = tokenPart?.removingPercentEncoding?.nonEmptyTrimmed ?? tokenPart?.nonEmptyTrimmed {
                    return token
                }
            }
        }

        return nil
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

enum AuthenticationProvider: Equatable {
    case google
    case microsoft
    case apple
    case email

    var displayName: String {
        switch self {
        case .google:
            return "Google"
        case .microsoft:
            return "Microsoft"
        case .apple:
            return "Apple"
        case .email:
            return "email"
        }
    }
}

@MainActor
final class AuthSessionStore: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var isRestoringSession = true
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isSigningOut = false
    @Published private(set) var pendingMfaChallenge: MfaChallenge?
    @Published private(set) var activeAuthenticationProvider: AuthenticationProvider?
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
        let currentSession: AuthSession
        if let existingSession = session {
            currentSession = existingSession.needsRefresh
                ? try await authService.refreshSession(using: existingSession.refreshToken)
                : existingSession
        } else {
            currentSession = try await authService.activeSession()
        }

        session = try await authService.refreshCurrentUserProfile(using: currentSession)
        errorMessage = nil
    }

    @discardableResult
    func ensureActiveSession() async throws -> AuthSession {
        do {
            let activeSession = try await authService.activeSession()
            session = activeSession
            errorMessage = nil
            return activeSession
        } catch {
            if session?.needsRefresh != false {
                authService.clearSavedSession()
                session = nil
                errorMessage = SL("Your login expired. Sign in again to continue.")
            } else {
                errorMessage = error.localizedDescription
            }

            throw error
        }
    }

    func updateCurrentUser(newbie: Bool) async throws {
        session = try await authService.updateCurrentUser(newbie: newbie)
    }

    func signInWithGoogle() {
        guard !isAuthenticating else {
            return
        }

        pendingMfaChallenge = nil
        errorMessage = nil
        isAuthenticating = true
        activeAuthenticationProvider = .google

        authenticationTask = Task {
            defer {
                isAuthenticating = false
                activeAuthenticationProvider = nil
                authenticationTask = nil
            }

            do {
                let authenticatedSession = try await authService.signInWithGoogle()
                session = authenticatedSession
            } catch let error as MfaRequiredError {
                pendingMfaChallenge = error.challenge
            } catch is CancellationError {
                errorMessage = AuthServiceError.userCancelled.localizedDescription
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func signInWithMicrosoft() {
        guard !isAuthenticating else {
            return
        }

        pendingMfaChallenge = nil
        errorMessage = nil
        isAuthenticating = true
        activeAuthenticationProvider = .microsoft

        authenticationTask = Task {
            defer {
                isAuthenticating = false
                activeAuthenticationProvider = nil
                authenticationTask = nil
            }

            do {
                let authenticatedSession = try await authService.signInWithMicrosoft()
                session = authenticatedSession
            } catch let error as MfaRequiredError {
                pendingMfaChallenge = error.challenge
            } catch is CancellationError {
                errorMessage = AuthServiceError.userCancelled.localizedDescription
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func signInWithApple() {
        guard !isAuthenticating else {
            return
        }

        pendingMfaChallenge = nil
        errorMessage = nil
        isAuthenticating = true
        activeAuthenticationProvider = .apple

        authenticationTask = Task {
            defer {
                isAuthenticating = false
                activeAuthenticationProvider = nil
                authenticationTask = nil
            }

            do {
                let authenticatedSession = try await authService.signInWithApple()
                session = authenticatedSession
            } catch let error as MfaRequiredError {
                pendingMfaChallenge = error.challenge
            } catch is CancellationError {
                errorMessage = AuthServiceError.userCancelled.localizedDescription
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelGoogleSignIn() {
        cancelAuthentication()
    }

    func cancelAuthentication() {
        guard isAuthenticating else {
            return
        }

        authService.cancelActiveAuthentication()
        authenticationTask?.cancel()
        isAuthenticating = false
        activeAuthenticationProvider = nil
        errorMessage = AuthServiceError.userCancelled.localizedDescription
    }

    @discardableResult
    func loginWithEmail(email: String, password: String) async -> EmailLoginResult? {
        await runEmailAuthenticationOperation {
            try await self.authService.loginWithEmail(email: email, password: password)
        }
    }

    func startEmailRegistration(email: String, name: String?) async -> EmailChallenge? {
        await runEmailAuthenticationOperation {
            try await self.authService.startEmailRegistration(email: email, name: name)
        }
    }

    func verifyEmailCode(challengeId: String, email: String, code: String) async -> EmailVerification? {
        await runEmailAuthenticationOperation {
            try await self.authService.verifyEmailCode(challengeId: challengeId, email: email, code: code)
        }
    }

    func setupRegistrationTotp(
        challengeId: String,
        email: String,
        verificationToken: String
    ) async -> TotpSetup? {
        await runEmailAuthenticationOperation {
            try await self.authService.setupRegistrationTotp(
                challengeId: challengeId,
                email: email,
                verificationToken: verificationToken
            )
        }
    }

    func completeEmailRegistration(input: CompleteEmailRegistrationInput) async -> AuthSession? {
        await runEmailAuthenticationOperation {
            try await self.authService.completeEmailRegistration(input: input)
        }
    }

    func verifyEmailMfa(challengeId: String, email: String, code: String) async -> AuthSession? {
        let result = await runEmailAuthenticationOperation {
            try await self.authService.verifyEmailMfa(challengeId: challengeId, email: email, code: code)
        }
        if result != nil { pendingMfaChallenge = nil }
        return result
    }

    func resendEmailCode(challengeId: String, email: String) async -> EmailChallenge? {
        await runEmailAuthenticationOperation {
            try await self.authService.resendEmailCode(challengeId: challengeId, email: email)
        }
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

    func clearPendingMfa() { pendingMfaChallenge = nil }

    func clearError() {
        errorMessage = nil
    }

    private func runEmailAuthenticationOperation<Value>(
        _ operation: @escaping () async throws -> Value
    ) async -> Value? {
        guard !isAuthenticating else {
            return nil
        }

        errorMessage = nil
        isAuthenticating = true
        activeAuthenticationProvider = .email

        defer {
            isAuthenticating = false
            activeAuthenticationProvider = nil
        }

        do {
            let value = try await operation()

            if let authenticatedSession = value as? AuthSession {
                session = authenticatedSession
            } else if let loginResult = value as? EmailLoginResult,
                      case .authenticated(let authenticatedSession) = loginResult {
                session = authenticatedSession
            }

            return value
        } catch let error as MfaRequiredError {
            pendingMfaChallenge = error.challenge
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
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

private struct AppleAuthorizationResult {
    let idToken: String?
    let authorizationCode: String?
    let firstName: String?
    let lastName: String?
    let email: String?
}

private final class AppleAuthorizationSession: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let rawNonce: String
    private let state: String
    private var controller: ASAuthorizationController?
    private var continuation: CheckedContinuation<AppleAuthorizationResult, Error>?

    init(rawNonce: String, state: String) {
        self.rawNonce = rawNonce
        self.state = state
        super.init()
    }

    func start() async throws -> AppleAuthorizationResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = rawNonce.sha256HexDigest
            request.state = state

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    func cancel() {
        guard continuation != nil else {
            return
        }

        controller?.cancel()
        finish(with: .failure(CancellationError()))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first ?? NSWindow()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(with: .failure(AuthServiceError.invalidResponse))
            return
        }

        guard credential.state == state else {
            finish(with: .failure(AuthServiceError.callbackStateMismatch))
            return
        }

        finish(
            with: .success(
                AppleAuthorizationResult(
                    idToken: credential.identityToken.flatMap { String(data: $0, encoding: .utf8) },
                    authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                    firstName: credential.fullName?.givenName,
                    lastName: credential.fullName?.familyName,
                    email: credential.email
                )
            )
        )
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue {
            finish(with: .failure(CancellationError()))
        } else {
            finish(with: .failure(error))
        }
    }

    private func finish(with result: Result<AppleAuthorizationResult, Error>) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        controller?.delegate = nil
        controller?.presentationContextProvider = nil
        controller = nil

        switch result {
        case .success(let authorization):
            continuation.resume(returning: authorization)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

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

private final class DesktopOAuthCallbackWaiter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.alexdem.speechara.auth.deeplink")
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var bufferedCallbackURL: URL?
    private var terminalError: Error?

    func receive(_ url: URL) {
        queue.async {
            self.finishCallbackLocked(with: .success(url))
        }
    }

    func waitForCallback(timeout: TimeInterval, timeoutError: Error) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: URL.self) { group in
                group.addTask {
                    try await self.nextCallback()
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw timeoutError
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
        queue.async {
            self.finishCallbackLocked(with: .failure(CancellationError()))
        }
    }

    private func nextCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let bufferedCallbackURL = self.bufferedCallbackURL {
                    self.bufferedCallbackURL = nil
                    continuation.resume(returning: bufferedCallbackURL)
                    return
                }

                if let terminalError = self.terminalError {
                    continuation.resume(throwing: terminalError)
                    return
                }

                self.callbackContinuation = continuation
            }
        }
    }

    private func finishCallbackLocked(with result: Result<URL, Error>) {
        guard terminalError == nil else {
            return
        }

        switch result {
        case .success(let url):
            if let callbackContinuation {
                self.callbackContinuation = nil
                callbackContinuation.resume(returning: url)
            } else if bufferedCallbackURL == nil {
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
    }
}

private final class LoopbackOAuthRedirectServer {
    private static let redirectHost = "localhost"

    private let callbackPath: String
    private let port: UInt16
    private let queue = DispatchQueue(label: "com.alexdem.speechara.auth.loopback")
    private var listener: NWListener?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var bufferedCallbackURL: URL?
    private var terminalError: Error?
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]

    var redirectURL: URL {
        URL(string: "http://\(Self.redirectHost):\(port)\(callbackPath)")!
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

    func waitForCallback(timeout: TimeInterval, timeoutError: Error) async throws -> URL {
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
                    throw timeoutError
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
        activeConnections[ObjectIdentifier(connection)] = connection
        connection.start(queue: queue)
        receiveNextChunk(on: connection, bufferedData: Data())
    }

    private func receiveNextChunk(on connection: NWConnection, bufferedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }

            if error != nil {
                closeConnection(connection)
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
                        kind: .failure,
                        deepLinkURL: nil
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
        guard let requestURL = URL(string: "http://\(Self.redirectHost):\(port)\(target)"),
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
                    kind: .failure,
                    deepLinkURL: nil
                )
            )
            finishCallback(with: .failure(AuthServiceError.callbackReturnedError(description)))
            return
        }

        guard let code = items["code"], !code.isEmpty,
              let state = items["state"], !state.isEmpty else {
            sendHTMLResponse(
                on: connection,
                statusCode: 400,
                body: Self.callbackHTML(
                    title: "Sign-in failed",
                    message: "Speechara received an incomplete Microsoft sign-in callback. Return to the app and try again.",
                    kind: .failure,
                    deepLinkURL: nil
                )
            )
            finishCallback(with: .failure(AuthServiceError.invalidCallback))
            return
        }

        sendHTMLResponse(
            on: connection,
            statusCode: 200,
            body: Self.callbackHTML(
                title: "Sign-in complete",
                message: "You can return to Speechara. This browser tab can be closed.",
                kind: .success,
                deepLinkURL: "speechara://auth/microsoft/complete"
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
                kind: .failure,
                deepLinkURL: nil
            )
        )
    }

    private func sendHTMLResponse(on connection: NWConnection, statusCode: Int, body: String) {
        let bodyData = Data(body.utf8)
        let header = [
            "HTTP/1.1 \(statusCode) \(Self.reasonPhrase(for: statusCode))",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")

        var responseData = Data(header.utf8)
        responseData.append(bodyData)

        connection.send(
            content: responseData,
            contentContext: .defaultMessage,
            isComplete: true,
            completion: .contentProcessed { [weak self] _ in
                self?.queue.asyncAfter(deadline: .now() + 0.25) {
                    self?.closeConnection(connection)
                }
            }
        )
    }

    private func closeConnection(_ connection: NWConnection) {
        activeConnections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
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

    private static func callbackHTML(
        title: String,
        message: String,
        kind: CallbackPageKind,
        deepLinkURL: String?
    ) -> String {
        let safeTitle = htmlEscaped(title)
        let safeMessage = htmlEscaped(message)
        let script = callbackScript(deepLinkURL: deepLinkURL)

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'">
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
            button {
              margin-top: 24px;
              border: 0;
              border-radius: 8px;
              background: #15181c;
              color: white;
              cursor: pointer;
              font: inherit;
              font-size: 15px;
              font-weight: 600;
              padding: 10px 16px;
            }
            button:focus-visible {
              outline: 3px solid rgba(21,24,28,0.24);
              outline-offset: 3px;
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
            <button type="button" onclick="window.close()">Close tab</button>
          </main>
          \(script)
        </body>
        </html>
        """
    }

    private static func callbackScript(deepLinkURL: String?) -> String {
        let historyPath = javaScriptStringEscaped(callbackPathForHistory)
        let deepLinkScript = deepLinkURL.map { url in
            let escapedURL = javaScriptStringEscaped(url)
            return """
                  window.setTimeout(function () {
                    window.location.href = "\(escapedURL)";
                  }, 300);
            """
        } ?? ""

        return """
        <script>
          try {
            window.history.replaceState(null, "Speechara Sign In", "\(historyPath)");
            \(deepLinkScript)
          } catch (_) {}
        </script>
        """
    }

    private static var callbackPathForHistory: String {
        "/oauth/microsoft/callback"
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

    private static func javaScriptStringEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let paddingLength = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: paddingLength))

        self.init(base64Encoded: base64)
    }
}

private extension Dictionary where Key == String, Value == String {
    var formURLEncodedData: Data {
        map { key, value in
            "\(key.formURLEncoded)=\(value.formURLEncoded)"
        }
        .joined(separator: "&")
        .data(using: .utf8) ?? Data()
    }
}

private extension String {
    var formURLEncoded: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
