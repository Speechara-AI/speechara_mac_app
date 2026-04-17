import AppKit
import SwiftUI

private let speecharaPermissionsOnboardingVersion = 1

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
                ContentView()
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
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: permissionsController.screenCaptureState)
    }

    private var setupColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            onboardingHero

            if permissionsController.shouldSuggestRelaunch {
                SetupAlertStrip(
                    iconName: "arrow.clockwise.circle.fill",
                    tint: Color(red: 0.19, green: 0.45, blue: 0.95),
                    text: "macOS approved screen capture for this launch. Restart Speechara once so system audio capture is fully available."
                )
            }

            VStack(spacing: 16) {
                microphonePermissionCard
                screenPermissionCard
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

                    Text("Enable the two macOS permissions that unlock system audio, microphone mix-in, and the full live transcription flow.")
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
            title: "Microphone input",
            subtitle: "Adds your own voice to the transcript, lets you test the selected mic, and mixes local speech into captured sessions.",
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

    private var screenPermissionCard: some View {
        PermissionAccessCard(
            accent: Color(red: 0.20, green: 0.45, blue: 0.95),
            iconName: "rectangle.on.rectangle.circle",
            title: "Screen and system audio",
            subtitle: "Required for ScreenCaptureKit to hear meeting audio from your Mac and feed it into the live transcript pipeline.",
            statusTitle: screenStatusTitle,
            statusTint: screenStatusTint,
            actionTitle: screenActionTitle,
            actionIconName: screenActionIcon,
            isActionEnabled: !permissionsController.isRequestingScreenCaptureAccess && permissionsController.screenCaptureState == .needsApproval,
            isActionInProgress: permissionsController.isRequestingScreenCaptureAccess,
            helpText: screenHelpText
        ) {
            permissionsController.requestScreenCaptureAccess()
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
                    tint: Color(red: 0.19, green: 0.45, blue: 0.95),
                    iconName: "speaker.wave.2.fill",
                    title: "System audio capture",
                    subtitle: "Speech from meetings, calls, and videos starts flowing into the transcript."
                )

                BenefitRow(
                    tint: Color(red: 0.10, green: 0.62, blue: 0.45),
                    iconName: "mic.badge.plus",
                    title: "Your microphone mixed in",
                    subtitle: "Speechara can keep your own voice in the same session when you want a full conversation log."
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
                    subtitle: "Needed for local voice capture and device testing."
                )

                StepRow(
                    isComplete: permissionsController.screenCaptureState.isApproved,
                    title: "Approve screen and system audio",
                    subtitle: "Needed for meeting audio from macOS."
                )

                StepRow(
                    isComplete: permissionsController.screenCaptureState != .restartRequired,
                    title: "Reopen Speechara once",
                    subtitle: "Only needed if screen access was granted during this launch."
                )
            }
        }
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !permissionsController.allRequiredPermissionsGranted && !permissionsController.shouldSuggestRelaunch {
                Text("You can skip this once, but Speechara will only capture live sessions correctly after both permissions are enabled.")
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
        return "Setup \(percent)%"
    }

    private var readinessTitle: String {
        if permissionsController.shouldSuggestRelaunch {
            return "Restart required"
        }

        if permissionsController.allRequiredPermissionsGranted {
            return "Ready to listen"
        }

        return "Permission setup"
    }

    private var readinessSubtitle: String {
        if permissionsController.shouldSuggestRelaunch {
            return "Speechara has everything it needs, but screen capture only becomes active after a relaunch."
        }

        if permissionsController.allRequiredPermissionsGranted {
            return "Both macOS permissions are active in this launch."
        }

        return "Finish the two access checks and the main capture flow will be ready."
    }

    private var readinessDetail: String {
        if permissionsController.shouldSuggestRelaunch {
            return "Use Quit and reopen below. On the next launch Speechara will enter the main workspace with capture ready."
        }

        if permissionsController.allRequiredPermissionsGranted {
            return "You can continue straight into the app and start a listening session without additional permission prompts."
        }

        return "Speechara asks only for the permissions that directly power the current product: microphone input and screen plus system audio capture."
    }

    private var readinessTint: Color {
        if permissionsController.shouldSuggestRelaunch {
            return Color(red: 0.19, green: 0.45, blue: 0.95)
        }

        if permissionsController.allRequiredPermissionsGranted {
            return Color(red: 0.10, green: 0.62, blue: 0.45)
        }

        return Color(red: 0.89, green: 0.57, blue: 0.20)
    }

    private var readinessIcon: String {
        if permissionsController.shouldSuggestRelaunch {
            return "arrow.clockwise.circle.fill"
        }

        if permissionsController.allRequiredPermissionsGranted {
            return "checkmark.seal.fill"
        }

        return "slider.horizontal.3"
    }

    private var microphoneStatusTitle: String {
        switch permissionsController.microphoneState {
        case .notDetermined:
            return "Not requested"
        case .denied:
            return "Needs attention"
        case .granted:
            return "Granted"
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
            return "Allow access"
        case .denied:
            return "Open settings"
        case .granted:
            return "Allowed"
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
            return "Speechara will ask macOS for microphone access the first time."
        case .denied:
            return "If you previously denied access, turn it back on in System Settings and return here."
        case .granted:
            return "Microphone input is active for this launch."
        }
    }

    private var screenStatusTitle: String {
        switch permissionsController.screenCaptureState {
        case .needsApproval:
            return "Not approved"
        case .restartRequired:
            return "Restart needed"
        case .granted:
            return "Granted"
        }
    }

    private var screenStatusTint: Color {
        switch permissionsController.screenCaptureState {
        case .needsApproval:
            return Color(red: 0.89, green: 0.57, blue: 0.20)
        case .restartRequired:
            return Color(red: 0.19, green: 0.45, blue: 0.95)
        case .granted:
            return Color(red: 0.10, green: 0.62, blue: 0.45)
        }
    }

    private var screenActionTitle: String {
        switch permissionsController.screenCaptureState {
        case .needsApproval:
            return "Allow access"
        case .restartRequired:
            return "Approved"
        case .granted:
            return "Allowed"
        }
    }

    private var screenActionIcon: String {
        switch permissionsController.screenCaptureState {
        case .needsApproval:
            return "rectangle.badge.plus"
        case .restartRequired:
            return "arrow.clockwise"
        case .granted:
            return "checkmark"
        }
    }

    private var screenHelpText: String {
        switch permissionsController.screenCaptureState {
        case .needsApproval:
            return "macOS may show a one-time prompt and ask you to reopen Speechara after approval."
        case .restartRequired:
            return "The permission is approved. One relaunch remains before system audio capture becomes active."
        case .granted:
            return "Screen and system audio capture are ready in this launch."
        }
    }

    private var primaryActionTitle: String {
        if permissionsController.shouldSuggestRelaunch {
            return "Quit and reopen"
        }

        if permissionsController.allRequiredPermissionsGranted {
            return "Open Speechara"
        }

        return "Grant access to continue"
    }

    private var primaryActionIcon: String {
        if permissionsController.shouldSuggestRelaunch {
            return "arrow.clockwise"
        }

        if permissionsController.allRequiredPermissionsGranted {
            return "play.fill"
        }

        return "lock.open.trianglebadge.exclamationmark"
    }

    private var primaryActionTint: Color {
        if permissionsController.shouldSuggestRelaunch {
            return Color(red: 0.19, green: 0.45, blue: 0.95)
        }

        if permissionsController.allRequiredPermissionsGranted {
            return Color(red: 0.10, green: 0.62, blue: 0.45)
        }

        return Color(red: 0.74, green: 0.76, blue: 0.80)
    }

    private var primaryActionEnabled: Bool {
        permissionsController.shouldSuggestRelaunch || permissionsController.allRequiredPermissionsGranted
    }

    private func handlePrimaryAction() {
        if permissionsController.shouldSuggestRelaunch {
            if permissionsController.microphoneState.isGranted {
                onContinue()
            }

            permissionsController.quitAndReopenApplication()
            return
        }

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
                        Text(title)
                            .font(.title3.weight(.bold))

                        SetupStatusBadge(
                            title: statusTitle,
                            iconName: statusIconName,
                            tint: statusTint
                        )
                    }

                    Text(subtitle)
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

                        Text(actionTitle)
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

                Text(helpText)
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
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Text(subtitle)
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
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Text(subtitle)
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

            Text(title)
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

            Text(text)
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

                Text(title)
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
