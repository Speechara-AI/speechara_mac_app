import Foundation

// Offline transport dependencies for testing the production history service.
struct AuthSession {
    let accessToken = "test-token"
    let user = AuthenticatedUser()
}
struct AuthenticatedUser {
    let currentWorkspaceID: String? = "test-workspace"
    let defaultWorkspaceID: String? = nil
    let workspaceID: String? = nil
    let currentWorkspace: Workspace? = nil
    let defaultWorkspace: Workspace? = nil
    let workspace: Workspace? = nil
    let workspaces: [Workspace]? = nil
}
struct Workspace { let id: String }
enum AuthServiceError: Error { case requestFailed(String) }
final class AuthService {
    static let shared = AuthService()
    func activeSession() async throws -> AuthSession { AuthSession() }
}
enum AppConfigurationKind {
    case authBackendBaseURL, defaultWorkspaceID
    var defaultValue: String? { "test-workspace" }
}
final class AppConfigurationStore {
    static let shared = AppConfigurationStore()
    func resolvedValue(for kind: AppConfigurationKind) -> String? {
        kind == .authBackendBaseURL ? "https://history.test" : "test-workspace"
    }
}

final class MockHistoryTransport: URLProtocol {
    static var handler: (([String: Any]) throws -> [String: Any])!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
                body = data
            }
            let json = try JSONSerialization.jsonObject(with: body!) as! [String: Any]
            let response = try Self.handler(json)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: response))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
