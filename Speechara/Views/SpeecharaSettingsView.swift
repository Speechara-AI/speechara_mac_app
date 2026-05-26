import SwiftUI

struct SpeecharaSettingsView: View {
    @EnvironmentObject private var localizationStore: SpeecharaLocalizationStore
    @AppStorage("speechara.appearanceMode") private var appearanceModeRawValue = SpeecharaAppearanceMode.system.rawValue
    @State private var authBackendBaseURL = ""
    @State private var microsoftClientID = ""

    private var appearanceSelection: Binding<SpeecharaAppearanceMode> {
        Binding(
            get: {
                SpeecharaAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
            },
            set: { newValue in
                appearanceModeRawValue = newValue.rawValue
            }
        )
    }

    private var languageSelection: Binding<SpeecharaAppLanguage> {
        Binding(
            get: {
                localizationStore.language
            },
            set: { newValue in
                localizationStore.setLanguage(newValue)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.title2.weight(.bold))

                Text("Choose how Speechara looks and reads. Changes apply immediately.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                Section("Appearance") {
                    Picker("Theme", selection: appearanceSelection) {
                        ForEach(SpeecharaAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Switches the whole app between Light, Dark, or the current macOS appearance. Changes apply immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Language") {
                    Picker("App language", selection: languageSelection) {
                        ForEach(SpeecharaAppLanguage.allCases) { language in
                            Text(language.pickerDisplayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Changes the entire app UI between English, Russian, German, Spanish, and French.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Authentication") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Auth backend URL", text: $authBackendBaseURL)
                            .textFieldStyle(.roundedBorder)

                        Text("Defaults to https://api.speechara.ai. Use this only for local or staging backends.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Microsoft client ID", text: $microsoftClientID)
                            .textFieldStyle(.roundedBorder)

                        Text("Required for Microsoft desktop sign-in. It must match the Microsoft client ID configured on the backend.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Save authentication settings") {
                        saveAuthenticationSettings()
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(20)
        .frame(width: 560, height: 430)
        .onAppear {
            loadAuthenticationSettings()
        }
    }

    private func loadAuthenticationSettings() {
        authBackendBaseURL = AppConfigurationStore.shared.savedValue(for: .authBackendBaseURL)
            ?? AppConfigurationKind.authBackendBaseURL.defaultValue
            ?? ""
        microsoftClientID = AppConfigurationStore.shared.savedValue(for: .microsoftClientID) ?? ""
    }

    private func saveAuthenticationSettings() {
        AppConfigurationStore.shared.save(authBackendBaseURL, for: .authBackendBaseURL)
        AppConfigurationStore.shared.save(microsoftClientID, for: .microsoftClientID)
    }
}
