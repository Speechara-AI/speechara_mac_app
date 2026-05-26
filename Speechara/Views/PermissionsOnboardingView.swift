import AppKit
import SwiftUI

let speecharaPermissionsOnboardingVersion = 1

struct SpeecharaRootView: View {
    @AppStorage("speechara.permissions.onboarding.version") private var permissionsOnboardingVersion = 0
    @EnvironmentObject private var authStore: AuthSessionStore

    var body: some View {
        Group {
            if authStore.isRestoringSession {
                AuthenticationLoadingView()
            } else if !authStore.isAuthenticated {
                AuthenticationView()
            } else if permissionsOnboardingVersion < speecharaPermissionsOnboardingVersion {
                PermissionsOnboardingView {
                    permissionsOnboardingVersion = speecharaPermissionsOnboardingVersion
                }
            } else {
                SpeecharaWorkspaceShellView()
            }
        }
    }
}

private struct PermissionsOnboardingView: View {
    @StateObject private var permissionsController = AppPermissionsController()

    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                HStack(spacing: 28) {
                    setupColumn
                        .frame(width: min(max(geometry.size.width * 0.54, 520), 680), alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .topLeading)

                    insightColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(32)
            }
        }
        .frame(minWidth: 1120, minHeight: 760)
        .onAppear {
            permissionsController.refreshStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionsController.refreshStatuses()
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: permissionsController.microphoneState)
    }

    private var setupColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            onboardingHero

            VStack(spacing: 16) {
                microphonePermissionCard
            }

            footerActions
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var insightColumn: some View {
        VStack(alignment: .leading, spacing: 22) {
            readinessCard
            benefitsCard
            stepsCard
            Spacer(minLength: 0)
        }
    }

    private var onboardingHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.92, green: 0.24, blue: 0.18),
                                    Color(red: 0.40, green: 0.48, blue: 0.95),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)

                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Prepare Speechara for live capture")
                        .font(.system(size: 40, weight: .bold, design: .rounded))

                    Text("Speechara captures system audio directly, without screen recording. Microphone access is optional for adding your own voice.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                SetupProgressBadge(
                    title: progressTitle,
                    progress: permissionsController.completionProgress
                )

                SetupStatusBadge(
                    title: readinessTitle,
                    iconName: readinessIcon,
                    tint: readinessTint
                )
            }
        }
    }

    private var microphonePermissionCard: some View {
        PermissionAccessCard(
            accent: Color(red: 0.10, green: 0.62, blue: 0.45),
            iconName: "mic.fill",
            title: "Optional microphone input",
            subtitle: "Lets Speechara add your own voice from the selected microphone when microphone mix-in is enabled.",
            statusTitle: microphoneStatusTitle,
            statusTint: microphoneStatusTint,
            actionTitle: microphoneActionTitle,
            actionIconName: microphoneActionIcon,
            isActionEnabled: !permissionsController.isRequestingMicrophoneAccess && !permissionsController.microphoneState.isGranted,
            isActionInProgress: permissionsController.isRequestingMicrophoneAccess,
            helpText: microphoneHelpText
        ) {
            Task {
                await permissionsController.requestMicrophoneAccess()
            }
        }
    }

    private var readinessCard: some View {
        InsightCard(accent: readinessTint.opacity(0.24)) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(readinessTint.opacity(0.15))
                            .frame(width: 48, height: 48)

                        Image(systemName: readinessIcon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(readinessTint)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(readinessTitle)
                            .font(.title3.weight(.bold))

                        Text(readinessSubtitle)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SetupReadinessMeter(progress: permissionsController.completionProgress, tint: readinessTint)

                Text(readinessDetail)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var benefitsCard: some View {
        InsightCard(accent: Color(red: 0.89, green: 0.57, blue: 0.20).opacity(0.20)) {
            VStack(alignment: .leading, spacing: 16) {
                Text("What turns on after setup")
                    .font(.headline)

                BenefitRow(
                    tint: Color(red: 0.10, green: 0.62, blue: 0.45),
                    iconName: "mic.fill",
                    title: "Audio-only system capture",
                    subtitle: "Speechara listens to system audio without asking for screen recording access."
                )

                BenefitRow(
                    tint: Color(red: 0.19, green: 0.45, blue: 0.95),
                    iconName: "menubar.rectangle",
                    title: "Menu bar control",
                    subtitle: "Start and stop listening while Speechara stays in the top bar."
                )

                BenefitRow(
                    tint: Color(red: 0.89, green: 0.57, blue: 0.20),
                    iconName: "sparkles",
                    title: "Live translation and assist",
                    subtitle: "Once audio is flowing, the rest of the pipeline can summarize, translate, and suggest replies."
                )
            }
        }
    }

    private var stepsCard: some View {
        InsightCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Quick path")
                    .font(.headline)

                StepRow(
                    isComplete: permissionsController.microphoneState.isGranted,
                    title: "Allow microphone access",
                    subtitle: "Optional for microphone mix-in and device testing."
                )
            }
        }
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !permissionsController.microphoneState.isGranted {
                Text("You can skip this once. Speechara will ask for microphone access later only if you enable microphone mix-in.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Button("Continue later") {
                    onContinue()
                }
                .buttonStyle(.bordered)

                Spacer()

                PermissionPrimaryButton(
                    title: primaryActionTitle,
                    iconName: primaryActionIcon,
                    tint: primaryActionTint,
                    isEnabled: primaryActionEnabled,
                    action: handlePrimaryAction
                )
            }
        }
    }

    private var progressTitle: String {
        let percent = Int((permissionsController.completionProgress * 100).rounded())
        return SLF("Setup %@%%", String(percent))
    }

    private var readinessTitle: String {
        if permissionsController.allRequiredPermissionsGranted {
            return SL("Ready to listen")
        }

        return SL("Permission setup")
    }

    private var readinessSubtitle: String {
        if permissionsController.microphoneState.isGranted {
            return SL("Microphone access is active in this launch.")
        }

        return SL("System audio starts without screen recording. Microphone access can be enabled later.")
    }

    private var readinessDetail: String {
        if permissionsController.microphoneState.isGranted {
            return SL("You can continue straight into the app and start a listening session without additional permission prompts.")
        }

        return SL("Speechara asks for microphone input only when microphone mix-in or testing needs it.")
    }

    private var readinessTint: Color {
        if permissionsController.allRequiredPermissionsGranted {
            return Color(red: 0.10, green: 0.62, blue: 0.45)
        }

        return Color(red: 0.89, green: 0.57, blue: 0.20)
    }

    private var readinessIcon: String {
        if permissionsController.allRequiredPermissionsGranted {
            return "checkmark.seal.fill"
        }

        return "slider.horizontal.3"
    }

    private var microphoneStatusTitle: String {
        switch permissionsController.microphoneState {
        case .notDetermined:
            return SL("Not requested")
        case .denied:
            return SL("Needs attention")
        case .granted:
            return SL("Granted")
        }
    }

    private var microphoneStatusTint: Color {
        switch permissionsController.microphoneState {
        case .notDetermined:
            return Color(red: 0.89, green: 0.57, blue: 0.20)
        case .denied:
            return Color(red: 0.84, green: 0.16, blue: 0.17)
        case .granted:
            return Color(red: 0.10, green: 0.62, blue: 0.45)
        }
    }

    private var microphoneActionTitle: String {
        switch permissionsController.microphoneState {
        case .notDetermined:
            return SL("Allow access")
        case .denied:
            return SL("Open settings")
        case .granted:
            return SL("Allowed")
        }
    }

    private var microphoneActionIcon: String {
        switch permissionsController.microphoneState {
        case .notDetermined:
            return "mic.badge.plus"
        case .denied:
            return "gearshape"
        case .granted:
            return "checkmark"
        }
    }

    private var microphoneHelpText: String {
        switch permissionsController.microphoneState {
        case .notDetermined:
            return SL("Speechara will ask macOS for microphone access the first time.")
        case .denied:
            return SL("If you previously denied access, turn it back on in System Settings and return here.")
        case .granted:
            return SL("Microphone input is active for this launch.")
        }
    }

    private var primaryActionTitle: String {
        if permissionsController.allRequiredPermissionsGranted {
            return SL("Open Speechara")
        }

        return SL("Grant access to continue")
    }

    private var primaryActionIcon: String {
        if permissionsController.allRequiredPermissionsGranted {
            return "play.fill"
        }

        return "lock.open.trianglebadge.exclamationmark"
    }

    private var primaryActionTint: Color {
        if permissionsController.allRequiredPermissionsGranted {
            return Color(red: 0.10, green: 0.62, blue: 0.45)
        }

        return Color(red: 0.74, green: 0.76, blue: 0.80)
    }

    private var primaryActionEnabled: Bool {
        permissionsController.allRequiredPermissionsGranted
    }

    private func handlePrimaryAction() {
        guard permissionsController.allRequiredPermissionsGranted else {
            return
        }

        onContinue()
    }

    private var backgroundGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.13),
                    Color(red: 0.11, green: 0.12, blue: 0.18),
                    Color(red: 0.13, green: 0.09, blue: 0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.97, blue: 0.95),
                Color(red: 0.95, green: 0.97, blue: 1.00),
                Color(red: 0.99, green: 0.96, blue: 0.95),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct PermissionAccessCard: View {
    let accent: Color
    let iconName: String
    let title: String
    let subtitle: String
    let statusTitle: String
    let statusTint: Color
    let actionTitle: String
    let actionIconName: String
    let isActionEnabled: Bool
    let isActionInProgress: Bool
    let helpText: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(accent.opacity(0.14))
                        .frame(width: 58, height: 58)

                    Image(systemName: iconName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(SL(title))
                            .font(.title3.weight(.bold))

                        SetupStatusBadge(
                            title: statusTitle,
                            iconName: statusIconName,
                            tint: statusTint
                        )
                    }

                    Text(SL(subtitle))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: 14) {
                Button(action: action) {
                    HStack(spacing: 8) {
                        if isActionInProgress {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: actionIconName)
                                .font(.system(size: 13, weight: .bold))
                        }

                        Text(SL(actionTitle))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(isActionEnabled ? .white : .secondary)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(
                        Capsule()
                            .fill(isActionEnabled ? accent : Color.secondary.opacity(0.10))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isActionEnabled)

                Text(SL(helpText))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(cardBorderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06), radius: 18, x: 0, y: 10)
    }

    private var statusIconName: String {
        isActionEnabled ? "clock.fill" : "checkmark.circle.fill"
    }

    private var cardBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.13, green: 0.15, blue: 0.18).opacity(0.96)
        }

        return Color.white.opacity(0.92)
    }

    private var cardBorderColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.08)
        }

        return Color.black.opacity(0.06)
    }
}

private struct InsightCard<Content: View>: View {
    var accent: Color? = nil
    let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(accent: Color? = nil, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(borderColor, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            if let accent {
                RoundedRectangle(cornerRadius: 28)
                    .fill(accent)
                    .blur(radius: 42)
                    .mask(
                        RoundedRectangle(cornerRadius: 28)
                    )
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.07), radius: 20, x: 0, y: 12)
    }

    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.12, green: 0.14, blue: 0.17).opacity(0.98)
        }

        return Color.white.opacity(0.94)
    }

    private var borderColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.08)
        }

        return Color.black.opacity(0.05)
    }
}

private struct BenefitRow: View {
    let tint: Color
    let iconName: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(SL(title))
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Text(SL(subtitle))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct StepRow: View {
    let isComplete: Bool
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isComplete ? Color(red: 0.10, green: 0.62, blue: 0.45) : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(SL(title))
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Text(SL(subtitle))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SetupProgressBadge: View {
    let title: String
    let progress: Double

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 104, height: 10)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.92, green: 0.24, blue: 0.18),
                                Color(red: 0.20, green: 0.45, blue: 0.95),
                                Color(red: 0.10, green: 0.62, blue: 0.45),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(12, 104 * progress), height: 10)
            }

            Text(SL(title))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct SetupStatusBadge: View {
    let title: String
    let iconName: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: iconName)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(tint.opacity(0.14))
            )
            .foregroundStyle(tint)
    }
}

private struct SetupAlertStrip: View {
    let iconName: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))

            Text(SL(text))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct SetupReadinessMeter: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.10))

                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.72),
                                tint,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(18, geometry.size.width * progress))
            }
        }
        .frame(height: 16)
    }
}

private struct PermissionPrimaryButton: View {
    let title: String
    let iconName: String
    let tint: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .bold))

                Text(SL(title))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.72))
            .padding(.horizontal, 26)
            .frame(height: 58)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                tint,
                                tint.opacity(0.82),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: tint.opacity(0.24), radius: 18, x: 0, y: 10)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.72)
    }
}
