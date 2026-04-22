import AppKit
import SwiftUI

@main
struct SpeecharaApp: App {
    @StateObject private var authStore = AuthSessionStore()
    @StateObject private var localizationStore = SpeecharaLocalizationStore.shared
    @AppStorage("speechara.appearanceMode") private var appearanceModeRawValue = SpeecharaAppearanceMode.system.rawValue

    private var appearanceMode: SpeecharaAppearanceMode {
        SpeecharaAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    init() {
        SpeecharaLocalizationStore.shared.installBundleOverrideIfNeeded()
    }

    var body: some Scene {
        WindowGroup("Speechara") {
            SpeecharaRootView()
                .environmentObject(authStore)
                .environmentObject(localizationStore)
                .environment(\.locale, localizationStore.locale)
                .preferredColorScheme(appearanceMode.preferredColorScheme)
                .id(localizationStore.language.rawValue)
        }
        .commands {
            SpeecharaFileCommands()
        }

        Window(SL("Settings"), id: "speechara-settings") {
            SpeecharaSettingsView()
                .environmentObject(authStore)
                .environmentObject(localizationStore)
                .environment(\.locale, localizationStore.locale)
                .preferredColorScheme(appearanceMode.preferredColorScheme)
                .id(localizationStore.language.rawValue)
        }
        .windowResizability(.contentSize)
    }
}

private struct SpeecharaFileCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("speechara.uiLanguage") private var selectedLanguageRawValue = SpeecharaLocalizationStore.shared.language.rawValue

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()

            Button(SL("Settings...")) {
                openWindow(id: "speechara-settings")
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button(SL("Settings...")) {
                openWindow(id: "speechara-settings")
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}

enum SpeecharaAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return SL("System")
        case .light:
            return SL("Light")
        case .dark:
            return SL("Dark")
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

struct SpeecharaRGBA {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    init(_ red: Double, _ green: Double, _ blue: Double, _ opacity: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
}

extension Color {
    static func speecharaDynamic(light: SpeecharaRGBA, dark: SpeecharaRGBA) -> Color {
        Color(
            nsColor: NSColor(
                name: nil,
                dynamicProvider: { appearance in
                    let isDarkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    let resolved = isDarkMode ? dark : light
                    return NSColor(
                        calibratedRed: resolved.red,
                        green: resolved.green,
                        blue: resolved.blue,
                        alpha: resolved.opacity
                    )
                }
            )
        )
    }
}
