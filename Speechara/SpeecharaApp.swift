import AppKit
import Combine
import CoreAudio
import CoreGraphics
import OSLog
import SwiftUI

enum SpeecharaDiagnostics {
    static let app = Logger(subsystem: "ai.speechara.mac", category: "App")
    static let session = Logger(subsystem: "ai.speechara.mac", category: "Session")
    static let audio = Logger(subsystem: "ai.speechara.mac", category: "Audio")
    static let transcription = Logger(subsystem: "ai.speechara.mac", category: "Transcription")
    static let translation = Logger(subsystem: "ai.speechara.mac", category: "Translation")
    static let history = Logger(subsystem: "ai.speechara.mac", category: "History")
    static let auth = Logger(subsystem: "ai.speechara.mac", category: "Auth")

    static func textSummary(_ text: String, limit: Int = 100) -> String {
        String(text.replacingOccurrences(of: "\n", with: " ").prefix(limit))
    }
}

extension Notification.Name {
    static let speecharaMeetingHistoryDidChange = Notification.Name("speechara.meetingHistoryDidChange")
    static let speecharaOpenMainWindow = Notification.Name("speechara.openMainWindow")
    static let speecharaInterfaceLanguageWillChange = Notification.Name("speechara.interfaceLanguageWillChange")
}

@MainActor
private final class SpeecharaPresentationStore: ObservableObject {
    static let shared = SpeecharaPresentationStore()

    @Published private(set) var isBackgroundOnly = false
    @Published private(set) var miniWindowGeneration = UUID()

    private init() {}

    func enterBackgroundOnlyMode() {
        guard !isBackgroundOnly else {
            return
        }

        isBackgroundOnly = true
        SpeecharaDiagnostics.app.notice("entering background-only presentation mode")
        SpeecharaMiniWindowCoordinator.hideAllWindowsForBackgroundMode()

        if !NSApp.setActivationPolicy(.accessory) {
            SpeecharaDiagnostics.app.error("failed to switch activation policy to accessory")
        }
    }

    func restoreApplication(openWindow: @escaping @MainActor () -> Void) {
        let wasBackgroundOnly = isBackgroundOnly
        isBackgroundOnly = false
        if wasBackgroundOnly {
            miniWindowGeneration = UUID()
        }
        SpeecharaDiagnostics.app.notice("restoring regular application presentation mode")

        let revealWindow = {
            SpeecharaMiniWindowCoordinator.restoreWindowsForUserRequest()
            openWindow()
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        guard NSApp.activationPolicy() != .regular else {
            revealWindow()
            return
        }

        if !NSApp.setActivationPolicy(.regular) {
            SpeecharaDiagnostics.app.error("failed to restore regular activation policy")
        }

        // AppKit needs one main-loop pass after becoming a regular application
        // before a SwiftUI window can reliably become key on every macOS version.
        Task { @MainActor in
            await Task.yield()
            revealWindow()
        }
    }
}

@main
struct SpeecharaApp: App {
    @NSApplicationDelegateAdaptor(SpeecharaAppDelegate.self) private var appDelegate
    @StateObject private var authStore = AuthSessionStore()
    @StateObject private var subtitleViewModel: SubtitleViewModel
    @StateObject private var localizationStore = SpeecharaLocalizationStore.shared
    @StateObject private var meetingDetectionStore: MeetingDetectionStore
    @StateObject private var presentationStore = SpeecharaPresentationStore.shared
    @AppStorage("speechara.appearanceMode") private var appearanceModeRawValue = SpeecharaAppearanceMode.system.rawValue

    private var appearanceMode: SpeecharaAppearanceMode {
        SpeecharaAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    private var interfaceLayoutDirection: LayoutDirection {
        localizationStore.language.isRightToLeft ? .rightToLeft : .leftToRight
    }

    init() {
#if !APP_STORE
        SpeecharaUpdateController.shared.activate()
#endif
        SpeecharaLocalizationStore.shared.installBundleOverrideIfNeeded()
        let viewModel = SubtitleViewModel()
        SpeecharaAppDelegate.subtitleViewModel = viewModel
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
                .environmentObject(presentationStore)
                .environment(\.locale, localizationStore.locale)
                .environment(\.layoutDirection, interfaceLayoutDirection)
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
                .environmentObject(presentationStore)
                .environment(\.locale, localizationStore.locale)
                .environment(\.layoutDirection, interfaceLayoutDirection)
                .preferredColorScheme(appearanceMode.preferredColorScheme)
                .id(localizationStore.language.rawValue)
        }

        Window(SL("Listening"), id: "speechara-listening-mini") {
            SpeecharaListeningMiniView()
                .environmentObject(subtitleViewModel)
                .environmentObject(localizationStore)
                .environmentObject(meetingDetectionStore)
                .environmentObject(presentationStore)
                .environment(\.locale, localizationStore.locale)
                .environment(\.layoutDirection, interfaceLayoutDirection)
                .preferredColorScheme(appearanceMode.preferredColorScheme)
                .id("\(localizationStore.language.rawValue)-\(presentationStore.miniWindowGeneration.uuidString)")
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            SpeecharaMenuBarMenu()
                .environmentObject(authStore)
                .environmentObject(subtitleViewModel)
                .environmentObject(localizationStore)
                .environmentObject(meetingDetectionStore)
                .environmentObject(presentationStore)
                .environment(\.locale, localizationStore.locale)
                .environment(\.layoutDirection, interfaceLayoutDirection)
                .id(localizationStore.language.rawValue)
        } label: {
            SpeecharaMenuBarLabel(
                isActive: subtitleViewModel.hasActiveSession,
                viewModel: subtitleViewModel,
                meetingDetectionStore: meetingDetectionStore
            )
            // The MenuBarExtra label has its own SwiftUI hierarchy. Its action
            // handlers also need the session store used by the popup content.
            .environmentObject(authStore)
            .environmentObject(subtitleViewModel)
            .environmentObject(meetingDetectionStore)
            .environmentObject(presentationStore)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct SpeecharaBackgroundCoordinatorView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var viewModel: SubtitleViewModel
    @EnvironmentObject private var meetingDetectionStore: MeetingDetectionStore
    @EnvironmentObject private var presentationStore: SpeecharaPresentationStore
    @AppStorage("speechara.isMiniWindowEnabled") private var isMiniWindowEnabled = true
    @State private var suppressMiniWindowUntil = Date.distantPast
    private let miniWindowVisibilityTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        Color.clear
            .onAppear {
                meetingDetectionStore.configure(
                    viewModel: viewModel,
                    startListening: {
                        startListeningAfterAuthRefresh()
                    },
                    shouldSuppressPrompts: {
                        presentationStore.isBackgroundOnly
                    }
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .speecharaInterfaceLanguageWillChange)) { _ in
                suppressMiniWindowUntil = Date().addingTimeInterval(1.5)
                SpeecharaMiniWindowCoordinator.closeMiniWindow(
                    restoringMainWindow: !presentationStore.isBackgroundOnly
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    synchronizeMiniWindowVisibility()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                synchronizeMiniWindowVisibility()
                if authStore.session != nil { viewModel.resumeMeetingHistorySync() }
            }
            .task(id: authStore.session?.user.id) {
                if authStore.session != nil { viewModel.resumeMeetingHistorySync() }
            }
            .onReceive(miniWindowVisibilityTimer) { _ in
                synchronizeMiniWindowVisibility()
            }
            .onChange(of: viewModel.hasActiveSession) { _ in
                synchronizeMiniWindowVisibility()
            }
    }

    private func startListeningAfterAuthRefresh() {
        Task { @MainActor in
            do {
                try await authStore.ensureActiveSession()
                viewModel.promptAndStartListening(includeMicrophone: viewModel.startsWithMicrophoneEnabled)
                revealMainWindowUnlessBackgroundOnly()
            } catch {
                viewModel.showErrorMessage(authStore.errorMessage ?? error.localizedDescription)
                revealMainWindowUnlessBackgroundOnly()
            }
        }
    }

    private func revealMainWindowUnlessBackgroundOnly() {
        guard !presentationStore.isBackgroundOnly else {
            return
        }

        presentationStore.restoreApplication {
            openWindow(id: "speechara-main")
        }
    }

    private func synchronizeMiniWindowVisibility() {
        guard !presentationStore.isBackgroundOnly else {
            SpeecharaMiniWindowCoordinator.closeMiniWindow(restoringMainWindow: false)
            return
        }

        guard isMiniWindowEnabled,
              viewModel.hasActiveSession,
              Date() >= suppressMiniWindowUntil,
              SpeecharaMiniWindowCoordinator.shouldPresentMiniWindow() else {
            SpeecharaMiniWindowCoordinator.closeMiniWindow()
            return
        }

        SpeecharaMiniWindowCoordinator.hideMainWindowIfNeeded()

        guard !SpeecharaMiniWindowCoordinator.isMiniWindowVisible else {
            SpeecharaMiniWindowCoordinator.presentMiniWindowOverOtherApps()
            return
        }

        SpeecharaDiagnostics.app.notice(
            "opening mini window transcriptChars=\(viewModel.subtitlesText.count, privacy: .public) translationChars=\(viewModel.translatedText.count, privacy: .public) transcriptEntries=\(viewModel.transcriptEntries.count, privacy: .public) translationEntries=\(viewModel.translationEntries.count, privacy: .public)"
        )
        openWindow(id: "speechara-listening-mini")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard isMiniWindowEnabled,
                  viewModel.hasActiveSession,
                  !presentationStore.isBackgroundOnly,
                  SpeecharaMiniWindowCoordinator.shouldPresentMiniWindow() else {
                SpeecharaMiniWindowCoordinator.closeMiniWindow(
                    restoringMainWindow: !presentationStore.isBackgroundOnly
                )
                return
            }

            SpeecharaMiniWindowCoordinator.presentMiniWindowOverOtherApps()
        }
    }
}

@MainActor
final class SpeecharaAppDelegate: NSObject, NSApplicationDelegate {
    static weak var subtitleViewModel: SubtitleViewModel?
    private var isFinishingMeeting = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel = Self.subtitleViewModel else { return .terminateNow }
        guard !isFinishingMeeting else { return .terminateLater }
        isFinishingMeeting = true
        Task { @MainActor in
            await viewModel.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

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
    @EnvironmentObject private var presentationStore: SpeecharaPresentationStore
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
                    },
                    shouldSuppressPrompts: {
                        presentationStore.isBackgroundOnly
                    }
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .speecharaOpenMainWindow)) { _ in
                presentationStore.restoreApplication {
                    openWindow(id: "speechara-main")
                }
            }
    }

    private func startListeningAfterAuthRefresh() {
        Task { @MainActor in
            do {
                try await authStore.ensureActiveSession()
                viewModel.promptAndStartListening(includeMicrophone: viewModel.startsWithMicrophoneEnabled)
                revealMainWindowUnlessBackgroundOnly()
            } catch {
                viewModel.showErrorMessage(authStore.errorMessage ?? error.localizedDescription)
                revealMainWindowUnlessBackgroundOnly()
            }
        }
    }

    private func revealMainWindowUnlessBackgroundOnly() {
        guard !presentationStore.isBackgroundOnly else {
            return
        }

        presentationStore.restoreApplication {
            openWindow(id: "speechara-main")
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
    @EnvironmentObject private var presentationStore: SpeecharaPresentationStore
    @AppStorage("speechara.miniWindowLayout") private var layoutRawValue = SpeecharaMiniWindowLayout.columns.rawValue
    @AppStorage("speechara.miniWindowSplit") private var splitFraction = 0.5

    private var layout: SpeecharaMiniWindowLayout {
        SpeecharaMiniWindowLayout(rawValue: layoutRawValue) ?? .columns
    }

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

    private var transcriptViewerText: String {
        let transcript = viewModel.subtitlesText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !transcript.isEmpty {
            return transcript
        }

        if !viewModel.liveSubtitlePreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }

        return SL("Waiting for speech...")
    }

    private var translationViewerText: String {
        let translation = viewModel.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !translation.isEmpty {
            return translation
        }

        if !viewModel.liveTranslationPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }

        return viewModel.translationPlaceholderText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(viewModel.hasActiveSession ? Color(red: 0.92, green: 0.05, blue: 0.08) : .secondary)
                            .frame(width: 8, height: 8)

                        Text(statusTitle)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }

                    Text(viewModel.selectedMicrophoneName)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Picker("", selection: $layoutRawValue) {
                    Image(systemName: "rectangle.split.2x1")
                        .tag(SpeecharaMiniWindowLayout.columns.rawValue)
                    Image(systemName: "rectangle.split.1x2")
                        .tag(SpeecharaMiniWindowLayout.rows.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 68)
                .help("Switch transcript layout")

                miniMicrophoneControl
                miniStopButton
            }

            if viewModel.isTranslationEnabled {
                resizableTranscriptLayout
                .layoutPriority(1)
            } else {
                transcriptPanel
                    .layoutPriority(1)
            }

            footerControls
        }
        .padding(18)
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 420, idealWidth: 720, maxWidth: .infinity, minHeight: 300, idealHeight: 420, maxHeight: .infinity)
        .background(SpeecharaFloatingMiniWindowConfigurator())
        .onAppear {
            SpeecharaDiagnostics.app.notice(
                "mini window appeared generation=\(presentationStore.miniWindowGeneration.uuidString, privacy: .public) transcriptChars=\(viewModel.subtitlesText.count, privacy: .public) translationChars=\(viewModel.translatedText.count, privacy: .public) transcriptDraftChars=\(viewModel.liveSubtitlePreview.count, privacy: .public) translationDraftChars=\(viewModel.liveTranslationPreview.count, privacy: .public)"
            )
        }
    }

    private var footerControls: some View {
        HStack(spacing: 10) {
            expandButton
            hideCompletelyButton
            Spacer()
        }
    }

    private var expandButton: some View {
        Button(SL("Expand Speechara")) {
            presentationStore.restoreApplication {
                openWindow(id: "speechara-main")
            }
        }
    }

    private var hideCompletelyButton: some View {
        Button {
            presentationStore.enterBackgroundOnlyMode()
        } label: {
            Label(SL("Hide completely"), systemImage: "eye.slash")
        }
        .help(SL("Keep listening with all Speechara windows hidden."))
    }

    private var miniMicrophoneControl: some View {
        HStack(spacing: 0) {
            Menu {
                microphoneMenuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(miniMicrophoneForegroundColor)
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(SL("Select microphone"))

            Rectangle()
                .fill(miniMicrophoneDividerColor)
                .frame(width: 1, height: 18)

            Button {
                viewModel.toggleMicrophoneCapture()
            } label: {
                Image(systemName: viewModel.isMicrophoneListening ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(miniMicrophoneForegroundColor)
                    .frame(width: 34, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(
                viewModel.isMicrophoneListening
                    ? SL("Turn microphone off. Right-click to choose a microphone.")
                    : SL("Turn microphone on. Right-click to choose a microphone.")
            )
        }
        .foregroundStyle(miniMicrophoneForegroundColor)
        .background(
            Capsule(style: .continuous)
                .fill(miniMicrophoneBackgroundColor)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(miniMicrophoneBorderColor, lineWidth: 1)
        )
        .disabled(viewModel.isBusy || viewModel.isMicrophoneBusy)
        .opacity(viewModel.isBusy || viewModel.isMicrophoneBusy ? 0.5 : 1)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var microphoneMenuItems: some View {
        Group {
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
    }

    private var miniStopButton: some View {
        Button {
            viewModel.stopActiveSession()
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .help(SL("Stop Listening"))
        .accessibilityLabel(SL("Stop Listening"))
        .disabled(!viewModel.hasActiveSession || viewModel.isBusy || viewModel.isMicrophoneBusy)
        .opacity(!viewModel.hasActiveSession || viewModel.isBusy || viewModel.isMicrophoneBusy ? 0.5 : 1)
    }

    private var miniMicrophoneActiveColor: Color {
        Color(red: 0.84, green: 0.16, blue: 0.17)
    }

    private var miniMicrophoneForegroundColor: Color {
        viewModel.isMicrophoneListening ? miniMicrophoneActiveColor : .secondary
    }

    private var miniMicrophoneBackgroundColor: Color {
        viewModel.isMicrophoneListening
            ? miniMicrophoneActiveColor.opacity(0.055)
            : Color.secondary.opacity(0.10)
    }

    private var miniMicrophoneBorderColor: Color {
        viewModel.isMicrophoneListening
            ? miniMicrophoneActiveColor.opacity(0.88)
            : Color.secondary.opacity(0.18)
    }

    private var miniMicrophoneDividerColor: Color {
        viewModel.isMicrophoneListening
            ? miniMicrophoneActiveColor.opacity(0.28)
            : Color.secondary.opacity(0.22)
    }

    private var transcriptPanel: some View {
        SpeecharaMiniTranscriptPanel(
            title: SL("Live transcript"),
            text: transcriptViewerText,
            draftText: viewModel.liveSubtitlePreview,
            systemImage: "waveform"
        )
    }

    private var translationPanel: some View {
        SpeecharaMiniTranscriptPanel(
            title: viewModel.translationPanelTitle,
            text: translationViewerText,
            draftText: viewModel.liveTranslationPreview,
            systemImage: "character.bubble"
        )
    }

    private var resizableTranscriptLayout: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 0
            let dividerSize: CGFloat = 8
            let available = layout == .columns ? proxy.size.width : proxy.size.height
            let firstSize = max(90, min(available - dividerSize - 90, available * splitFraction))
            let secondSize = max(90, available - dividerSize - firstSize)

            Group {
                if layout == .columns {
                    HStack(spacing: gap) {
                        transcriptPanel.frame(width: firstSize)
                        splitDivider(available: proxy.size.width)
                        translationPanel.frame(width: secondSize)
                    }
                } else {
                    VStack(spacing: gap) {
                        transcriptPanel.frame(height: firstSize)
                        splitDivider(available: proxy.size.height)
                        translationPanel.frame(height: secondSize)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "speechara-mini-split")
        }
    }

    private func splitDivider(available: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.secondary.opacity(0.20))
            .frame(
                width: layout == .columns ? 3 : 24,
                height: layout == .columns ? 24 : 3
            )
            .frame(
                width: layout == .columns ? 8 : nil,
                height: layout == .columns ? nil : 8
            )
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    (layout == .columns ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
            .overlay {
                Image(systemName: layout == .columns ? "arrow.left.and.right" : "arrow.up.and.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .gesture(
                DragGesture(coordinateSpace: .named("speechara-mini-split"))
                    .onChanged { value in
                        let position = layout == .columns ? value.location.x : value.location.y
                        splitFraction = max(0.2, min(0.8, position / max(1, available)))
                    }
            )
            .accessibilityLabel("Resize transcript panels")
    }
}

private enum SpeecharaMiniWindowLayout: String {
    case columns
    case rows
}

private struct SpeecharaMiniTranscriptPanel: View {
    let title: String
    let text: String
    let draftText: String
    let systemImage: String
    @State private var scrollWorkItem: DispatchWorkItem?
    private let bottomAnchor = "mini-transcript-bottom-anchor"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !text.isEmpty {
                            Text(text)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .textSelection(.enabled)
                        }

                        if !cleanDraft.isEmpty {
                            Text(cleanDraft)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .textSelection(.enabled)
                                .accessibilityLabel(SL("Live draft"))
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchor)
                    }
                    .padding(12)
                }
                .onAppear {
                    scrollToBottom(using: proxy)
                }
                .onChange(of: scrollSignature) { _ in
                    scrollToBottom(using: proxy)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var cleanDraft: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var scrollSignature: String {
        "\(text)-\(cleanDraft)"
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        scrollWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
        scrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
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
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.resizable)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: 420, height: 300)
            window.maxSize = NSSize(width: 960, height: 680)
            window.identifier = NSUserInterfaceItemIdentifier("speechara-listening-mini")
            window.orderFrontRegardless()
        }
    }
}

@MainActor
enum SpeecharaMiniWindowCoordinator {
    private static let mainWindowTitle = "Speechara"
    private static let miniWindowIdentifier = NSUserInterfaceItemIdentifier("speechara-listening-mini")
    private static let coveredSampleColumns = 12
    private static let coveredSampleRows = 8
    private static let coveredSampleThreshold = 0.94
    private static weak var mainWindowHiddenForMiniWindow: NSWindow?
    private static var hiddenMainWindowBounds: CGRect?
    private static var coveringApplicationPID: pid_t?

    static func shouldPresentMiniWindow() -> Bool {
        guard let mainWindow = NSApp.windows.first(where: { $0.title == mainWindowTitle }) else {
            return true
        }

        if mainWindowHiddenForMiniWindow === mainWindow {
            return isHiddenMainWindowStillCovered()
        }

        guard mainWindow.isVisible, !mainWindow.isMiniaturized else {
            return true
        }

        // AppKit is a useful fast path, but it can report this app as visible
        // when several foreign windows together cover it. Confirm with the
        // actual WindowServer stacking order in that case.
        return !mainWindow.occlusionState.contains(.visible)
            || isMainWindowFullyCoveredByOtherApps(mainWindow)
    }

    static func hideMainWindowIfNeeded() {
        guard mainWindowHiddenForMiniWindow == nil,
              let mainWindow = NSApp.windows.first(where: { $0.title == mainWindowTitle }),
              mainWindow.isVisible,
              !mainWindow.isMiniaturized,
              let windowInfo = onScreenWindowInfo(),
              let mainInfo = windowInfo.first(where: {
                  integerValue($0[kCGWindowNumber as String]) == mainWindow.windowNumber
              }),
              let bounds = windowBounds(from: mainInfo[kCGWindowBounds as String]) else {
            // When Webex is in a separate full-screen Space, the main window is
            // already absent from that Space and must remain attached to its own one.
            return
        }

        hiddenMainWindowBounds = bounds
        coveringApplicationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        mainWindowHiddenForMiniWindow = mainWindow
        mainWindow.orderOut(nil)
    }

    static func presentMiniWindowOverOtherApps() {
        for window in NSApp.windows {
            if isMiniWindow(window) {
                window.level = .floating
                window.collectionBehavior.insert(.canJoinAllSpaces)
                window.collectionBehavior.insert(.fullScreenAuxiliary)
                window.hidesOnDeactivate = false
                window.orderFrontRegardless()
            }
        }
    }

    static var isMiniWindowVisible: Bool {
        NSApp.windows.contains { isMiniWindow($0) && $0.isVisible }
    }

    static func closeMiniWindow(restoringMainWindow: Bool = true) {
        NSApp.windows
            .filter(isMiniWindow)
            .forEach { $0.close() }

        if restoringMainWindow {
            restoreMainWindowIfNeeded()
        }
    }

    static func hideAllWindowsForBackgroundMode() {
        closeMiniWindow(restoringMainWindow: false)

        if mainWindowHiddenForMiniWindow == nil,
           let mainWindow = NSApp.windows.first(where: { $0.title == mainWindowTitle }) {
            mainWindowHiddenForMiniWindow = mainWindow
        }

        hiddenMainWindowBounds = nil
        coveringApplicationPID = nil

        NSApp.windows
            .filter { window in
                !isMiniWindow(window)
                    && window.isVisible
            }
            .forEach { $0.orderOut(nil) }
    }

    static func restoreWindowsForUserRequest() {
        closeMiniWindow(restoringMainWindow: false)
        restoreMainWindowIfNeeded()
    }

    private static func isMiniWindow(_ window: NSWindow) -> Bool {
        window.identifier == miniWindowIdentifier || window.title == SL("Listening")
    }

    private static func isMainWindowFullyCoveredByOtherApps(_ mainWindow: NSWindow) -> Bool {
        guard let windowInfo = onScreenWindowInfo() else {
            return false
        }

        // Full-screen meeting apps such as Webex live in their own macOS Space.
        // In that state the still-visible AppKit window is absent from WindowServer's
        // on-screen list, which means it is completely unavailable to the user.
        guard let mainIndex = windowInfo.firstIndex(where: {
            integerValue($0[kCGWindowNumber as String]) == mainWindow.windowNumber
        }) else {
            return true
        }

        guard
              let mainBounds = windowBounds(from: windowInfo[mainIndex][kCGWindowBounds as String]),
              mainBounds.width > 0,
              mainBounds.height > 0 else {
            return false
        }

        let coveringBounds = windowInfo[..<mainIndex].compactMap { info -> CGRect? in
            guard integerValue(info[kCGWindowLayer as String]) == 0,
                  let ownerPID = integerValue(info[kCGWindowOwnerPID as String]),
                  ownerPID != ProcessInfo.processInfo.processIdentifier,
                  (numberValue(info[kCGWindowAlpha as String]) ?? 1) > 0.05,
                  let bounds = windowBounds(from: info[kCGWindowBounds as String]),
                  bounds.intersects(mainBounds) else {
                return nil
            }
            return bounds
        }

        guard !coveringBounds.isEmpty else {
            return false
        }

        return isCovered(mainBounds, by: coveringBounds)
    }

    private static func isHiddenMainWindowStillCovered() -> Bool {
        guard let mainBounds = hiddenMainWindowBounds,
              let windowInfo = onScreenWindowInfo() else {
            return false
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let coveringPID = frontmostPID != ownPID ? frontmostPID : coveringApplicationPID

        guard let coveringPID else {
            return false
        }

        let coveringBounds = windowInfo.compactMap { info -> CGRect? in
            guard integerValue(info[kCGWindowLayer as String]) == 0,
                  integerValue(info[kCGWindowOwnerPID as String]) == Int(coveringPID),
                  (numberValue(info[kCGWindowAlpha as String]) ?? 1) > 0.05,
                  let bounds = windowBounds(from: info[kCGWindowBounds as String]),
                  bounds.intersects(mainBounds) else {
                return nil
            }
            return bounds
        }

        return isCovered(mainBounds, by: coveringBounds)
    }

    private static func isCovered(_ mainBounds: CGRect, by coveringBounds: [CGRect]) -> Bool {
        guard !coveringBounds.isEmpty else {
            return false
        }

        let sampleWidth = mainBounds.width / CGFloat(coveredSampleColumns)
        let sampleHeight = mainBounds.height / CGFloat(coveredSampleRows)
        var coveredSamples = 0
        let totalSamples = coveredSampleColumns * coveredSampleRows

        for column in 0 ..< coveredSampleColumns {
            for row in 0 ..< coveredSampleRows {
                let point = CGPoint(
                    x: mainBounds.minX + (CGFloat(column) + 0.5) * sampleWidth,
                    y: mainBounds.minY + (CGFloat(row) + 0.5) * sampleHeight
                )
                if coveringBounds.contains(where: { $0.contains(point) }) {
                    coveredSamples += 1
                }
            }
        }

        return Double(coveredSamples) / Double(totalSamples) >= coveredSampleThreshold
    }

    private static func restoreMainWindowIfNeeded() {
        guard let mainWindow = mainWindowHiddenForMiniWindow else {
            return
        }

        mainWindowHiddenForMiniWindow = nil
        hiddenMainWindowBounds = nil
        coveringApplicationPID = nil
        mainWindow.orderFront(nil)
    }

    private static func onScreenWindowInfo() -> [[String: Any]]? {
        CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]
    }

    private static func windowBounds(from value: Any?) -> CGRect? {
        guard let dictionary = value as? [String: Any],
              let x = numberValue(dictionary["X"]),
              let y = numberValue(dictionary["Y"]),
              let width = numberValue(dictionary["Width"]),
              let height = numberValue(dictionary["Height"]) else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func integerValue(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue ?? value as? Int
    }

    private static func numberValue(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber {
            return CGFloat(number.doubleValue)
        }
        return value as? CGFloat
    }

}

private struct SpeecharaMenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var viewModel: SubtitleViewModel
    @EnvironmentObject private var presentationStore: SpeecharaPresentationStore
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

        Button(SL("Show Speechara")) {
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
        presentationStore.restoreApplication {
            openWindow(id: "speechara-main")
        }
    }

    private func openSettingsWindow() {
        presentationStore.restoreApplication {
            openWindow(id: "speechara-settings")
        }
    }

    private func openListeningWindow() {
        presentationStore.restoreApplication {
            openWindow(id: "speechara-main")
        }
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
    private var shouldSuppressPrompts: () -> Bool = { false }
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
        startListening: @escaping () -> Void,
        shouldSuppressPrompts: @escaping () -> Bool = { false }
    ) {
        self.viewModel = viewModel
        startListeningHandler = startListening
        self.shouldSuppressPrompts = shouldSuppressPrompts
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
        guard !shouldSuppressPrompts() else {
            closePanel()
            return
        }

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
            viewModel.promptAndStartListening(includeMicrophone: viewModel.startsWithMicrophoneEnabled)
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
