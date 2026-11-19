import AppKit
import SwiftUI

private enum SpeecharaAppSection: String, Identifiable {
    case workspace
    case profile
    case history

    static let sidebarOrder: [SpeecharaAppSection] = [
        .workspace,
        .history,
        .profile,
    ]

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
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var authStore: AuthSessionStore
    @ObservedObject private var updateController = SpeecharaUpdateController.shared
    @AppStorage("speechara.focusModeEnabled") private var isFocusModeEnabled = false
    @AppStorage("speechara.sidebarCollapsed") private var isSidebarCollapsed = true
    @State private var selectedSection: SpeecharaAppSection = .workspace
    @State private var isSidebarManuallyHidden = false
    @State private var isSidebarRevealHandleHovered = false

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                if !isSidebarHidden {
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

            if isSidebarHidden {
                sidebarRevealHandle
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .background(shellBackground.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.22), value: isSidebarHidden)
        .animation(.easeInOut(duration: 0.20), value: isSidebarCollapsed)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                SpeecharaSidebarVisibilityButton(
                    isSidebarHidden: isSidebarHidden,
                    action: toggleSidebarVisibility
                )
            }
        }
        // Individual sections define the width they actually need. Keeping the
        // shell itself compact lets the workspace shrink further in rows mode.
        .frame(minWidth: 760, minHeight: 820)
    }

    private var isSidebarHidden: Bool {
        isSidebarManuallyHidden || isSidebarHiddenForFocusMode
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
        VStack(spacing: isSidebarCollapsed ? 14 : 22) {
            appMark

            VStack(spacing: isSidebarCollapsed ? 8 : 12) {
                ForEach(SpeecharaAppSection.sidebarOrder) { section in
                    SpeecharaSidebarButton(
                        title: section.title,
                        systemImage: section.systemImage,
                        isSelected: selectedSection == section,
                        isCompact: isSidebarCollapsed
                    ) {
                        selectedSection = section
                    }
                }

                SpeecharaSidebarButton(
                    title: SL("Settings"),
                    systemImage: "gearshape",
                    isSelected: false,
                    isCompact: isSidebarCollapsed
                ) {
                    openSettingsWindow()
                }
            }

            Spacer(minLength: 0)

#if !APP_STORE
            if updateController.isUpdateAvailable {
                SpeecharaSidebarUpdateButton(isCompact: isSidebarCollapsed) {
                    updateController.checkForUpdates()
                }
                .padding(.horizontal, isSidebarCollapsed ? 2 : 10)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
#endif

            if let user = authStore.currentUser {
                VStack(spacing: 10) {
                    SpeecharaSidebarAvatar(
                        initials: user.initials,
                        avatarURL: user.avatarURL,
                        isCompact: isSidebarCollapsed
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, isSidebarCollapsed ? 2 : 10)
                .padding(.vertical, isSidebarCollapsed ? 5 : 14)
                .background(
                    RoundedRectangle(cornerRadius: isSidebarCollapsed ? 18 : 28)
                        .fill(SpeecharaShellTheme.sidebarPanelFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isSidebarCollapsed ? 18 : 28)
                        .stroke(SpeecharaShellTheme.sidebarPanelBorder, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 28))
                .contextMenu {
                    Button("Sign out", role: .destructive) {
                        authStore.signOut()
                    }
                }
            }

            sidebarCollapseButton
        }
        .padding(.horizontal, isSidebarCollapsed ? 6 : 14)
        .padding(.vertical, isSidebarCollapsed ? 14 : 18)
        .frame(width: isSidebarCollapsed ? 64 : 138)
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SpeecharaShellTheme.sidebarDivider)
                .frame(width: 1)
        }
    }

    private var sidebarRevealHandle: some View {
        Button(action: revealSidebar) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSidebarRevealHandleHovered
                            ? SpeecharaShellTheme.selectedButtonFill
                            : SpeecharaShellTheme.sidebarPanelFill
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isSidebarRevealHandleHovered
                                    ? SpeecharaShellTheme.selectedButtonBorder
                                    : SpeecharaShellTheme.sidebarPanelBorder,
                                lineWidth: 1
                            )
                    )
                    .frame(width: 24, height: 68)
                    .offset(x: -8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(
                        isSidebarRevealHandleHovered
                            ? SpeecharaShellTheme.selectedButtonIcon
                            : SpeecharaShellTheme.buttonIcon
                    )
                    .frame(width: 16, height: 68)
            }
                .frame(width: 16, height: 68, alignment: .leading)
                .clipped()
                .shadow(
                    color: Color.black.opacity(isSidebarRevealHandleHovered ? 0.17 : 0.10),
                    radius: isSidebarRevealHandleHovered ? 11 : 8,
                    x: 2,
                    y: 0
                )
                .frame(width: 24, height: 72, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            isSidebarRevealHandleHovered = isHovered
        }
        .animation(.easeOut(duration: 0.14), value: isSidebarRevealHandleHovered)
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onEnded { value in
                    if value.translation.width > 12 {
                        revealSidebar()
                    }
                }
        )
        .help(SL("Show sidebar"))
        .accessibilityLabel(SL("Show sidebar"))
    }

    private var appMark: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: isSidebarCollapsed ? 40 : 58, height: isSidebarCollapsed ? 40 : 58)
            .clipShape(RoundedRectangle(cornerRadius: isSidebarCollapsed ? 12 : 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: isSidebarCollapsed ? 8 : 14, x: 0, y: 6)
        .frame(maxWidth: .infinity)
        .padding(.top, isSidebarCollapsed ? 0 : 4)
        .padding(.bottom, isSidebarCollapsed ? 4 : 8)
    }

    private var sidebarCollapseButton: some View {
        Button {
            isSidebarCollapsed.toggle()
        } label: {
            Image(systemName: isSidebarCollapsed ? "chevron.right" : "chevron.left")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(SpeecharaShellTheme.buttonIcon)
                .frame(width: 32, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(SpeecharaShellTheme.buttonFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(SpeecharaShellTheme.buttonBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(SL(isSidebarCollapsed ? "Expand sidebar" : "Collapse sidebar"))
        .accessibilityLabel(SL(isSidebarCollapsed ? "Expand sidebar" : "Collapse sidebar"))
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

    private func openSettingsWindow() {
        openWindow(id: "speechara-settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func toggleSidebarVisibility() {
        if isSidebarHidden {
            revealSidebar()
        } else {
            isSidebarManuallyHidden = true
        }
    }

    private func revealSidebar() {
        isSidebarManuallyHidden = false

        if isSidebarHiddenForFocusMode {
            isFocusModeEnabled = false
        }
    }
}

private struct SpeecharaSidebarVisibilityButton: View {
    let isSidebarHidden: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SpeecharaShellTheme.buttonIcon)
                .frame(width: 28, height: 24)
                .overlay(alignment: .topTrailing) {
                    if isSidebarHidden {
                        Circle()
                            .fill(Color(red: 0.96, green: 0.55, blue: 0.14))
                            .frame(width: 6, height: 6)
                            .overlay(
                                Circle()
                                    .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                            )
                            .offset(x: -2, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(SL(isSidebarHidden ? "Show sidebar" : "Hide sidebar"))
        .accessibilityLabel(SL(isSidebarHidden ? "Show sidebar" : "Hide sidebar"))
    }
}

private struct SpeecharaSidebarButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isCompact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: isCompact ? 0 : 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: isCompact ? 13 : 16)
                        .fill(
                            isSelected
                                ? SpeecharaShellTheme.selectedButtonFill
                                : SpeecharaShellTheme.buttonFill
                        )
                        .frame(width: isCompact ? 42 : 54, height: isCompact ? 42 : 54)

                    RoundedRectangle(cornerRadius: isCompact ? 13 : 16)
                        .stroke(
                            isSelected
                                ? SpeecharaShellTheme.selectedButtonBorder
                                : SpeecharaShellTheme.buttonBorder,
                            lineWidth: 1
                        )
                        .frame(width: isCompact ? 42 : 54, height: isCompact ? 42 : 54)

                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? SpeecharaShellTheme.selectedButtonIcon
                                : SpeecharaShellTheme.buttonIcon
                        )
                }

                if !isCompact {
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
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isCompact ? 2 : 12)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct SpeecharaSidebarUpdateButton: View {
    let isCompact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isCompact ? 0 : 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .bold))

                if !isCompact {
                    Text(SL("Update"))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: isCompact ? nil : .infinity)
            .frame(width: isCompact ? 38 : nil, height: isCompact ? 38 : 34)
            .background(
                RoundedRectangle(cornerRadius: isCompact ? 12 : 15, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.42, blue: 0.84))
            )
            .overlay(
                RoundedRectangle(cornerRadius: isCompact ? 12 : 15, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.10, green: 0.42, blue: 0.84).opacity(0.22), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .help(SL("Install available update"))
    }
}

private struct SpeecharaSidebarAvatar: View {
    let initials: String
    let avatarURL: String?
    let isCompact: Bool

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
                .frame(width: isCompact ? 40 : 62, height: isCompact ? 40 : 62)

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
                .frame(width: isCompact ? 34 : 54, height: isCompact ? 34 : 54)
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
            .font(.system(size: isCompact ? 12 : 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: isCompact ? 34 : 54, height: isCompact ? 34 : 54)
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
