import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject private var authStore: AuthSessionStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 30) {
                    Spacer(minLength: 24)

                    VStack(spacing: 10) {
                        Text("Sign In")
                            .font(.system(size: 44, weight: .semibold, design: .serif))

                        Text("Connect your Google account to unlock the full Speechara desktop workflow.")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        Button {
                            authStore.clearError()
                            authStore.signInWithGoogle()
                        } label: {
                            HStack(spacing: 14) {
                                GoogleMark()

                                Text(authStore.isAuthenticating ? "Waiting for Google…" : "Continue with Google")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .frame(height: 54)
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

                        if let errorMessage = authStore.errorMessage {
                            AuthMessageStrip(
                                tint: Color(red: 0.78, green: 0.22, blue: 0.26),
                                text: errorMessage
                            )
                        }

                        if authStore.isAuthenticating {
                            VStack(alignment: .leading, spacing: 10) {
                                AuthMessageStrip(
                                    tint: Color(red: 0.19, green: 0.45, blue: 0.95),
                                    text: "Speechara opened your default browser. Finish Google sign-in there and the app will activate again automatically."
                                )

                                Button("Cancel sign-in") {
                                    authStore.cancelGoogleSignIn()
                                }
                                .buttonStyle(.link)
                            }
                        }

                        HStack(spacing: 8) {
                            Text("By continuing, you allow Speechara to create a desktop session for your account.")
                                .foregroundStyle(.secondary)

                            Button("Auth settings") {
                                openWindow(id: "speechara-settings")
                            }
                            .buttonStyle(.link)
                        }
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 30)
                    .frame(width: min(max(geometry.size.width * 0.56, 420), 560))
                    .background(
                        RoundedRectangle(cornerRadius: 30)
                            .fill(cardFillColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(cardBorderColor, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.26 : 0.08), radius: 28, x: 0, y: 18)

                    Spacer(minLength: 24)
                }
                .padding(32)
            }
        }
        .frame(minWidth: 880, minHeight: 620)
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

                Text("Restoring your session…")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
            }
        }
        .frame(minWidth: 880, minHeight: 620)
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

            Text(text)
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
