// This is appended to the production AuthService.swift so private protocol helpers are exercised unchanged.
final class AuthSecurityURLProtocol: URLProtocol {
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        let body = Data("""
        {"code":"MFA_REQUIRED","challengeId":"challenge-123","email":"alex@example.com",
         "maskedEmail":"a***@example.com","type":"totp","expiresIn":300,"expiresAt":"2026-11-19T16:00:00Z"}
        """.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

// Configuration and localization are not under test; every network request is intercepted above.
final class AppConfigurationStore {
    enum Key { case authBackendBaseURL, microsoftClientID }
    static let shared = AppConfigurationStore()
    func resolvedValue(for key: Key) -> String? { "https://auth-test.invalid" }
}
func SL(_ value: String) -> String { value }

extension AuthService {
    static func runAuthSecurityRegressionTests() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthSecurityURLProtocol.self]
        let auth = AuthService(session: URLSession(configuration: configuration))
        let transaction = try OAuthPKCETransaction()
        let second = try OAuthPKCETransaction()
        precondition(transaction.state != second.state && transaction.codeVerifier != second.codeVerifier)
        let backend = Configuration(baseURL: URL(string: "https://auth-test.invalid")!)
        let startURL = try auth.makeGoogleDesktopAuthorizationURL(configuration: backend,
            state: transaction.state, codeChallenge: transaction.codeChallenge)
        let query = URLComponents(url: startURL, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(query.contains { $0.name == "code_challenge" && $0.value == transaction.codeChallenge })
        precondition(query.contains { $0.name == "code_challenge_method" && $0.value == "S256" })
        precondition(!startURL.absoluteString.contains(transaction.codeVerifier))
        do {
            _ = try await auth.exchangeDesktopAuthCode(configuration: backend, code: "handoff-code",
                    state: transaction.state, codeVerifier: transaction.codeVerifier)
            preconditionFailure("Desktop MFA challenge was accepted as a session")
        } catch let error as MfaRequiredError {
            precondition(error.challenge.challengeId == "challenge-123")
        }
        precondition(AuthSecurityURLProtocol.requests.count == 1)
        let request = AuthSecurityURLProtocol.requests[0]
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        }
        let payload = try JSONSerialization.jsonObject(with: body!) as! [String: String]
        precondition(payload["code_verifier"] == transaction.codeVerifier)
        precondition(payload["state"] == transaction.state)
        do {
            _ = try await auth.exchangeMicrosoftIdToken("provider-token")
            preconditionFailure("Social MFA challenge was accepted as a session")
        } catch let error as MfaRequiredError {
            precondition(error.challenge.type == "totp")
        }
        do {
            _ = try CallbackPayload(url: URL(string: "speechara://auth/callback?code=one&state=one&state=two")!)
            preconditionFailure("Duplicate callback state was accepted")
        } catch is AuthServiceError {}
        print("PASS: desktop PKCE request/exchange, social MFA challenge, duplicate callback rejection")
    }
}

@main struct AuthSecurityTests {
    static func main() async throws { try await AuthService.runAuthSecurityRegressionTests() }
}
