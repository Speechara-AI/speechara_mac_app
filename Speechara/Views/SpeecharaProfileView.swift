import SwiftUI

struct SpeecharaProfileView: View {
    @EnvironmentObject private var authStore: AuthSessionStore
    @State private var isRefreshingProfile = false
    @State private var profileRefreshErrorMessage: String?
    @State private var billingSummary: SpeecharaBillingSummary?
    @State private var billingRefreshErrorMessage: String?

    private let billingService = SpeecharaBillingService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                syncStateBlock
                accountSection
                billingSection
                footerActions
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .task(id: authStore.currentUser?.id) {
            await refreshProfileScreenData()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Profile")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(SpeecharaProfileTheme.primaryText)

            Text("Manage your Speechara account, plan, and usage.")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(SpeecharaProfileTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var syncStateBlock: some View {
        if isRefreshingProfile {
            SpeecharaProfileStatusStrip(
                text: SL("Syncing account and billing…"),
                tint: Color(red: 0.17, green: 0.54, blue: 0.95)
            )
        } else if let profileRefreshErrorMessage {
            SpeecharaProfileStatusStrip(
                text: profileRefreshErrorMessage,
                tint: Color(red: 0.84, green: 0.33, blue: 0.30)
            )
        } else if let billingRefreshErrorMessage {
            SpeecharaProfileStatusStrip(
                text: SLF("Account synced, but billing is unavailable right now: %@", billingRefreshErrorMessage),
                tint: Color(red: 0.86, green: 0.62, blue: 0.20)
            )
        } else if authStore.currentUser != nil {
            SpeecharaProfileStatusStrip(
                text: SL("Account and billing data are up to date."),
                tint: Color(red: 0.15, green: 0.67, blue: 0.46)
            )
        }
    }

    private var accountSection: some View {
        SpeecharaProfileSectionCard(
            title: "Account",
            subtitle: "Your signed-in Speechara profile."
        ) {
            if let user = authStore.currentUser {
                VStack(spacing: 16) {
                    SpeecharaProfileIdentityHero(
                        displayName: user.displayName,
                        email: user.email,
                        initials: user.initials,
                        avatarURL: user.avatarURL
                    )

                    VStack(spacing: 12) {
                        SpeecharaProfileInfoRow(
                            title: "Name",
                            value: user.displayName,
                            systemImage: "person"
                        )

                        SpeecharaProfileInfoRow(
                            title: "Email",
                            value: user.email,
                            systemImage: "envelope"
                        )
                    }
                }
            } else {
                Text("No authenticated account is available in the current desktop session.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeecharaProfileTheme.secondaryText)
            }
        }
    }

    private var billingSection: some View {
        SpeecharaProfileSectionCard(
            title: "Billing",
            subtitle: "Current plan, billing period, and live transcription usage."
        ) {
            if let billingSummary {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        SpeecharaBillingStatusBadge(summary: billingSummary)

                        if billingSummary.subscription.cancelAtPeriodEnd {
                            SpeecharaProfileBadge(
                                title: "Cancels at period end",
                                tint: Color(red: 0.86, green: 0.62, blue: 0.20)
                            )
                        }
                    }

                    VStack(spacing: 12) {
                        SpeecharaProfileInfoRow(
                            title: "Current plan",
                            value: billingSummary.displayPlanName,
                            systemImage: "creditcard"
                        )

                        SpeecharaProfileInfoRow(
                            title: "Current period end",
                            value: billingSummary.currentPeriodEndText,
                            systemImage: "calendar"
                        )

                        SpeecharaProfileInfoRow(
                            title: "Subscription status",
                            value: billingSummary.statusTitle,
                            systemImage: "checkmark.seal"
                        )

                        SpeecharaProfileInfoRow(
                            title: "Transcription access",
                            value: billingSummary.transcriptionAccessTitle,
                            systemImage: "waveform.badge.mic"
                        )
                    }

                    SpeecharaBillingUsageCard(summary: billingSummary)
                }
            } else if let billingRefreshErrorMessage {
                SpeecharaProfileInlineErrorCard(
                    text: billingRefreshErrorMessage,
                    actionTitle: "Retry billing"
                ) {
                    Task {
                        await refreshProfileScreenData()
                    }
                }
            } else {
                SpeecharaProfileLoadingCard(text: "Loading billing summary…")
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: 12) {
            Button("Sign out") {
                authStore.signOut()
            }
            .buttonStyle(.bordered)
            .tint(Color.red.opacity(0.9))

            Button("Refresh profile") {
                Task {
                    await refreshProfileScreenData()
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshingProfile)
        }
    }

    @MainActor
    private func refreshProfileScreenData() async {
        guard !isRefreshingProfile else {
            return
        }

        isRefreshingProfile = true
        defer {
            isRefreshingProfile = false
        }

        let resolvedProfileResult = await loadProfileRefreshResult()
        let resolvedBillingResult = await loadBillingSummaryResult()

        switch resolvedProfileResult {
        case .success:
            profileRefreshErrorMessage = nil
        case .failure(let error):
            profileRefreshErrorMessage = error.localizedDescription
        }

        switch resolvedBillingResult {
        case .success(let summary):
            billingSummary = summary
            billingRefreshErrorMessage = nil
        case .failure(let error):
            billingRefreshErrorMessage = error.localizedDescription
        }
    }

    private func loadProfileRefreshResult() async -> Result<Void, Error> {
        do {
            try await authStore.refreshCurrentUserProfile()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func loadBillingSummaryResult() async -> Result<SpeecharaBillingSummary, Error> {
        do {
            if let accessToken = authStore.session?.accessToken {
                return .success(try await billingService.fetchSummary(accessToken: accessToken))
            }

            return .success(try await billingService.fetchSummary())
        } catch {
            return .failure(error)
        }
    }
}

private enum SpeecharaProfileTheme {
    static let primaryText = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.10, 0.16, 0.24),
        dark: SpeecharaRGBA(0.92, 0.95, 0.98)
    )
    static let secondaryText = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.34, 0.42, 0.54),
        dark: SpeecharaRGBA(0.70, 0.77, 0.86)
    )
    static let tertiaryText = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.47, 0.54, 0.64),
        dark: SpeecharaRGBA(0.56, 0.63, 0.74)
    )
    static let cardFill = Color.speecharaDynamic(
        light: SpeecharaRGBA(1.00, 1.00, 1.00, 0.86),
        dark: SpeecharaRGBA(0.11, 0.13, 0.16, 0.94)
    )
    static let subtlePanelFill = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.96, 0.97, 0.99),
        dark: SpeecharaRGBA(0.15, 0.17, 0.21)
    )
    static let cardBorder = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.84, 0.88, 0.94),
        dark: SpeecharaRGBA(0.24, 0.29, 0.36)
    )
    static let accent = Color(red: 0.17, green: 0.54, blue: 0.95)
    static let avatarSurface = Color.speecharaDynamic(
        light: SpeecharaRGBA(1.00, 1.00, 1.00),
        dark: SpeecharaRGBA(0.19, 0.22, 0.27)
    )
    static let progressTrack = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.89, 0.92, 0.96),
        dark: SpeecharaRGBA(0.24, 0.28, 0.34)
    )
}

private struct SpeecharaProfileSectionCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(SL(title))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(SpeecharaProfileTheme.primaryText)

                if let subtitle {
                    Text(SL(subtitle))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeecharaProfileTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(SpeecharaProfileTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(SpeecharaProfileTheme.cardBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 14)
    }
}

private struct SpeecharaProfileIdentityHero: View {
    let displayName: String
    let email: String
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
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(SpeecharaProfileTheme.avatarSurface)
                    .frame(width: 68, height: 68)

                if let resolvedAvatarURL {
                    AsyncImage(url: resolvedAvatarURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            fallbackAvatar
                        }
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                } else {
                    fallbackAvatar
                }
            }
            .overlay(
                Circle()
                    .stroke(SpeecharaProfileTheme.cardBorder, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(SpeecharaProfileTheme.primaryText)

                Text(email)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeecharaProfileTheme.secondaryText)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(SpeecharaProfileTheme.subtlePanelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(SpeecharaProfileTheme.cardBorder, lineWidth: 1)
        )
    }

    private var fallbackAvatar: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 60, height: 60)
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

private struct SpeecharaProfileInfoRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SpeecharaProfileTheme.accent)
                .frame(width: 18)

            Text(SL(title))
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(SpeecharaProfileTheme.secondaryText)

            Spacer(minLength: 16)

            Text(SL(value))
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(SpeecharaProfileTheme.primaryText)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(SpeecharaProfileTheme.subtlePanelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(SpeecharaProfileTheme.cardBorder, lineWidth: 1)
        )
    }
}

private struct SpeecharaProfileStatusStrip: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint.opacity(0.14))
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)
                )

            Text(SL(text))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(SpeecharaProfileTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct SpeecharaProfileBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(SL(title))
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                Capsule()
                    .fill(tint.opacity(0.10))
            )
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
    }
}

private struct SpeecharaBillingStatusBadge: View {
    let summary: SpeecharaBillingSummary

    var body: some View {
        SpeecharaProfileBadge(
            title: summary.statusTitle,
            tint: summary.statusTint
        )
    }
}

private struct SpeecharaBillingUsageCard: View {
    let summary: SpeecharaBillingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(SL("Usage this period"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(SpeecharaProfileTheme.primaryText)

                Spacer(minLength: 0)

                Text(summary.usageHeadline)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeecharaProfileTheme.primaryText)
            }

            Text(summary.usageDetailText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(SpeecharaProfileTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(SpeecharaProfileTheme.progressTrack)
                        .frame(height: 10)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.26, green: 0.82, blue: 0.97),
                                    Color(red: 0.30, green: 0.55, blue: 0.96),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(proxy.size.width * summary.usageFraction, summary.usageFraction > 0 ? 10 : 0),
                            height: 10
                        )
                }
            }
            .frame(height: 10)

            HStack(spacing: 14) {
                Text(summary.remainingMinutesText)
                Text(summary.transcriptionAccessTitle)
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(SpeecharaProfileTheme.tertiaryText)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(SpeecharaProfileTheme.subtlePanelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(SpeecharaProfileTheme.cardBorder, lineWidth: 1)
        )
    }
}

private struct SpeecharaProfileInlineErrorCard: View {
    let text: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(SpeecharaProfileTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(SL(actionTitle), action: action)
                .buttonStyle(.bordered)
                .tint(Color(red: 0.84, green: 0.33, blue: 0.30))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.red.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct SpeecharaProfileLoadingCard: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .tint(SpeecharaProfileTheme.accent)

            Text(SL(text))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(SpeecharaProfileTheme.primaryText)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(SpeecharaProfileTheme.subtlePanelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(SpeecharaProfileTheme.cardBorder, lineWidth: 1)
        )
    }
}

private extension SpeecharaBillingSummary {
    var displayPlanName: String {
        subscription.planName?.nilIfEmpty ?? SL("No active plan")
    }

    var statusTitle: String {
        switch subscription.status.lowercased() {
        case "active":
            return SL("Active")
        case "trialing":
            return SL("Trialing")
        case "past_due":
            return SL("Past due")
        case "canceled":
            return SL("Canceled")
        case "expired":
            return SL("Expired")
        case "none":
            return SL("No subscription")
        default:
            return subscription.status.capitalized
        }
    }

    var statusTint: Color {
        switch subscription.status.lowercased() {
        case "active":
            return Color(red: 0.15, green: 0.67, blue: 0.46)
        case "trialing":
            return Color(red: 0.17, green: 0.54, blue: 0.95)
        case "past_due":
            return Color(red: 0.86, green: 0.62, blue: 0.20)
        case "canceled", "expired":
            return Color(red: 0.84, green: 0.33, blue: 0.30)
        default:
            return SpeecharaProfileTheme.tertiaryText
        }
    }

    var currentPeriodEndText: String {
        subscription.currentPeriodEnd?.profileDisplayDate ?? "—"
    }

    var transcriptionAccessTitle: String {
        usage.canUseTranscription ? SL("Live transcription available") : SL("Live transcription unavailable")
    }

    var usageHeadline: String {
        SLF("%@ min / %@ min", String(usage.usedMinutes), String(usage.includedMinutes))
    }

    var remainingMinutesText: String {
        SLF("%@ min remaining", String(usage.remainingMinutes))
    }

    var usageDetailText: String {
        if usage.includedMinutes <= 0 {
            return usage.canUseTranscription
                ? SL("No included minutes are reported yet.")
                : SL("No included minutes are available for this workspace.")
        }

        if usage.isLimitReached || !usage.canUseTranscription {
            return SLF(
                "Used %@ min out of %@ min. The billing limit has been reached.",
                String(usage.usedMinutes),
                String(usage.includedMinutes)
            )
        }

        return SLF(
            "Used %@ min out of %@ min. %@ min remain in the current billing period.",
            String(usage.usedMinutes),
            String(usage.includedMinutes),
            String(usage.remainingMinutes)
        )
    }

    var usageFraction: Double {
        guard usage.includedMinutes > 0 else {
            return 0
        }

        return min(max(Double(usage.usedMinutes) / Double(usage.includedMinutes), 0), 1)
    }
}

private extension Date {
    var profileDisplayDate: String {
        let formatter = DateFormatter()
        formatter.locale = SpeecharaLocalizationStore.shared.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
