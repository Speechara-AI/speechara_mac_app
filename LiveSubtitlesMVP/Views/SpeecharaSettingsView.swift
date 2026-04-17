import SwiftUI

struct SpeecharaSettingsView: View {
    @EnvironmentObject private var authStore: AuthSessionStore

    @State private var deepgramAPIKey = AppSecretsStore.shared.savedValue(for: .deepgram) ?? ""
    @State private var deepSeekAPIKey = AppSecretsStore.shared.savedValue(for: .deepseek) ?? ""
    @State private var authBackendURL = AppConfigurationStore.shared.savedValue(for: .authBackendBaseURL) ?? ""
    @State private var defaultWorkspaceID = AppConfigurationStore.shared.savedValue(for: .defaultWorkspaceID) ?? ""
    @State private var saveMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Speechara Settings")
                    .font(.title2.weight(.bold))

                Text("Configure temporary local credentials, inspect the current desktop sign-in state, and override the auth backend only when you need a non-production environment.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                Section("Authentication") {
                    configurationField(
                        kind: .authBackendBaseURL,
                        value: $authBackendURL,
                        placeholder: AppConfigurationKind.authBackendBaseURL.defaultValue ?? "https://api.speechara.ai"
                    )

                    configurationField(
                        kind: .defaultWorkspaceID,
                        value: $defaultWorkspaceID,
                        placeholder: AppConfigurationKind.defaultWorkspaceID.defaultValue ?? ""
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current account")
                            .font(.headline)

                        if let displayName = authStore.signedInDisplayName,
                           let email = authStore.signedInEmail {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(displayName)
                                    .font(.body.weight(.semibold))

                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("No desktop session is active.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("API Keys") {
                    settingsField(
                        kind: .deepgram,
                        value: $deepgramAPIKey,
                        placeholder: "Paste a temporary transcription key"
                    )

                    settingsField(
                        kind: .deepseek,
                        value: $deepSeekAPIKey,
                        placeholder: "Paste a temporary AI service key"
                    )
                }
            }
            .formStyle(.grouped)

            HStack(spacing: 12) {
                Button("Save keys") {
                    AppSecretsStore.shared.save(deepgramAPIKey, for: .deepgram)
                    AppSecretsStore.shared.save(deepSeekAPIKey, for: .deepseek)
                    AppConfigurationStore.shared.save(authBackendURL, for: .authBackendBaseURL)
                    AppConfigurationStore.shared.save(defaultWorkspaceID, for: .defaultWorkspaceID)
                    saveMessage = authBackendURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Saved locally for this app. Production auth URL will be used by default."
                        : "Saved locally for this app."
                }
                .buttonStyle(.borderedProminent)

                Button("Clear saved config") {
                    deepgramAPIKey = ""
                    deepSeekAPIKey = ""
                    authBackendURL = ""
                    defaultWorkspaceID = ""
                    AppSecretsStore.shared.save("", for: .deepgram)
                    AppSecretsStore.shared.save("", for: .deepseek)
                    AppConfigurationStore.shared.save("", for: .authBackendBaseURL)
                    AppConfigurationStore.shared.save("", for: .defaultWorkspaceID)
                    saveMessage = "Saved keys and auth override were cleared. Production auth URL will be used."
                }
                .buttonStyle(.bordered)

                if authStore.isAuthenticated {
                    Button("Sign out") {
                        authStore.signOut()
                        saveMessage = "Desktop session was cleared."
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(width: 680, height: 460)
    }

    private func settingsField(
        kind: AppSecretKind,
        value: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(kind.displayName)
                    .font(.headline)

                if AppSecretsStore.shared.environmentValue(for: kind) != nil {
                    Label("Environment override", systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.14))
                        )
                        .foregroundStyle(.orange)
                }
            }

            SecureField(placeholder, text: value)
                .textFieldStyle(.roundedBorder)

            Text(helperText(for: kind))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func helperText(for kind: AppSecretKind) -> String {
        if AppSecretsStore.shared.environmentValue(for: kind) != nil {
            return "This launch already has \(kind.environmentKey) in the environment, so the saved value is currently ignored."
        }

        return "If the environment key is missing, Speechara will use this saved value."
    }

    private func configurationField(
        kind: AppConfigurationKind,
        value: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(kind.displayName)
                    .font(.headline)

                if AppConfigurationStore.shared.environmentValue(for: kind) != nil {
                    Label("Environment override", systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.14))
                        )
                        .foregroundStyle(.orange)
                }
            }

            TextField(placeholder, text: value)
                .textFieldStyle(.roundedBorder)

            Text(configurationHelperText(for: kind))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func configurationHelperText(for kind: AppConfigurationKind) -> String {
        if AppConfigurationStore.shared.environmentValue(for: kind) != nil {
            return "This launch already has \(kind.environmentKey) in the environment, so the saved value is currently ignored."
        }

        switch kind {
        case .authBackendBaseURL:
            let defaultValue = kind.defaultValue ?? "https://api.speechara.ai"
            return "Speechara defaults to \(defaultValue). Set this only to override the production auth backend."
        case .defaultWorkspaceID:
            let defaultValue = kind.defaultValue ?? ""
            return "Meeting history uses this workspace when the native auth session does not include workspace info. Leave the default unless you need a different workspace."
                + (defaultValue.isEmpty ? "" : " Default: \(defaultValue).")
        }
    }
}
