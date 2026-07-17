import AppKit
import SwiftUI

private enum EmailAuthFlow: Equatable {
    case signIn
    case register
    case verifyRegistration(EmailChallenge)
    case completeRegistration(EmailVerification)
    case registrationTotp(EmailVerification, TotpSetup)
    case loginMfa(MfaChallenge)

    var title: String {
        switch self {
        case .signIn:
            return "Email sign in"
        case .register:
            return "Create account"
        case .verifyRegistration:
            return "Verify your email"
        case .completeRegistration:
            return "Set your password"
        case .registrationTotp:
            return "Set up authenticator"
        case .loginMfa:
            return "Authenticator code"
        }
    }
}

struct AuthenticationView: View {
    @EnvironmentObject private var authStore: AuthSessionStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    @State private var emailFlow: EmailAuthFlow = .signIn
    @State private var email = ""
    @State private var name = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var emailCode = ""
    @State private var mfaCode = ""
    @State private var wantsTotpDuringRegistration = false
    @State private var localErrorMessage: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer(minLength: 18)

                    header

                    VStack(alignment: .leading, spacing: 18) {
                        socialButtons
                        dividerRow
                        emailContent
                        messageArea
                        footer
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 26)
                    .frame(width: min(max(geometry.size.width * 0.58, 460), 600))
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(cardFillColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(cardBorderColor, lineWidth: 1)
                    )
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.26 : 0.08),
                        radius: 24,
                        x: 0,
                        y: 16
                    )

                    Spacer(minLength: 18)
                }
                .padding(32)
            }
        }
        .frame(minWidth: 880, minHeight: 700)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(SL("Sign In"))
                .font(.system(size: 44, weight: .semibold, design: .serif))

            Text(SL("Use Google, Microsoft, Apple, or a Speechara email/password account."))
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
        }
    }

    private var socialButtons: some View {
        VStack(spacing: 12) {
            providerButton(
                title: authStore.activeAuthenticationProvider == .google ? "Waiting for Google..." : "Continue with Google",
                mark: AnyView(GoogleMark())
            ) {
                clearMessages()
                authStore.signInWithGoogle()
            }

            providerButton(
                title: authStore.activeAuthenticationProvider == .microsoft ? "Waiting for Microsoft..." : "Continue with Microsoft",
                mark: AnyView(MicrosoftMark())
            ) {
                clearMessages()
                authStore.signInWithMicrosoft()
            }

            providerButton(
                title: authStore.activeAuthenticationProvider == .apple ? "Waiting for Apple..." : "Continue with Apple",
                mark: AnyView(AppleMark())
            ) {
                clearMessages()
                authStore.signInWithApple()
            }
        }
    }

    private var dividerRow: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(cardBorderColor)
                .frame(height: 1)

            Text("or")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Rectangle()
                .fill(cardBorderColor)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var emailContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(emailFlow.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Spacer()

                if showsEmailModeSwitch {
                    Button(emailFlow == .signIn ? "Create account" : "Have an account?") {
                        switchEmailMode()
                    }
                    .buttonStyle(.link)
                    .disabled(authStore.isAuthenticating)
                }
            }

            switch emailFlow {
            case .signIn:
                signInForm
            case .register:
                registrationStartForm
            case .verifyRegistration(let challenge):
                registrationVerifyForm(challenge)
            case .completeRegistration(let verification):
                registrationCompleteForm(verification)
            case .registrationTotp(let verification, let setup):
                registrationTotpForm(verification: verification, setup: setup)
            case .loginMfa(let challenge):
                loginMfaForm(challenge)
            }
        }
    }

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            AuthField(title: "Email") {
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .authInputStyle()
            }

            AuthField(title: "Password") {
                AuthPasswordInput("Password", text: $password)
            }

            Button {
                loginWithEmail()
            } label: {
                AuthButtonLabel(title: "Sign in with email", systemImage: "envelope")
            }
            .buttonStyle(.plain)
            .disabled(authStore.isAuthenticating)
        }
    }

    private var registrationStartForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            AuthField(title: "Name") {
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .authInputStyle()
            }

            AuthField(title: "Email") {
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .authInputStyle()
            }

            Button {
                startRegistration()
            } label: {
                AuthButtonLabel(title: "Send verification code", systemImage: "paperplane")
            }
            .buttonStyle(.plain)
            .disabled(authStore.isAuthenticating)
        }
    }

    private func registrationVerifyForm(_ challenge: EmailChallenge) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AuthMessageStrip(
                tint: Color(red: 0.15, green: 0.56, blue: 0.38),
                text: "We sent a code to \(challenge.maskedEmail)."
            )

            AuthField(title: "Verification code") {
                TextField("123456", text: $emailCode)
                    .textFieldStyle(.roundedBorder)
                    .authInputStyle(design: .monospaced)
            }

            HStack(spacing: 10) {
                Button {
                    verifyRegistrationCode(challenge)
                } label: {
                    AuthButtonLabel(title: "Verify code", systemImage: "checkmark")
                }
                .buttonStyle(.plain)
                .disabled(authStore.isAuthenticating)

                Button(SL("Resend")) {
                    resendRegistrationCode(challenge)
                }
                .buttonStyle(.link)
                .disabled(authStore.isAuthenticating)
            }
        }
    }

    private func registrationCompleteForm(_ verification: EmailVerification) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AuthField(title: "Password") {
                AuthPasswordInput("StrongPass1!", text: $password)
            }

            AuthField(title: "Confirm password") {
                AuthPasswordInput("Repeat password", text: $confirmPassword)
            }

            Toggle("Set up 2FA before finishing", isOn: $wantsTotpDuringRegistration)
                .toggleStyle(.checkbox)

            Button {
                continueRegistration(verification)
            } label: {
                AuthButtonLabel(
                    title: wantsTotpDuringRegistration ? "Continue to 2FA" : "Create account",
                    systemImage: wantsTotpDuringRegistration ? "lock.shield" : "person.badge.plus"
                )
            }
            .buttonStyle(.plain)
            .disabled(authStore.isAuthenticating)
        }
    }

    private func registrationTotpForm(verification: EmailVerification, setup: TotpSetup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                TotpQRCodeView(dataURL: setup.qrCodeDataUrl)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Scan the QR code in your authenticator app, or enter this secret manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(setup.secret)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(buttonFillColor)
                        )
                }
            }

            AuthField(title: "Authenticator code") {
                TextField("123456", text: $mfaCode)
                    .textFieldStyle(.roundedBorder)
                    .authInputStyle(design: .monospaced)
            }

            Button {
                completeRegistration(verification: verification, setup: setup)
            } label: {
                AuthButtonLabel(title: "Finish registration", systemImage: "checkmark.shield")
            }
            .buttonStyle(.plain)
            .disabled(authStore.isAuthenticating)
        }
    }

    private func loginMfaForm(_ challenge: MfaChallenge) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AuthMessageStrip(
                tint: Color(red: 0.17, green: 0.43, blue: 0.88),
                text: "Enter the authenticator code for \(challenge.maskedEmail)."
            )

            AuthField(title: "Authenticator code") {
                TextField("123456", text: $mfaCode)
                    .textFieldStyle(.roundedBorder)
                    .authInputStyle(design: .monospaced)
            }

            HStack(spacing: 10) {
                Button {
                    verifyLoginMfa(challenge)
                } label: {
                    AuthButtonLabel(title: "Verify and sign in", systemImage: "checkmark.shield")
                }
                .buttonStyle(.plain)
                .disabled(authStore.isAuthenticating)

                Button(SL("Back")) {
                    emailFlow = .signIn
                    mfaCode = ""
                    clearMessages()
                }
                .buttonStyle(.link)
                .disabled(authStore.isAuthenticating)
            }
        }
    }

    @ViewBuilder
    private var messageArea: some View {
        if let errorMessage = localErrorMessage ?? authStore.errorMessage {
            AuthMessageStrip(
                tint: Color(red: 0.78, green: 0.22, blue: 0.26),
                text: errorMessage
            )
        }

        if authStore.isAuthenticating, let provider = authStore.activeAuthenticationProvider {
            VStack(alignment: .leading, spacing: 10) {
                AuthMessageStrip(
                    tint: Color(red: 0.19, green: 0.45, blue: 0.95),
                    text: authenticatingMessage(for: provider)
                )

                if provider != .email {
                    Button(SL("Cancel sign-in")) {
                        authStore.cancelAuthentication()
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(SL("By continuing, you allow Speechara to create a desktop session for your account."))
                .foregroundStyle(.secondary)

            Button(SL("Auth settings")) {
                openWindow(id: "speechara-settings")
            }
            .buttonStyle(.link)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var showsEmailModeSwitch: Bool {
        emailFlow == .signIn || emailFlow == .register
    }

    private func providerButton(title: String, mark: AnyView, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                mark

                Text(SL(title))
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 52)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(buttonFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(buttonBorderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(authStore.isAuthenticating)
    }

    private func switchEmailMode() {
        clearMessages()
        emailCode = ""
        mfaCode = ""
        password = ""
        confirmPassword = ""
        wantsTotpDuringRegistration = false
        emailFlow = emailFlow == .signIn ? .register : .signIn
    }

    private func loginWithEmail() {
        guard validateEmail(normalizedEmail), validateRequired(password, label: "Password") else {
            return
        }

        Task { @MainActor in
            clearMessages()
            if let result = await authStore.loginWithEmail(email: normalizedEmail, password: password) {
                switch result {
                case .authenticated:
                    break
                case .mfaRequired(let challenge):
                    mfaCode = ""
                    emailFlow = .loginMfa(challenge)
                }
            }
        }
    }

    private func startRegistration() {
        guard validateEmail(normalizedEmail),
              validateRequired(name, label: "Name") else {
            return
        }

        Task { @MainActor in
            clearMessages()
            if let challenge = await authStore.startEmailRegistration(
                email: normalizedEmail,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines)
            ) {
                email = challenge.email
                emailCode = ""
                emailFlow = .verifyRegistration(challenge)
            }
        }
    }

    private func verifyRegistrationCode(_ challenge: EmailChallenge) {
        guard validateRequired(emailCode, label: "Verification code") else {
            return
        }

        Task { @MainActor in
            clearMessages()
            if let verification = await authStore.verifyEmailCode(
                challengeId: challenge.challengeId,
                email: challenge.email,
                code: emailCode.trimmed
            ) {
                password = ""
                confirmPassword = ""
                wantsTotpDuringRegistration = false
                emailFlow = .completeRegistration(verification)
            }
        }
    }

    private func resendRegistrationCode(_ challenge: EmailChallenge) {
        Task { @MainActor in
            clearMessages()
            if let refreshedChallenge = await authStore.resendEmailCode(
                challengeId: challenge.challengeId,
                email: challenge.email
            ) {
                emailFlow = .verifyRegistration(refreshedChallenge)
            }
        }
    }

    private func continueRegistration(_ verification: EmailVerification) {
        guard validatePasswordForRegistration() else {
            return
        }

        if wantsTotpDuringRegistration {
            Task { @MainActor in
                clearMessages()
                if let setup = await authStore.setupRegistrationTotp(
                    challengeId: verification.challengeId,
                    email: verification.email,
                    verificationToken: verification.verificationToken
                ) {
                    mfaCode = ""
                    emailFlow = .registrationTotp(verification, setup)
                }
            }
        } else {
            completeRegistration(verification: verification, setup: nil)
        }
    }

    private func completeRegistration(verification: EmailVerification, setup: TotpSetup?) {
        guard validatePasswordForRegistration() else {
            return
        }

        if setup != nil, !validateRequired(mfaCode, label: "Authenticator code") {
            return
        }

        Task { @MainActor in
            clearMessages()
            let input = CompleteEmailRegistrationInput(
                challengeId: verification.challengeId,
                email: verification.email,
                name: name.trimmed,
                password: password,
                verificationToken: verification.verificationToken,
                mfa: setup.map { EmailRegistrationMFA(setupId: $0.setupId, code: mfaCode.trimmed) }
            )
            _ = await authStore.completeEmailRegistration(input: input)
        }
    }

    private func verifyLoginMfa(_ challenge: MfaChallenge) {
        guard validateRequired(mfaCode, label: "Authenticator code") else {
            return
        }

        Task { @MainActor in
            clearMessages()
            _ = await authStore.verifyEmailMfa(
                challengeId: challenge.challengeId,
                email: challenge.email,
                code: mfaCode.trimmed
            )
        }
    }

    private func validateEmail(_ value: String) -> Bool {
        guard value.contains("@"), value.contains(".") else {
            localErrorMessage = "Enter a valid email address."
            return false
        }

        return true
    }

    private func validateRequired(_ value: String, label: String) -> Bool {
        guard !value.trimmed.isEmpty else {
            localErrorMessage = "\(label) is required."
            return false
        }

        return true
    }

    private func validatePasswordForRegistration() -> Bool {
        guard validateRequired(password, label: "Password") else {
            return false
        }

        guard password == confirmPassword else {
            localErrorMessage = "Passwords do not match."
            return false
        }

        if let policyError = passwordPolicyError {
            localErrorMessage = policyError
            return false
        }

        return true
    }

    private var passwordPolicyError: String? {
        if password.count < 8 {
            return "Password must be at least 8 characters."
        }
        if password.rangeOfCharacter(from: .uppercaseLetters) == nil {
            return "Password must include an uppercase letter."
        }
        if password.rangeOfCharacter(from: .lowercaseLetters) == nil {
            return "Password must include a lowercase letter."
        }
        if password.rangeOfCharacter(from: .decimalDigits) == nil {
            return "Password must include a digit."
        }
        if password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil {
            return "Password must include a symbol."
        }

        return nil
    }

    private var normalizedEmail: String {
        email.trimmed.lowercased()
    }

    private func clearMessages() {
        localErrorMessage = nil
        authStore.clearError()
    }

    private func authenticatingMessage(for provider: AuthenticationProvider) -> String {
        switch provider {
        case .google, .microsoft:
            return "Speechara opened your default browser. Finish \(provider.displayName) sign-in there and the app will activate again automatically."
        case .apple:
            return "Complete Apple sign-in in the system prompt."
        case .email:
            return "Checking your Speechara account..."
        }
    }

    private var backgroundGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.10, blue: 0.11),
                    Color(red: 0.09, green: 0.11, blue: 0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.97, blue: 0.94),
                Color(red: 0.94, green: 0.96, blue: 1.00),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardFillColor: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.15).opacity(0.96)
            : Color.white.opacity(0.88)
    }

    private var cardBorderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
    }

    private var buttonFillColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.92)
    }

    private var buttonBorderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.12)
    }
}

struct AuthenticationLoadingView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.10, green: 0.10, blue: 0.11), Color(red: 0.09, green: 0.11, blue: 0.16)]
                    : [Color(red: 0.98, green: 0.97, blue: 0.94), Color(red: 0.94, green: 0.96, blue: 1.00)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)

                Text(SL("Restoring your session…"))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
            }
        }
        .frame(minWidth: 880, minHeight: 620)
    }
}

private struct AuthField<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            content
        }
    }
}

private struct AuthInputModifier: ViewModifier {
    let design: Font.Design

    func body(content: Content) -> some View {
        content
            .font(.system(size: 15, weight: .medium, design: design))
            .controlSize(.large)
            .frame(height: 38)
    }
}

private extension View {
    func authInputStyle(design: Font.Design = .rounded) -> some View {
        modifier(AuthInputModifier(design: design))
    }
}

private struct AuthPasswordInput: View {
    let placeholder: String
    @Binding var text: String
    @State private var isPasswordVisible = false
    @FocusState private var isFocused: Bool

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isPasswordVisible {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .focused($isFocused)

            Button {
                isPasswordVisible.toggle()
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(isPasswordVisible ? SL("Hide password") : SL("Show password"))
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isFocused ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.48),
                    lineWidth: isFocused ? 2 : 1
                )
        )
    }
}

private struct AuthButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))

            Text(title)
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.12, green: 0.33, blue: 0.86))
        )
    }
}

private struct GoogleMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 28, height: 28)
                .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)

            Text("G")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.26, green: 0.52, blue: 0.96),
                            Color(red: 0.17, green: 0.70, blue: 0.38),
                            Color(red: 0.96, green: 0.76, blue: 0.18),
                            Color(red: 0.88, green: 0.28, blue: 0.22),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

private struct MicrosoftMark: View {
    private let colors = [
        Color(red: 0.95, green: 0.29, blue: 0.20),
        Color(red: 0.48, green: 0.73, blue: 0.16),
        Color(red: 0.00, green: 0.64, blue: 0.85),
        Color(red: 1.00, green: 0.73, blue: 0.08),
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(12), spacing: 3), count: 2), spacing: 3) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Rectangle()
                    .fill(color)
                    .frame(width: 12, height: 12)
            }
        }
        .frame(width: 28, height: 28)
    }
}

private struct AppleMark: View {
    var body: some View {
        Image(systemName: "apple.logo")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 28, height: 28)
    }
}

private struct TotpQRCodeView: View {
    let dataURL: String?

    var body: some View {
        Group {
            if let image = Self.image(from: dataURL) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(8)
                    .background(Color.white)
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 138, height: 138)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.10), lineWidth: 1)
        )
    }

    private static func image(from dataURL: String?) -> NSImage? {
        guard let dataURL,
              let commaIndex = dataURL.firstIndex(of: ",") else {
            return nil
        }

        let encodedData = String(dataURL[dataURL.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: encodedData) else {
            return nil
        }

        return NSImage(data: data)
    }
}

private struct AuthMessageStrip: View {
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                )

            Text(SL(text))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
