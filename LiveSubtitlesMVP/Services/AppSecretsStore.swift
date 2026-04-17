import Foundation

enum AppSecretKind: CaseIterable, Identifiable {
    case deepgram
    case deepseek

    var id: Self { self }

    var environmentKey: String {
        switch self {
        case .deepgram:
            return "DEEPGRAM_API_KEY"
        case .deepseek:
            return "DEEPSEEK_API_KEY"
        }
    }

    var defaultsKey: String {
        switch self {
        case .deepgram:
            return "speechara.savedDeepgramAPIKey"
        case .deepseek:
            return "speechara.savedDeepSeekAPIKey"
        }
    }

    var displayName: String {
        switch self {
        case .deepgram:
            return "Transcription API key"
        case .deepseek:
            return "AI service API key"
        }
    }
}

final class AppSecretsStore {
    static let shared = AppSecretsStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func resolvedValue(for kind: AppSecretKind) -> String? {
        if let environmentValue = environmentValue(for: kind) {
            return environmentValue
        }

        return savedValue(for: kind)
    }

    func environmentValue(for kind: AppSecretKind) -> String? {
        let rawValue = ProcessInfo.processInfo.environment[kind.environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        return rawValue
    }

    func savedValue(for kind: AppSecretKind) -> String? {
        let rawValue = defaults.string(forKey: kind.defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        return rawValue
    }

    func save(_ value: String, for kind: AppSecretKind) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty {
            defaults.removeObject(forKey: kind.defaultsKey)
            return
        }

        defaults.set(trimmedValue, forKey: kind.defaultsKey)
    }
}

enum AppConfigurationKind: CaseIterable, Identifiable {
    case authBackendBaseURL
    case defaultWorkspaceID

    var id: Self { self }

    var environmentKey: String {
        switch self {
        case .authBackendBaseURL:
            return "SPEECHARA_AUTH_BASE_URL"
        case .defaultWorkspaceID:
            return "SPEECHARA_DEFAULT_WORKSPACE_ID"
        }
    }

    var defaultsKey: String {
        switch self {
        case .authBackendBaseURL:
            return "speechara.savedAuthBackendBaseURL"
        case .defaultWorkspaceID:
            return "speechara.savedDefaultWorkspaceID"
        }
    }

    var displayName: String {
        switch self {
        case .authBackendBaseURL:
            return "Auth backend URL"
        case .defaultWorkspaceID:
            return "Default workspace ID"
        }
    }

    var defaultValue: String? {
        switch self {
        case .authBackendBaseURL:
            return "https://api.speechara.ai"
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
}
