import SwiftUI

struct SpeecharaSettingsView: View {
    @EnvironmentObject private var localizationStore: SpeecharaLocalizationStore
    @AppStorage("speechara.appearanceMode") private var appearanceModeRawValue = SpeecharaAppearanceMode.system.rawValue
    @AppStorage("speechara.isMiniWindowEnabled") private var isMiniWindowEnabled = true

    private var appearanceMode: SpeecharaAppearanceMode {
        SpeecharaAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    var body: some View {
        ZStack {
            SpeecharaSettingsTheme.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(SL("Settings"))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(SpeecharaSettingsTheme.primaryText)

                    VStack(spacing: 16) {
                        SpeecharaSettingsPanel(title: "Theme") {
                            themeSelector
                        }

                        SpeecharaSettingsPanel(title: "Interface language") {
                            languageSelector
                        }

                        SpeecharaSettingsPanel(title: "Mini Window") {
                            miniWindowToggle
                        }

#if !APP_STORE
                        SpeecharaSettingsPanel(title: "Updates") {
                            updateControl
                        }
#endif
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .frame(
            minWidth: 560,
            idealWidth: 600,
            maxWidth: .infinity,
            minHeight: 520,
            idealHeight: 560,
            maxHeight: .infinity
        )
    }

    private var themeSelector: some View {
        HStack(spacing: 0) {
            ForEach(SpeecharaAppearanceMode.allCases) { mode in
                SpeecharaThemeOptionButton(
                    mode: mode,
                    isSelected: appearanceMode == mode
                ) {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        appearanceModeRawValue = mode.rawValue
                    }
                }
            }
        }
        .padding(4)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(SpeecharaSettingsTheme.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(SpeecharaSettingsTheme.controlBorder, lineWidth: 1)
        )
    }

    private var languageSelector: some View {
        HStack(spacing: 12) {
            Image(systemName: "textformat")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(SpeecharaSettingsTheme.secondaryText)
                .frame(width: 24)

            Menu {
                ForEach(SpeecharaAppLanguage.allCases) { language in
                    Button {
                        NotificationCenter.default.post(name: .speecharaInterfaceLanguageWillChange, object: nil)
                        localizationStore.setLanguage(language)
                    } label: {
                        HStack {
                            Text(language.pickerDisplayName)

                            if localizationStore.language == language {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(localizationStore.language.pickerDisplayName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeecharaSettingsTheme.primaryText)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SpeecharaSettingsTheme.secondaryText)
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SpeecharaSettingsTheme.menuChipFill)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(SpeecharaSettingsTheme.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(SpeecharaSettingsTheme.controlBorder, lineWidth: 1)
        )
    }

    private var miniWindowToggle: some View {
        Toggle(isOn: $isMiniWindowEnabled) {
            HStack(spacing: 12) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(SpeecharaSettingsTheme.secondaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(SL("Show mini window"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeecharaSettingsTheme.primaryText)

                    Text(SL("Automatically show the floating listening window while a session is active."))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeecharaSettingsTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 58)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(SpeecharaSettingsTheme.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(SpeecharaSettingsTheme.controlBorder, lineWidth: 1)
        )
        .onChange(of: isMiniWindowEnabled) { isEnabled in
            if !isEnabled {
                SpeecharaMiniWindowCoordinator.closeMiniWindow()
            }
        }
    }

    private var updateControl: some View {
#if APP_STORE
        EmptyView()
#else
        Button {
            SpeecharaUpdateController.shared.checkForUpdates()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SpeecharaSettingsTheme.accent)

                Text(SL("Check for Updates..."))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeecharaSettingsTheme.primaryText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SpeecharaSettingsTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(SpeecharaSettingsTheme.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(SpeecharaSettingsTheme.controlBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Speechara checks updates from updates.speechara.ai and will ask before installing a new version.")
#endif
    }
}

private enum SpeecharaSettingsTheme {
    static let background = LinearGradient(
        colors: [
            Color.speecharaDynamic(
                light: SpeecharaRGBA(0.98, 0.99, 1.00),
                dark: SpeecharaRGBA(0.12, 0.14, 0.16)
            ),
            Color.speecharaDynamic(
                light: SpeecharaRGBA(0.93, 0.97, 1.00),
                dark: SpeecharaRGBA(0.09, 0.11, 0.14)
            ),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let panelFill = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.86, 0.98, 0.92, 0.82),
        dark: SpeecharaRGBA(0.13, 0.20, 0.20, 0.88)
    )
    static let panelBorder = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.72, 0.91, 0.84),
        dark: SpeecharaRGBA(0.22, 0.34, 0.34)
    )
    static let controlFill = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.95, 0.97, 1.00, 0.92),
        dark: SpeecharaRGBA(0.18, 0.20, 0.24, 0.94)
    )
    static let selectedControlFill = Color.speecharaDynamic(
        light: SpeecharaRGBA(1.00, 1.00, 1.00, 0.96),
        dark: SpeecharaRGBA(0.25, 0.29, 0.34, 0.96)
    )
    static let menuChipFill = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.84, 0.89, 0.96, 0.92),
        dark: SpeecharaRGBA(0.28, 0.31, 0.37, 0.94)
    )
    static let controlBorder = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.77, 0.84, 0.92),
        dark: SpeecharaRGBA(0.29, 0.34, 0.40)
    )
    static let primaryText = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.09, 0.16, 0.27),
        dark: SpeecharaRGBA(0.92, 0.95, 0.98)
    )
    static let secondaryText = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.40, 0.48, 0.60),
        dark: SpeecharaRGBA(0.64, 0.70, 0.78)
    )
    static let accent = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.09, 0.58, 0.84),
        dark: SpeecharaRGBA(0.34, 0.76, 1.00)
    )
}

private struct SpeecharaSettingsPanel<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(SL(title))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(SpeecharaSettingsTheme.primaryText)

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(SpeecharaSettingsTheme.panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(SpeecharaSettingsTheme.panelBorder, lineWidth: 1)
        )
    }
}

private struct SpeecharaThemeOptionButton: View {
    let mode: SpeecharaAppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))

                Text(mode.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? SpeecharaSettingsTheme.accent : SpeecharaSettingsTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 17)
                    .fill(isSelected ? SpeecharaSettingsTheme.selectedControlFill : Color.clear)
            )
            .shadow(
                color: isSelected ? Color.black.opacity(0.08) : .clear,
                radius: 8,
                x: 0,
                y: 3
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
    }

    private var iconName: String {
        switch mode {
        case .system:
            return "desktopcomputer"
        case .light:
            return "sun.max"
        case .dark:
            return "moon.fill"
        }
    }
}
