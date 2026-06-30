import AppKit
import CoreAudio
import CoreGraphics
import OSLog
import SwiftUI

private extension Notification.Name {
    static let speecharaOpenMainWindow = Notification.Name("speechara.openMainWindow")
}

@main
struct SpeecharaApp: App {
    @NSApplicationDelegateAdaptor(SpeecharaAppDelegate.self) private var appDelegate
    @StateObject private var authStore = AuthSessionStore()
    @StateObject private var subtitleViewModel: SubtitleViewModel
    @StateObject private var localizationStore = SpeecharaLocalizationStore.shared
    @StateObject private var meetingDetectionStore: MeetingDetectionStore
    @AppStorage("speechara.appearanceMode") private var appearanceModeRawValue = SpeecharaAppearanceMode.system.rawValue

    private var appearanceMode: SpeecharaAppearanceMode {
        SpeecharaAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    init() {
#if !APP_STORE
        SpeecharaUpdateController.shared.activate()
#endif
        SpeecharaLocalizationStore.shared.installBundleOverrideIfNeeded()
        let viewModel = SubtitleViewModel()
        _subtitleViewModel = StateObject(wrappedValue: viewModel)
        _meetingDetectionStore = StateObject(wrappedValue: MeetingDetectionStore(viewModel: viewModel))
    }

    var body: some Scene {
        Window("Speechara", id: "speechara-main") {
            ZStack {
                SpeecharaRootView()
                SpeecharaBackgroundCoordinatorView()
                    .frame(width: 0, height: 0)
            }
                .environmentObject(authStore)
                .environmentObject(subtitleViewModel)
                .environmentObject(localizationStore)
                .environmentObject(meetingDetectionStore)
                .environment(\.locale, localizationStore.locale)
                .preferredColorScheme(appearanceMode.preferredColorScheme)
                .id(localizationStore.language.rawValue)
        }
        .commands {
            SpeecharaFileCommands()
        }

        Window(SL("Settings"), id: "speechara-settings") {
            SpeecharaSettingsView()
                .environmentObject(authStore)
                .environmentObject(subtitleViewModel)
                .environmentObject(localizationStore)
                .environmentObject(meetingDetectionStore)
                .environment(\.locale, localizationStore.locale)
                .preferredColorScheme(appearanceMode.preferredColorScheme)
                .id(localizationStore.language.rawValue)
        }

        Window(SL("Listening"), id: "speechara-listening-mini") {
            SpeecharaListeningMiniView()
                .environmentObject(subtitleViewModel)
                .environmentObject(localizationStore)
                .environmentObject(meetingDetectionStore)
                .environment(\.locale, localizationStore.locale)
                .preferredColorScheme(appearanceMode.preferredColorScheme)
                .id(localizationStore.language.rawValue)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            SpeecharaMenuBarMenu()
                .environmentObject(authStore)
                .environmentObject(subtitleViewModel)
                .environmentObject(localizationStore)
                .environmentObject(meetingDetectionStore)
                .environment(\.locale, localizationStore.locale)
                .id(localizationStore.language.rawValue)
        } label: {
            SpeecharaMenuBarLabel(
                isActive: subtitleViewModel.hasActiveSession,
                viewModel: subtitleViewModel,
                meetingDetectionStore: meetingDetectionStore
            )
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct SpeecharaBackgroundCoordinatorView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var viewModel: SubtitleViewModel
    @EnvironmentObject private var meetingDetectionStore: MeetingDetectionStore

    var body: some View {
        Color.clear
            .onAppear {
                meetingDetectionStore.configure(
                    viewModel: viewModel,
                    startListening: {
                        startListeningAfterAuthRefresh()
                    }
                )
            }
    }

    private func startListeningAfterAuthRefresh() {
        Task { @MainActor in
            do {
                try await authStore.ensureActiveSession()
                viewModel.startListening(mode: .newSession, includeMicrophone: viewModel.startsWithMicrophoneEnabled)
                openWindow(id: "speechara-listening-mini")
                NSApp.activate(ignoringOtherApps: true)
            } catch {
                viewModel.showErrorMessage(authStore.errorMessage ?? error.localizedDescription)
                openWindow(id: "speechara-main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

final class SpeecharaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.async {
            NSApp.windows
                .filter { $0.title == "Speechara" }
                .forEach { $0.close() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: .speecharaOpenMainWindow, object: nil)
        }

        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let handledAuthCallback = urls.contains { AuthService.shared.handleIncomingURL($0) }

        guard handledAuthCallback else {
            return
        }

        NotificationCenter.default.post(name: .speecharaOpenMainWindow, object: nil)
        application.activate(ignoringOtherApps: true)
    }
}

private struct SpeecharaMenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var authStore: AuthSessionStore
    let isActive: Bool
    @ObservedObject var viewModel: SubtitleViewModel
    let meetingDetectionStore: MeetingDetectionStore

    var body: some View {
        SpeecharaMenuBarIcon(isActive: isActive)
            .onAppear {
                meetingDetectionStore.configure(
                    viewModel: viewModel,
                    startListening: {
                        startListeningAfterAuthRefresh()
                    }
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .speecharaOpenMainWindow)) { _ in
                openWindow(id: "speechara-main")
                NSApp.activate(ignoringOtherApps: true)
            }
    }

    private func startListeningAfterAuthRefresh() {
        Task { @MainActor in
            do {
                try await authStore.ensureActiveSession()
                viewModel.startListening(mode: .newSession, includeMicrophone: viewModel.startsWithMicrophoneEnabled)
                openWindow(id: "speechara-listening-mini")
                NSApp.activate(ignoringOtherApps: true)
            } catch {
                viewModel.showErrorMessage(authStore.errorMessage ?? error.localizedDescription)
                openWindow(id: "speechara-main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

private struct SpeecharaMenuBarIcon: View {
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image("SpeecharaMenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .opacity(isActive ? 1 : 0.82)

            if isActive {
                Circle()
                    .fill(Color(red: 0.92, green: 0.05, blue: 0.08))
                    .frame(width: 7, height: 7)
            }

            if isActive {
                Text(SL("Listening"))
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .accessibilityLabel(isActive ? SL("Listening") : "Speechara")
    }
}

private struct SpeecharaListeningMiniView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var viewModel: SubtitleViewModel

    private var statusTitle: String {
        if viewModel.isBusy {
            return SL("Preparing session")
        }

        if viewModel.hasActiveSession {
            return SL("Listening")
        }

        if viewModel.status == .stopped {
            return SL("Listening stopped")
        }

        return SL("Ready to listen")
    }

    private var previewText: String {
        let livePreview = viewModel.liveSubtitlePreview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !livePreview.isEmpty {
            return livePreview
        }

        let transcript = viewModel.subtitlesText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            return transcript
        }

        return SL("Waiting for speech...")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Image("SpeecharaMenuBarIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)

                    if viewModel.hasActiveSession {
                        Circle()
                            .fill(Color(red: 0.92, green: 0.05, blue: 0.08))
                            .frame(width: 10, height: 10)
                            .offset(x: 2, y: -1)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))

                    Text(viewModel.selectedMicrophoneName)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    viewModel.stopActiveSession()
                } label: {
                    Label(SL("Stop Listening"), systemImage: "stop.fill")
                }
                .disabled(!viewModel.hasActiveSession || viewModel.isBusy || viewModel.isMicrophoneBusy)
            }

            Text(previewText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )

            HStack(spacing: 10) {
                Button(SL("Open Speechara")) {
                    openWindow(id: "speechara-main")
                    NSApp.activate(ignoringOtherApps: true)
                }

                Spacer()

                Menu(SL("Select microphone")) {
                    if viewModel.hasAvailableMicrophones {
                        ForEach(viewModel.availableMicrophones) { device in
                            Button {
                                viewModel.selectMicrophone(device.id)
                            } label: {
                                Label(
                                    device.name,
                                    systemImage: device.id == viewModel.selectedMicrophoneID ? "checkmark" : "mic"
                                )
                            }
                            .disabled(device.id == viewModel.selectedMicrophoneID)
                        }
                    } else {
                        Button(SL("No microphone devices available")) {}
                            .disabled(true)
                    }
                }
                .disabled(viewModel.isBusy || viewModel.isMicrophoneBusy)
            }
        }
        .padding(18)
        .frame(minWidth: 360, idealWidth: 520, maxWidth: .infinity, minHeight: 176, idealHeight: 220, maxHeight: .infinity)
        .background(SpeecharaFloatingMiniWindowConfigurator())
    }
}

private struct SpeecharaFloatingMiniWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(for: nsView)
    }

    private func configureWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }

            window.level = .floating
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.hidesOnDeactivate = false
            window.isMovableByWindowBackground = true
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.resizable)
            window.minSize = NSSize(width: 360, height: 176)
            window.maxSize = NSSize(width: 720, height: 420)
        }
    }
}

private struct SpeecharaMenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var viewModel: SubtitleViewModel
    @AppStorage("speechara.permissions.onboarding.version") private var permissionsOnboardingVersion = 0

    private var canControlListening: Bool {
        authStore.isAuthenticated
            && !authStore.isRestoringSession
            && permissionsOnboardingVersion >= speecharaPermissionsOnboardingVersion
    }

    private var isControlBusy: Bool {
        viewModel.isBusy || viewModel.isMicrophoneBusy
    }

    private var primaryActionTitle: String {
        viewModel.hasActiveSession ? SL("Stop Listening") : SL("Start Listening")
    }

    private var statusTitle: String {
        if authStore.isRestoringSession {
            return SL("Preparing session")
        }

        if !authStore.isAuthenticated || permissionsOnboardingVersion < speecharaPermissionsOnboardingVersion {
            return SL("Grant access to continue")
        }

        if viewModel.hasActiveSession {
            return SL("Listening")
        }

        if viewModel.status == .stopped {
            return SL("Listening stopped")
        }

        return SL("Ready to listen")
    }

    var body: some View {
        Button(primaryActionTitle) {
            toggleListening()
        }
        .disabled(!canControlListening || isControlBusy)

        Button(SL("Open Speechara")) {
            openSpeecharaWindow()
        }

        Divider()

        Button(statusTitle) {}
            .disabled(true)

        Menu(SL("Select microphone")) {
            microphoneMenuItems
        }
        .disabled(!canControlListening || isControlBusy)

        Button(SL("Settings...")) {
            openSettingsWindow()
        }

#if !APP_STORE
        Button(SL("Check for Updates...")) {
            SpeecharaUpdateController.shared.checkForUpdates()
        }

        Divider()
#endif

        Button(SL("Quit Speechara completely")) {
            NSApp.terminate(nil)
        }
    }

    @ViewBuilder
    private var microphoneMenuItems: some View {
        Button(SL("Refresh microphones")) {
            viewModel.refreshAvailableMicrophones()
        }

        Divider()

        if viewModel.hasAvailableMicrophones {
            ForEach(viewModel.availableMicrophones) { device in
                Button {
                    viewModel.selectMicrophone(device.id)
                } label: {
                    Label(
                        device.name,
                        systemImage: device.id == viewModel.selectedMicrophoneID ? "checkmark" : "mic"
                    )
                }
                .disabled(device.id == viewModel.selectedMicrophoneID)
            }
        } else {
            Button(SL("No microphone devices available")) {}
                .disabled(true)
        }
    }

    private func toggleListening() {
        if viewModel.hasActiveSession {
            viewModel.stopActiveSession()
            return
        }

        startListeningAfterAuthRefresh()
    }

    private func startListeningAfterAuthRefresh() {
        Task { @MainActor in
            do {
                try await authStore.ensureActiveSession()
                viewModel.promptAndStartListening(includeMicrophone: viewModel.startsWithMicrophoneEnabled)
                openListeningWindow()
            } catch {
                viewModel.showErrorMessage(authStore.errorMessage ?? error.localizedDescription)
                openSpeecharaWindow()
            }
        }
    }

    private func openSpeecharaWindow() {
        openWindow(id: "speechara-main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettingsWindow() {
        openWindow(id: "speechara-settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openListeningWindow() {
        openWindow(id: "speechara-listening-mini")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SpeecharaFileCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("speechara.uiLanguage") private var selectedLanguageRawValue = SpeecharaLocalizationStore.shared.language.rawValue

    var body: some Commands {
#if !APP_STORE
        CommandGroup(after: .appInfo) {
            Button(SL("Check for Updates...")) {
                SpeecharaUpdateController.shared.checkForUpdates()
            }
        }
#endif

        CommandGroup(after: .newItem) {
            Divider()

            Button(SL("Settings...")) {
                openWindow(id: "speechara-settings")
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button(SL("Settings...")) {
                openWindow(id: "speechara-settings")
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}

enum SpeecharaAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return SL("System")
        case .light:
            return SL("Light")
        case .dark:
            return SL("Dark")
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

private enum MeetingApp: String {
    case zoom
    case webex

    var displayName: String {
        switch self {
        case .zoom:
            return "Zoom"
        case .webex:
            return "Cisco Webex"
        }
    }

    static func match(bundleIdentifier: String?, appName: String?) -> MeetingApp? {
        let bundle = bundleIdentifier?.lowercased() ?? ""
        let name = appName?.lowercased() ?? ""

        if bundle.contains("zoom") || name.contains("zoom") {
            return .zoom
        }

        if bundle.contains("webex")
            || bundle.contains("cisco")
            || name.contains("webex")
            || name.contains("cisco webex") {
            return .webex
        }

        return nil
    }

    static func match(windowTitle: String?, ownerName: String) -> MeetingApp? {
        let text = "\(windowTitle ?? "") \(ownerName)".lowercased()

        if text.contains("zoom") {
            return .zoom
        }

        if text.contains("webex") || text.contains("cisco webex") {
            return .webex
        }

        return nil
    }

    func hasMeetingSignal(windowTitle: String?, ownerName: String) -> Bool {
        let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let owner = ownerName.lowercased()

        guard !Self.isKnownNonMeetingTitle(title) else {
            return false
        }

        switch self {
        case .zoom:
            return title.contains("zoom meeting")
                || title.contains("zoom webinar")
                || title.contains("webinar")
                || title.contains("waiting room")
                || title.contains("meeting id")
                || (owner.contains("zoom") && Self.containsStandaloneMeeting(in: title))
        case .webex:
            return title.contains("webex meeting")
                || title.contains("meeting information")
                || title.contains("meeting details")
                || title.contains("personal room")
                || title.contains("webex call")
                || (owner.contains("webex") && Self.containsStandaloneMeeting(in: title))
        }
    }

    private static func containsStandaloneMeeting(in text: String) -> Bool {
        text.range(of: #"\bmeeting\b"#, options: .regularExpression) != nil
    }

    private static func isKnownNonMeetingTitle(_ title: String) -> Bool {
        title.isEmpty
            || title == "webex"
            || title == "cisco webex"
            || title == "zoom"
            || title == "zoom workplace"
            || title == "set a status"
            || title == "messaging"
            || title == "meetings"
            || title.contains("search, meet and call")
    }
}

private enum MeetingDetectionSource: String {
    case windowSignal
    case audioOutput
}

private enum MeetingPromptKind {
    case startListening
    case finishRecording
}

private struct DetectedMeeting {
    let meetingApp: MeetingApp
    let appName: String
    let processID: pid_t
    let windowTitle: String?
    let isAudioOutputActive: Bool
    let detectionSource: MeetingDetectionSource

    var key: String {
        "\(meetingApp.rawValue):\(processID)"
    }

    var requiresAudioConfirmation: Bool {
        detectionSource == .audioOutput
    }

    var displayName: String {
        let trimmedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedAppName.isEmpty ? meetingApp.displayName : trimmedAppName
    }
}

@MainActor
private final class MeetingDetectionStore: ObservableObject {
    private struct Candidate {
        let meetingApp: MeetingApp
        let appName: String
        let processID: pid_t
    }

    private struct VisibleWindow {
        let processID: pid_t
        let ownerName: String
        let title: String?
        let bounds: CGRect
    }

    private weak var viewModel: SubtitleViewModel?
    private var startListeningHandler: (() -> Void)?
    private let monitoringQueue = DispatchQueue(label: "Speechara.MeetingDetection", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var monitoringActivity: NSObjectProtocol?
    private var panel: NSPanel?
    private var currentPromptKind: MeetingPromptKind?
    private var currentMeeting: DetectedMeeting?
    private var activeMeeting: DetectedMeeting?
    private var activeMeetingLastSeenAt: Date?
    private var dismissedMeetings = [String: Date]()
    private var presentedMeetings = [String: Date]()
    private var dismissedEndPrompts = [String: Date]()
    private var presentedEndPrompts = [String: Date]()
    private var audioOnlyMeetingsFirstSeen = [String: Date]()

    private let pollingInterval: TimeInterval = 2
    private let audioOutputConfirmationInterval: TimeInterval = 6
    private let meetingEndGraceInterval: TimeInterval = 60
    private let dismissCooldown: TimeInterval = 10 * 60
    private let presentCooldown: TimeInterval = 2 * 60
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Speechara",
        category: "MeetingDetection"
    )

    init(viewModel: SubtitleViewModel? = nil) {
        self.viewModel = viewModel
        startMonitoringIfNeeded()
    }

    func configure(
        viewModel: SubtitleViewModel,
        startListening: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        startListeningHandler = startListening
        startMonitoringIfNeeded()
    }

    private func startMonitoringIfNeeded() {
        guard timer == nil else {
            pollForMeetings()
            return
        }

        startBackgroundActivityIfNeeded()
        pollForMeetings()

        let timer = DispatchSource.makeTimerSource(queue: monitoringQueue)
        timer.schedule(
            deadline: .now() + pollingInterval,
            repeating: pollingInterval,
            leeway: .milliseconds(250)
        )
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.pollForMeetings()
            }
        }
        timer.resume()
        self.timer = timer
        Self.logger.info("Meeting detector started with dispatch timer interval \(self.pollingInterval, privacy: .public)s")
    }

    private func startBackgroundActivityIfNeeded() {
        guard monitoringActivity == nil else {
            return
        }

        monitoringActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Speechara watches meeting apps so it can suggest starting listening while running in the menu bar."
        )
    }

    deinit {
        timer?.cancel()

        if let monitoringActivity {
            ProcessInfo.processInfo.endActivity(monitoringActivity)
        }
    }

    private func pollForMeetings() {
        guard let viewModel else {
            closePanel()
            resetActiveMeetingTracking()
            return
        }

        guard !viewModel.hasActiveSession else {
            pollForMeetingEndPrompt(viewModel: viewModel)
            return
        }

        resetActiveMeetingTracking()
        if currentPromptKind == .finishRecording {
            closePanel()
        }

        guard let meeting = Self.detectMeeting() else {
            audioOnlyMeetingsFirstSeen.removeAll()
            return
        }

        guard confirmMeetingIfNeeded(meeting) else {
            return
        }

        presentMeetingIfNeeded(meeting)
    }

    private func pollForMeetingEndPrompt(viewModel: SubtitleViewModel) {
        if currentPromptKind == .startListening {
            closePanel()
        }

        guard (viewModel.isSystemAudioListening || viewModel.isMicrophoneListening),
              !viewModel.isBusy,
              !viewModel.isMicrophoneBusy else {
            return
        }

        if let meeting = Self.detectMeeting() {
            activeMeeting = meeting
            activeMeetingLastSeenAt = Date()

            if currentPromptKind == .finishRecording, panel?.isVisible == true {
                closePanel()
            }

            return
        }

        guard let meeting = activeMeeting,
              let lastSeenAt = activeMeetingLastSeenAt else {
            return
        }

        guard Date().timeIntervalSince(lastSeenAt) >= meetingEndGraceInterval else {
            return
        }

        presentMeetingEndPromptIfNeeded(meeting)
    }

    private func confirmMeetingIfNeeded(_ meeting: DetectedMeeting) -> Bool {
        guard meeting.requiresAudioConfirmation else {
            audioOnlyMeetingsFirstSeen[meeting.key] = nil
            return true
        }

        let now = Date()
        guard let firstSeenAt = audioOnlyMeetingsFirstSeen[meeting.key] else {
            audioOnlyMeetingsFirstSeen[meeting.key] = now
            Self.logger.info("Meeting candidate is audio-only; waiting for stable audio before showing popup.")
            return false
        }

        return now.timeIntervalSince(firstSeenAt) >= audioOutputConfirmationInterval
    }

    private func presentMeetingIfNeeded(_ meeting: DetectedMeeting) {
        let now = Date()

        if let dismissedAt = dismissedMeetings[meeting.key],
           now.timeIntervalSince(dismissedAt) < dismissCooldown {
            return
        }

        if let presentedAt = presentedMeetings[meeting.key],
           now.timeIntervalSince(presentedAt) < presentCooldown {
            return
        }

        if currentMeeting?.key == meeting.key, panel?.isVisible == true {
            return
        }

        currentMeeting = meeting
        currentPromptKind = .startListening
        presentedMeetings[meeting.key] = now
        Self.logger.info(
            "Presenting meeting popup for \(meeting.displayName, privacy: .public), source=\(meeting.detectionSource.rawValue, privacy: .public)"
        )
        showPanel(for: meeting)
    }

    private func showPanel(for meeting: DetectedMeeting) {
        closePanel()
        currentMeeting = meeting
        currentPromptKind = .startListening

        let contentView = SpeecharaMeetingDetectedPanelView(
            meeting: meeting,
            startListening: { [weak self] in
                self?.startDetectedMeeting()
            },
            dismiss: { [weak self] in
                self?.dismissDetectedMeeting()
            }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 106),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: contentView)

        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func presentMeetingEndPromptIfNeeded(_ meeting: DetectedMeeting) {
        let now = Date()

        if let dismissedAt = dismissedEndPrompts[meeting.key],
           now.timeIntervalSince(dismissedAt) < dismissCooldown {
            return
        }

        if let presentedAt = presentedEndPrompts[meeting.key],
           now.timeIntervalSince(presentedAt) < presentCooldown {
            return
        }

        if currentPromptKind == .finishRecording,
           currentMeeting?.key == meeting.key,
           panel?.isVisible == true {
            return
        }

        currentMeeting = meeting
        currentPromptKind = .finishRecording
        presentedEndPrompts[meeting.key] = now
        Self.logger.info("Presenting finish recording popup for \(meeting.displayName, privacy: .public)")
        showMeetingEndPanel(for: meeting)
    }

    private func showMeetingEndPanel(for meeting: DetectedMeeting) {
        closePanel()
        currentMeeting = meeting
        currentPromptKind = .finishRecording

        let contentView = SpeecharaMeetingEndedPanelView(
            meeting: meeting,
            finishRecording: { [weak self] in
                self?.finishDetectedMeeting()
            },
            keepRecording: { [weak self] in
                self?.dismissMeetingEndPrompt()
            }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 116),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: contentView)

        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }

        let x = visibleFrame.maxX - panel.frame.width - 24
        let y = visibleFrame.maxY - panel.frame.height - 18
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func startDetectedMeeting() {
        guard viewModel?.hasActiveSession != true else {
            closePanel()
            return
        }

        let meeting = currentMeeting
        if let startListeningHandler {
            startListeningHandler()
        } else if let viewModel {
            viewModel.startListening(mode: .newSession, includeMicrophone: viewModel.startsWithMicrophoneEnabled)
        }

        if let meeting, meeting.detectionSource == .windowSignal {
            activeMeeting = meeting
            activeMeetingLastSeenAt = Date()
        }

        closePanel()
    }

    private func finishDetectedMeeting() {
        viewModel?.stopActiveSession()
        resetActiveMeetingTracking()
        closePanel()
    }

    private func dismissMeetingEndPrompt() {
        if let currentMeeting {
            dismissedEndPrompts[currentMeeting.key] = Date()
            activeMeetingLastSeenAt = Date()
        }
        closePanel()
    }

    private func dismissDetectedMeeting() {
        if let currentMeeting {
            dismissedMeetings[currentMeeting.key] = Date()
        }
        closePanel()
    }

    private func closePanel() {
        panel?.close()
        panel = nil
        currentPromptKind = nil
        currentMeeting = nil
    }

    private func resetActiveMeetingTracking() {
        activeMeeting = nil
        activeMeetingLastSeenAt = nil
    }

    private static func detectMeeting() -> DetectedMeeting? {
        detectMeeting(includeAudioOutput: true)
    }

    private static func detectMeeting(includeAudioOutput: Bool) -> DetectedMeeting? {
        let windows = visibleWindows()
        let candidates = runningMeetingCandidates()

        for candidate in candidates {
            let isAudioOutputActive = isProcessRunningOutput(candidate.processID)
            let candidateWindows = windows.filter { window in
                window.processID == candidate.processID && isMeetingWindowSize(window)
            }

            if let window = candidateWindows.first(where: { window in
                candidate.meetingApp.hasMeetingSignal(windowTitle: window.title, ownerName: window.ownerName)
            }) {
                return DetectedMeeting(
                    meetingApp: candidate.meetingApp,
                    appName: candidate.appName,
                    processID: candidate.processID,
                    windowTitle: window.title,
                    isAudioOutputActive: isAudioOutputActive,
                    detectionSource: .windowSignal
                )
            }

            if includeAudioOutput && isAudioOutputActive {
                return DetectedMeeting(
                    meetingApp: candidate.meetingApp,
                    appName: candidate.appName,
                    processID: candidate.processID,
                    windowTitle: candidateWindows.first?.title,
                    isAudioOutputActive: true,
                    detectionSource: .audioOutput
                )
            }
        }

        for window in windows where isMeetingWindowSize(window) {
            guard let meetingApp = MeetingApp.match(windowTitle: window.title, ownerName: window.ownerName),
                  meetingApp.hasMeetingSignal(windowTitle: window.title, ownerName: window.ownerName) else {
                continue
            }

            return DetectedMeeting(
                meetingApp: meetingApp,
                appName: meetingApp.displayName,
                processID: window.processID,
                windowTitle: window.title,
                isAudioOutputActive: isProcessRunningOutput(window.processID),
                detectionSource: .windowSignal
            )
        }

        return nil
    }

    private static func isMeetingWindowSize(_ window: VisibleWindow) -> Bool {
        window.bounds.width >= 360 && window.bounds.height >= 220
    }

    private static func runningMeetingCandidates() -> [Candidate] {
        NSWorkspace.shared.runningApplications.compactMap { runningApp in
            guard let meetingApp = MeetingApp.match(
                bundleIdentifier: runningApp.bundleIdentifier,
                appName: runningApp.localizedName
            ) else {
                return nil
            }

            return Candidate(
                meetingApp: meetingApp,
                appName: runningApp.localizedName ?? meetingApp.displayName,
                processID: runningApp.processIdentifier
            )
        }
    }

    private static func visibleWindows() -> [VisibleWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowInfo.compactMap { info -> VisibleWindow? in
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0,
                  let processNumber = info[kCGWindowOwnerPID as String] as? Int else {
                return nil
            }

            let bounds = windowBounds(from: info[kCGWindowBounds as String])
            guard bounds.width > 0, bounds.height > 0 else {
                return nil
            }

            return VisibleWindow(
                processID: pid_t(processNumber),
                ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
                title: info[kCGWindowName as String] as? String,
                bounds: bounds
            )
        }
    }

    private static func windowBounds(from value: Any?) -> CGRect {
        guard let dictionary = value as? [String: Any] else {
            return .zero
        }

        var rect = CGRect.zero
        CGRectMakeWithDictionaryRepresentation(dictionary as CFDictionary, &rect)
        return rect
    }

    private static func isProcessRunningOutput(_ processID: pid_t) -> Bool {
        guard let processObjectID = audioProcessObjectID(for: processID) else {
            return false
        }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(processObjectID, &propertyAddress) else {
            return false
        }

        var isRunningOutput: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            processObjectID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &isRunningOutput
        )

        return status == noErr && isRunningOutput != 0
    }

    private static func audioProcessObjectID(for processID: pid_t) -> AudioObjectID? {
        var processID = processID
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let qualifierSize = UInt32(MemoryLayout<pid_t>.size)
        let status = withUnsafePointer(to: &processID) { processIDPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                qualifierSize,
                processIDPointer,
                &dataSize,
                &processObjectID
            )
        }

        guard status == noErr, processObjectID != kAudioObjectUnknown else {
            return nil
        }

        return processObjectID
    }
}

private struct SpeecharaMeetingDetectedPanelView: View {
    let meeting: DetectedMeeting
    let startListening: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.blue)
                .frame(width: 4, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(SL("Meeting detected"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(meeting.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if meeting.isAudioOutputActive {
                    Text(SL("Meeting audio is active"))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Button(action: {
                startListening()
            }) {
                HStack(spacing: 8) {
                    Image("SpeecharaMenuBarIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)

                    Text(SL("Start Listening"))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.16, green: 0.38, blue: 1.0),
                                    Color(red: 0.08, green: 0.22, blue: 0.78),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 520, height: 106)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(1)
    }
}

private struct SpeecharaMeetingEndedPanelView: View {
    let meeting: DetectedMeeting
    let finishRecording: () -> Void
    let keepRecording: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: keepRecording) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 0.92, green: 0.20, blue: 0.18))
                .frame(width: 4, height: 62)

            VStack(alignment: .leading, spacing: 4) {
                Text(SL("Meeting ended?"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(meeting.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(SL("Speechara is still listening."))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Button(action: keepRecording) {
                Text(SL("Keep Listening"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)

            Button(action: finishRecording) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))

                    Text(SL("Stop Listening"))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.84, green: 0.16, blue: 0.17))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 540, height: 116)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(1)
    }
}

struct SpeecharaRGBA {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    init(_ red: Double, _ green: Double, _ blue: Double, _ opacity: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
}

extension Color {
    static func speecharaDynamic(light: SpeecharaRGBA, dark: SpeecharaRGBA) -> Color {
        Color(
            nsColor: NSColor(
                name: nil,
                dynamicProvider: { appearance in
                    let isDarkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    let resolved = isDarkMode ? dark : light
                    return NSColor(
                        calibratedRed: resolved.red,
                        green: resolved.green,
                        blue: resolved.blue,
                        alpha: resolved.opacity
                    )
                }
            )
        )
    }
}
