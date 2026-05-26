import AppKit
import SwiftUI

private enum SpeecharaAppSection: String, CaseIterable, Identifiable {
    case workspace
    case profile
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace:
            return SL("Workspace")
        case .profile:
            return SL("Profile")
        case .history:
            return SL("History")
        }
    }

    var systemImage: String {
        switch self {
        case .workspace:
            return "rectangle.split.3x1"
        case .profile:
            return "person.crop.circle"
        case .history:
            return "clock.arrow.circlepath"
        }
    }
}

private enum SpeecharaShellTheme {
    static let shellTop = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.98, 0.98, 0.97),
        dark: SpeecharaRGBA(0.09, 0.10, 0.13)
    )
    static let shellBottom = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.94, 0.96, 0.99),
        dark: SpeecharaRGBA(0.07, 0.11, 0.16)
    )
    static let sidebarTop = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.96, 0.97, 0.99),
        dark: SpeecharaRGBA(0.11, 0.13, 0.17)
    )
    static let sidebarBottom = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.92, 0.95, 0.98),
        dark: SpeecharaRGBA(0.09, 0.11, 0.15)
    )
    static let sidebarDivider = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.00, 0.00, 0.00, 0.08),
        dark: SpeecharaRGBA(1.00, 1.00, 1.00, 0.08)
    )
    static let sidebarPanelFill = Color.speecharaDynamic(
        light: SpeecharaRGBA(1.00, 1.00, 1.00, 0.62),
        dark: SpeecharaRGBA(0.17, 0.20, 0.25, 0.82)
    )
    static let sidebarPanelBorder = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.70, 0.78, 0.88),
        dark: SpeecharaRGBA(0.28, 0.34, 0.43)
    )
    static let buttonFill = Color.speecharaDynamic(
        light: SpeecharaRGBA(1.00, 1.00, 1.00, 0.62),
        dark: SpeecharaRGBA(0.17, 0.20, 0.25, 0.76)
    )
    static let selectedButtonFill = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.84, 0.92, 0.99),
        dark: SpeecharaRGBA(0.13, 0.28, 0.40, 0.95)
    )
    static let buttonBorder = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.76, 0.82, 0.90),
        dark: SpeecharaRGBA(0.28, 0.33, 0.40)
    )
    static let selectedButtonBorder = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.32, 0.62, 0.90, 0.85),
        dark: SpeecharaRGBA(0.23, 0.58, 0.90, 0.95)
    )
    static let buttonIcon = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.28, 0.35, 0.47),
        dark: SpeecharaRGBA(0.74, 0.80, 0.88)
    )
    static let selectedButtonIcon = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.12, 0.47, 0.80),
        dark: SpeecharaRGBA(0.82, 0.92, 1.00)
    )
    static let buttonText = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.34, 0.42, 0.53),
        dark: SpeecharaRGBA(0.75, 0.81, 0.89)
    )
    static let selectedButtonText = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.12, 0.22, 0.33),
        dark: SpeecharaRGBA(0.90, 0.95, 1.00)
    )
    static let avatarSurface = Color.speecharaDynamic(
        light: SpeecharaRGBA(1.00, 1.00, 1.00, 0.82),
        dark: SpeecharaRGBA(0.19, 0.22, 0.28, 0.92)
    )
    static let avatarBorder = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.73, 0.80, 0.89),
        dark: SpeecharaRGBA(0.30, 0.36, 0.45)
    )
}

struct SpeecharaWorkspaceShellView: View {
    @EnvironmentObject private var authStore: AuthSessionStore
    @AppStorage("speechara.focusModeEnabled") private var isFocusModeEnabled = false
    @State private var selectedSection: SpeecharaAppSection = .workspace

    var body: some View {
        HStack(spacing: 0) {
            if !isSidebarHiddenForFocusMode {
                sidebar
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            ZStack {
                shellBackground
                    .ignoresSafeArea()

                currentSection
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(shellBackground.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.22), value: isSidebarHiddenForFocusMode)
        .frame(minWidth: 1320, minHeight: 820)
    }

    private var isSidebarHiddenForFocusMode: Bool {
        selectedSection == .workspace && isFocusModeEnabled
    }

    private var shellBackground: LinearGradient {
        LinearGradient(
            colors: [
                SpeecharaShellTheme.shellTop,
                SpeecharaShellTheme.shellBottom,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var sidebarBackground: LinearGradient {
        LinearGradient(
            colors: [
                SpeecharaShellTheme.sidebarTop,
                SpeecharaShellTheme.sidebarBottom,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var sidebar: some View {
        VStack(spacing: 22) {
            appMark

            VStack(spacing: 12) {
                ForEach(SpeecharaAppSection.allCases) { section in
                    SpeecharaSidebarButton(
                        title: section.title,
                        systemImage: section.systemImage,
                        isSelected: selectedSection == section
                    ) {
                        selectedSection = section
                    }
                }
            }

            Spacer(minLength: 0)

            if let user = authStore.currentUser {
                VStack(spacing: 10) {
                    SpeecharaSidebarAvatar(
                        initials: user.initials,
                        avatarURL: user.avatarURL
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(SpeecharaShellTheme.sidebarPanelFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(SpeecharaShellTheme.sidebarPanelBorder, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 28))
                .contextMenu {
                    Button("Sign out", role: .destructive) {
                        authStore.signOut()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(width: 138)
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SpeecharaShellTheme.sidebarDivider)
                .frame(width: 1)
        }
    }

    private var appMark: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var currentSection: some View {
        switch selectedSection {
        case .workspace:
            ContentView()
        case .profile:
            SpeecharaProfileView()
        case .history:
            SpeecharaHistoryView()
        }
    }
}

private struct SpeecharaSidebarButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            isSelected
                                ? SpeecharaShellTheme.selectedButtonFill
                                : SpeecharaShellTheme.buttonFill
                        )
                        .frame(width: 54, height: 54)

                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isSelected
                                ? SpeecharaShellTheme.selectedButtonBorder
                                : SpeecharaShellTheme.buttonBorder,
                            lineWidth: 1
                        )
                        .frame(width: 54, height: 54)

                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? SpeecharaShellTheme.selectedButtonIcon
                                : SpeecharaShellTheme.buttonIcon
                        )
                }

                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        isSelected
                            ? SpeecharaShellTheme.selectedButtonText
                            : SpeecharaShellTheme.buttonText
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

private struct SpeecharaSidebarAvatar: View {
    let initials: String
    let avatarURL: String?

    private var resolvedAvatarURL: URL? {
        guard let avatarURL = avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !avatarURL.isEmpty else {
            return nil
        }

        return URL(string: avatarURL)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(SpeecharaShellTheme.avatarSurface)
                .frame(width: 62, height: 62)

            if let resolvedAvatarURL {
                AsyncImage(url: resolvedAvatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(Circle())
            } else {
                fallback
            }
        }
        .overlay(
            Circle()
                .stroke(SpeecharaShellTheme.avatarBorder, lineWidth: 1)
        )
    }

    private var fallback: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 54, height: 54)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.91, green: 0.23, blue: 0.18),
                        Color(red: 0.25, green: 0.45, blue: 0.95),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Circle())
    }
}
