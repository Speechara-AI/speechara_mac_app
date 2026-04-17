import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

@MainActor
final class AppPermissionsController: ObservableObject {
    enum MicrophoneState: Equatable {
        case notDetermined
        case denied
        case granted

        var isGranted: Bool {
            self == .granted
        }
    }

    enum ScreenCaptureState: Equatable {
        case needsApproval
        case restartRequired
        case granted

        var isApproved: Bool {
            switch self {
            case .needsApproval:
                return false
            case .restartRequired, .granted:
                return true
            }
        }

        var isReadyForUse: Bool {
            self == .granted
        }
    }

    @Published private(set) var microphoneState: MicrophoneState = .notDetermined
    @Published private(set) var screenCaptureState: ScreenCaptureState = .needsApproval
    @Published private(set) var isRequestingMicrophoneAccess = false
    @Published private(set) var isRequestingScreenCaptureAccess = false

    private let hadScreenCaptureAccessAtLaunch: Bool

    init() {
        hadScreenCaptureAccessAtLaunch = Self.hasScreenCaptureAccess()
        refreshStatuses()
    }

    var allRequiredPermissionsGranted: Bool {
        microphoneState.isGranted && screenCaptureState.isReadyForUse
    }

    var shouldSuggestRelaunch: Bool {
        screenCaptureState == .restartRequired
    }

    var completionProgress: Double {
        let microphoneProgress = microphoneState.isGranted ? 1.0 : 0.0
        let screenProgress: Double

        switch screenCaptureState {
        case .needsApproval:
            screenProgress = 0.0
        case .restartRequired:
            screenProgress = 0.7
        case .granted:
            screenProgress = 1.0
        }

        return (microphoneProgress + screenProgress) / 2.0
    }

    func refreshStatuses() {
        microphoneState = Self.currentMicrophoneState()

        if Self.hasScreenCaptureAccess() {
            screenCaptureState = hadScreenCaptureAccessAtLaunch ? .granted : .restartRequired
        } else {
            screenCaptureState = .needsApproval
        }
    }

    func requestMicrophoneAccess() async {
        guard !isRequestingMicrophoneAccess else {
            return
        }

        isRequestingMicrophoneAccess = true
        defer {
            isRequestingMicrophoneAccess = false
            refreshStatuses()
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            openSystemSettings()
        @unknown default:
            break
        }
    }

    func requestScreenCaptureAccess() {
        guard !isRequestingScreenCaptureAccess else {
            return
        }

        isRequestingScreenCaptureAccess = true
        defer {
            isRequestingScreenCaptureAccess = false
            refreshStatuses()
        }

        guard !Self.hasScreenCaptureAccess() else {
            return
        }

        if !CGRequestScreenCaptureAccess() {
            openSystemSettings()
        }
    }

    func openSystemSettings() {
        let settingsURL = URL(fileURLWithPath: "/System/Applications/System Settings.app", isDirectory: true)
        _ = NSWorkspace.shared.open(settingsURL)
    }

    func quitAndReopenApplication() {
        let applicationURL = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", applicationURL.path]

        do {
            try process.run()
        } catch {
            NSApp.terminate(nil)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }

    private static func currentMicrophoneState() -> MicrophoneState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private static func hasScreenCaptureAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}
