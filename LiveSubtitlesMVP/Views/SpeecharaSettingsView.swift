import SwiftUI

struct SpeecharaSettingsView: View {
    @EnvironmentObject private var localizationStore: SpeecharaLocalizationStore
    @AppStorage("speechara.appearanceMode") private var appearanceModeRawValue = SpeecharaAppearanceMode.system.rawValue

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
            }
            .formStyle(.grouped)
        }
        .padding(20)
        .frame(width: 520, height: 250)
    }
}
