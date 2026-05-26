import AppKit
@preconcurrency import AVFoundation
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

    @Published private(set) var microphoneState: MicrophoneState = .notDetermined
    @Published private(set) var isRequestingMicrophoneAccess = false

    init() {
        refreshStatuses()
    }

    var allRequiredPermissionsGranted: Bool {
        true
    }

    var completionProgress: Double {
        microphoneState.isGranted ? 1.0 : 0.75
    }

    func refreshStatuses() {
        microphoneState = Self.currentMicrophoneState()
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

    func openSystemSettings() {
        let settingsURL = URL(fileURLWithPath: "/System/Applications/System Settings.app", isDirectory: true)
        _ = NSWorkspace.shared.open(settingsURL)
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
}
