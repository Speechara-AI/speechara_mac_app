import AppKit
import SwiftUI

private enum SpeecharaWorkspaceLayout: String {
    case columns
    case rows
}

struct ContentView: View {
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var viewModel: SubtitleViewModel
    @AppStorage("speechara.focusModeEnabled") private var isFocusModeEnabled = false
    @AppStorage("speechara.workspaceLayout") private var workspaceLayoutRawValue = SpeecharaWorkspaceLayout.columns.rawValue
    @AppStorage("speechara.workspaceSplit") private var workspaceSplitFraction = 0.5
    @State private var isListeningSetupPresented = false
    @State private var shouldStartListeningAfterSetup = false
    @State private var isMicrophoneOffWarningDismissed = false

    var body: some View {
        GeometryReader { _ in
            VStack(alignment: .leading, spacing: 20) {
                heroSection

                if let errorMessage = viewModel.errorMessage {
                    InlineStatusMessage(text: errorMessage, tint: .red)
                }

                if let translationMessage = viewModel.translationMessage {
                    InlineStatusMessage(text: translationMessage, tint: .orange)
                }

                if shouldShowMicrophoneOffWarning {
                    MicrophoneOffWarningBanner {
                        isMicrophoneOffWarningDismissed = true
                    }
                }

                resizableWorkspacePanels
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if viewModel.isTranscriptAnswerVisible {
                    assistantColumn
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 1120, minHeight: 760)
        .sheet(isPresented: $isListeningSetupPresented) {
            ListeningSetupSheet(viewModel: viewModel) {
                shouldStartListeningAfterSetup = true
                isListeningSetupPresented = false
            }
        }
        .onChange(of: isListeningSetupPresented) { isPresented in
            guard !isPresented, shouldStartListeningAfterSetup else {
                return
            }

            shouldStartListeningAfterSetup = false
            startListeningAfterAuthRefresh()
        }
        .onAppear {
            viewModel.setFocusModeEnabled(isFocusModeEnabled)
        }
        .onChange(of: isFocusModeEnabled) { isEnabled in
            viewModel.setFocusModeEnabled(isEnabled)
        }
        .onChange(of: viewModel.isMicrophoneListening) { _ in
            isMicrophoneOffWarningDismissed = false
        }
        .onChange(of: viewModel.hasActiveSession) { _ in
            isMicrophoneOffWarningDismissed = false
        }
    }

    private var workspaceLayout: SpeecharaWorkspaceLayout {
        SpeecharaWorkspaceLayout(rawValue: workspaceLayoutRawValue) ?? .columns
    }

    private var workspaceLayoutPicker: some View {
        Picker("Panel layout", selection: $workspaceLayoutRawValue) {
            Image(systemName: "rectangle.split.2x1")
                .tag(SpeecharaWorkspaceLayout.columns.rawValue)
            Image(systemName: "rectangle.split.1x2")
                .tag(SpeecharaWorkspaceLayout.rows.rawValue)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 68)
        .help("Switch transcript and translation layout")
    }

    private var resizableWorkspacePanels: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 6
            let dividerSize: CGFloat = 8
            let available = workspaceLayout == .columns ? proxy.size.width : proxy.size.height
            let minimumPanelSize: CGFloat = workspaceLayout == .columns ? 360 : 240
            let firstSize = max(minimumPanelSize, min(available - dividerSize - minimumPanelSize, available * workspaceSplitFraction))
            let secondSize = max(minimumPanelSize, available - dividerSize - firstSize)

            Group {
                if workspaceLayout == .columns {
                    HStack(alignment: .top, spacing: gap) {
                        transcriptColumn.frame(width: firstSize)
                        workspaceDivider(available: proxy.size.width)
                        translationColumn.frame(width: secondSize)
                    }
                } else {
                    VStack(spacing: gap) {
                        transcriptColumn.frame(height: firstSize)
                        workspaceDivider(available: proxy.size.height)
                        translationColumn.frame(height: secondSize)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(name: "speechara-workspace-split")
        }
    }

    private func workspaceDivider(available: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.secondary.opacity(0.22))
            .frame(
                width: workspaceLayout == .columns ? 3 : 28,
                height: workspaceLayout == .columns ? 28 : 3
            )
            .frame(
                width: workspaceLayout == .columns ? 8 : nil,
                height: workspaceLayout == .columns ? nil : 8
            )
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    (workspaceLayout == .columns ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(coordinateSpace: .named("speechara-workspace-split"))
                    .onChanged { value in
                        let position = workspaceLayout == .columns ? value.location.x : value.location.y
                        workspaceSplitFraction = max(0.25, min(0.75, position / max(1, available)))
                    }
            )
            .accessibilityLabel("Resize transcript and translation panels")
    }

    private var shouldShowMicrophoneOffWarning: Bool {
        viewModel.shouldShowMicrophoneOffWarning && !isMicrophoneOffWarningDismissed
    }

    private var heroSection: some View {
        SurfaceCard(accent: primaryActionTint.opacity(0.16)) {
            ViewThatFits(in: .horizontal) {
                fullToolbar
                compactToolbar
            }
        }
    }

    private var fullToolbar: some View {
        HStack(alignment: .center, spacing: 12) {
            if !isFocusModeEnabled {
                PrimaryActionButton(
                    title: primaryActionTitle,
                    subtitle: viewModel.hasActiveSession ? nil : SL("system audio"),
                    systemImage: primaryActionIcon,
                    tint: primaryActionTint,
                    action: handlePrimaryAction
                )
                .disabled(primaryActionDisabled)
                .opacity(primaryActionDisabled ? 0.55 : 1)

                MicrophoneControl(
                    viewModel: viewModel
                )

                if showsSessionToolbarControls {
                    settingsStrip
                }
            }

            if let activityText = viewModel.assistantActivityText {
                LiveStatusPill(
                    title: activityText,
                    systemImage: "sparkles",
                    tint: Color(red: 0.56, green: 0.35, blue: 0.88)
                )
            }

            Spacer(minLength: 12)

            ToolbarSecondaryButton(
                title: "New",
                systemImage: "plus.circle"
            ) {
                viewModel.startNewSession()
            }

            ToolbarSecondaryButton(
                title: isFocusModeEnabled ? "Exit" : "Focus",
                systemImage: isFocusModeEnabled ? "rectangle.compress.vertical" : "rectangle.expand.vertical",
                isActive: isFocusModeEnabled
            ) {
                isFocusModeEnabled.toggle()
            }
        }
    }

    private var compactToolbar: some View {
        HStack(alignment: .center, spacing: 10) {
            if !isFocusModeEnabled {
                PrimaryActionButton(
                    title: primaryActionTitle,
                    subtitle: nil,
                    systemImage: primaryActionIcon,
                    tint: primaryActionTint,
                    action: handlePrimaryAction
                )
                .disabled(primaryActionDisabled)
                .opacity(primaryActionDisabled ? 0.55 : 1)

                MicrophoneControl(
                    viewModel: viewModel
                )

                if showsSessionToolbarControls {
                    sessionSettingsMenu
                }
            }

            Spacer(minLength: 8)

            ToolbarSecondaryButton(
                title: "New",
                systemImage: "plus.circle"
            ) {
                viewModel.startNewSession()
            }

            ToolbarSecondaryButton(
                title: isFocusModeEnabled ? "Exit" : "Focus",
                systemImage: isFocusModeEnabled ? "rectangle.compress.vertical" : "rectangle.expand.vertical",
                isActive: isFocusModeEnabled
            ) {
                isFocusModeEnabled.toggle()
            }
        }
    }

    private var showsSessionToolbarControls: Bool {
        viewModel.status == .listening || viewModel.status == .stopped
    }

    private var savedAudioStrip: some View {
        HStack(spacing: 10) {
            Label(SL("Saved audio"), systemImage: "waveform")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(savedAudioInlineDescription)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(viewModel.lastRecordingDescription)

            if viewModel.canRevealLastRecording {
                Button {
                    viewModel.revealLastRecordingInFinder()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(SL("Show saved recording in Finder"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: ToolbarMetrics.controlHeight)
        .background(
            RoundedRectangle(cornerRadius: ToolbarMetrics.cornerRadius)
                .fill(Color.white.opacity(0.56))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ToolbarMetrics.cornerRadius)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        .frame(maxWidth: 340, alignment: .trailing)
    }

    private var savedAudioInlineDescription: String {
        guard let lastRecordingPath = viewModel.lastRecordingPath,
              !lastRecordingPath.isEmpty else {
            return viewModel.lastRecordingDescription
        }

        let fileName = URL(fileURLWithPath: lastRecordingPath).lastPathComponent
        return fileName.isEmpty ? viewModel.lastRecordingDescription : fileName
    }

    private var settingsStrip: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(SourceLanguageOption.allCases) { language in
                    Button(language.displayName) {
                        viewModel.selectedSourceLanguage = language
                    }
                }
            } label: {
                SettingStripPill(
                    title: "IN",
                    value: viewModel.selectedSourceLanguage.deepgramLanguageCode.uppercased(),
                    systemImage: "ear",
                    showsChevron: true
                )
                .help(SLF("Input: %@", viewModel.selectedSourceLanguage.displayName))
            }
            .menuStyle(.borderlessButton)

            Button {
                viewModel.isAudioRecordingEnabled.toggle()
            } label: {
                SettingStripPill(
                    title: "REC",
                    value: viewModel.isAudioRecordingEnabled ? "On" : "Off",
                    systemImage: "waveform",
                    tint: viewModel.isAudioRecordingEnabled ? Color(red: 0.10, green: 0.59, blue: 0.46) : .secondary
                )
                .help(viewModel.isAudioRecordingEnabled ? SL("Audio recording is enabled") : SL("Audio recording is disabled"))
            }
            .buttonStyle(.plain)

            Menu {
                Button(SL("Off")) {
                    viewModel.isTranslationEnabled = false
                }

                Divider()

                ForEach(viewModel.availableTranslationLanguages) { language in
                    Button(language.displayName) {
                        viewModel.isTranslationEnabled = true
                        viewModel.selectedTranslationLanguage = language
                    }
                }
            } label: {
                SettingStripPill(
                    title: nil,
                    value: nil,
                    systemImage: "translate",
                    tint: viewModel.isTranslationEnabled ? Color(red: 0.40, green: 0.44, blue: 0.92) : .secondary,
                    showsChevron: true
                )
                .help(viewModel.translationSummary)
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var sessionSettingsMenu: some View {
        Menu {
            Menu(SL("Input language")) {
                ForEach(SourceLanguageOption.allCases) { language in
                    Button {
                        viewModel.selectedSourceLanguage = language
                    } label: {
                        Label(
                            language.displayName,
                            systemImage: language == viewModel.selectedSourceLanguage ? "checkmark" : "ear"
                        )
                    }
                }
            }

            Menu(SL("Translation")) {
                Button {
                    viewModel.isTranslationEnabled = false
                } label: {
                    Label(SL("Off"), systemImage: viewModel.isTranslationEnabled ? "globe.slash" : "checkmark")
                }

                Divider()

                ForEach(viewModel.availableTranslationLanguages) { language in
                    Button {
                        viewModel.isTranslationEnabled = true
                        viewModel.selectedTranslationLanguage = language
                    } label: {
                        Label(
                            language.displayName,
                            systemImage: viewModel.isTranslationEnabled && language == viewModel.selectedTranslationLanguage ? "checkmark" : "globe"
                        )
                    }
                }
            }

            Button {
                viewModel.isAudioRecordingEnabled.toggle()
            } label: {
                Label(
                    viewModel.isAudioRecordingEnabled ? SL("Recording: On") : SL("Recording: Off"),
                    systemImage: viewModel.isAudioRecordingEnabled ? "waveform" : "waveform.slash"
                )
            }

            if viewModel.canRevealLastRecording {
                Divider()

                Button {
                    viewModel.revealLastRecordingInFinder()
                } label: {
                    Label(SL("Show saved recording in Finder"), systemImage: "folder")
                }
            }
        } label: {
            SettingStripPill(
                title: "Session",
                value: sessionSummaryCode,
                systemImage: "slider.horizontal.3",
                showsChevron: true
            )
        }
        .menuStyle(.borderlessButton)
        .help(SL("Session settings"))
    }

    private var sessionSummaryCode: String {
        let input = viewModel.selectedSourceLanguage.deepgramLanguageCode.uppercased()
        let translation = viewModel.isTranslationEnabled
            ? viewModel.selectedTranslationLanguage.languageCode.uppercased()
            : "Off"
        return "\(input) / \(translation)"
    }

    private var transcriptColumn: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Text(SL("Live transcript"))
                        .font(.title3.weight(.bold))
                        .help(SL("Editable during testing, with timestamped blocks."))

                    Spacer()

                    FontSizeControls(
                        canDecrease: viewModel.canDecreaseTranscriptFontSize,
                        canIncrease: viewModel.canIncreaseTranscriptFontSize,
                        onDecrease: viewModel.decreaseTranscriptFontSize,
                        onIncrease: viewModel.increaseTranscriptFontSize
                    )

                    Divider().frame(height: 18)
                    workspaceLayoutPicker
                    Divider().frame(height: 18)

                    SummaryButton(
                        title: viewModel.sourceSummaryButtonTitle,
                        isEnabled: viewModel.canSummarizeSource,
                        action: viewModel.summarizeSourceText
                    )

                    PanelActionButton(
                        title: viewModel.sourceProtocolButtonTitle,
                        isEnabled: viewModel.canGenerateSourceProtocol,
                        action: viewModel.generateSourceProtocol,
                        helpText: "Create a full structured meeting protocol from this transcript."
                    )

                    PanelActionButton(
                        title: viewModel.sourceAnswerButtonTitle,
                        isEnabled: viewModel.canSuggestSourceAnswer,
                        action: viewModel.suggestSourceAnswer,
                        helpText: "Draft a suggested reply to the latest question in this transcript.",
                        accentColor: Color(red: 0.22, green: 0.46, blue: 0.96)
                    )
                }

                if viewModel.isTranscriptSummaryVisible {
                    VSplitView {
                        historyPanel(
                            text: viewModel.subtitlesText,
                            entries: viewModel.transcriptEntries,
                            draftText: viewModel.liveSubtitlePreview,
                            fontSize: viewModel.transcriptFontSize,
                            isDialogueMode: true,
                            placeholder: viewModel.transcriptPlaceholderText
                        )
                        .frame(minHeight: 180)

                        ResultPanel(
                            title: viewModel.sourceSummaryPanelTitle,
                            contentText: viewModel.transcriptSummaryText,
                            errorMessage: viewModel.transcriptSummaryErrorMessage,
                            isLoading: viewModel.isTranscriptSummaryLoading,
                            copyAction: viewModel.copyTranscriptSummaryToPasteboard,
                            closeAction: viewModel.hideTranscriptSummary,
                            loadingText: "Summarizing transcript...",
                            emptyText: "No summary yet."
                        )
                        .frame(minHeight: 130)
                    }
                    .frame(maxHeight: .infinity)
                } else if viewModel.isTranscriptProtocolVisible {
                    VSplitView {
                        historyPanel(
                            text: viewModel.subtitlesText,
                            entries: viewModel.transcriptEntries,
                            draftText: viewModel.liveSubtitlePreview,
                            fontSize: viewModel.transcriptFontSize,
                            isDialogueMode: true,
                            placeholder: viewModel.transcriptPlaceholderText
                        )
                        .frame(minHeight: 180)

                        ResultPanel(
                            title: viewModel.sourceProtocolPanelTitle,
                            contentText: viewModel.transcriptProtocolText,
                            errorMessage: viewModel.transcriptProtocolErrorMessage,
                            isLoading: viewModel.isTranscriptProtocolLoading,
                            copyAction: viewModel.copyTranscriptProtocolToPasteboard,
                            closeAction: viewModel.hideTranscriptProtocol,
                            loadingText: "Building meeting protocol...",
                            emptyText: "No protocol yet."
                        )
                        .frame(minHeight: 130)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    historyPanel(
                        text: viewModel.subtitlesText,
                        entries: viewModel.transcriptEntries,
                        draftText: viewModel.liveSubtitlePreview,
                        fontSize: viewModel.transcriptFontSize,
                        isDialogueMode: true,
                        placeholder: viewModel.transcriptPlaceholderText
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }

    private var assistantColumn: some View {
        SurfaceCard(accent: Color.orange.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Label(SL("Suggested response"), systemImage: "sparkles")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color(red: 0.92, green: 0.64, blue: 0.12))
                        .help(SL("Looks at the latest transcript and suggests a natural response you can say on the call."))

                    Spacer()

                    clearSubtitlesButton

                    if viewModel.isTranscriptAnswerVisible || !viewModel.transcriptAnswerText.isEmpty || viewModel.isTranscriptAnswerLoading {
                        Button("Copy", action: viewModel.copyTranscriptAnswerToPasteboard)
                            .buttonStyle(.borderless)
                            .disabled(viewModel.transcriptAnswerText.isEmpty || viewModel.isTranscriptAnswerLoading)

                        Button(action: viewModel.hideTranscriptAnswer) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                SmartAssistantPanel(
                    contentText: viewModel.transcriptAnswerText,
                    errorMessage: viewModel.transcriptAnswerErrorMessage,
                    isLoading: viewModel.isTranscriptAnswerLoading,
                    loadingText: "Suggesting a natural answer...",
                    emptyText: viewModel.sourceAnswerPlaceholderText
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var translationColumn: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(viewModel.translationPanelTitle)
                        .font(.title3.weight(.bold))
                        .help(SL("The translation stays secondary to the live transcript and fills in only when final text is ready."))

                    Spacer()

                    FontSizeControls(
                        canDecrease: viewModel.canDecreaseTranslationFontSize,
                        canIncrease: viewModel.canIncreaseTranslationFontSize,
                        onDecrease: viewModel.decreaseTranslationFontSize,
                        onIncrease: viewModel.increaseTranslationFontSize
                    )

                    Divider().frame(height: 18)

                    SummaryButton(
                        title: viewModel.translationSummaryButtonTitle,
                        isEnabled: viewModel.canSummarizeTranslation,
                        action: viewModel.summarizeTranslatedText
                    )

                    PanelActionButton(
                        title: viewModel.translationProtocolButtonTitle,
                        isEnabled: viewModel.canGenerateTranslationProtocol,
                        action: viewModel.generateTranslatedProtocol,
                        helpText: "Create a full structured meeting protocol in the selected translation language."
                    )

                }

                if viewModel.isTranslationSummaryVisible {
                    VSplitView {
                        historyPanel(
                            text: viewModel.translatedText,
                            entries: viewModel.translationEntries,
                            draftText: viewModel.liveTranslationPreview,
                            fontSize: viewModel.translationFontSize,
                            isDialogueMode: true,
                            placeholder: viewModel.translationPlaceholderText
                        )
                        .frame(minHeight: 180)

                        ResultPanel(
                            title: viewModel.translationSummaryPanelTitle,
                            contentText: viewModel.translationSummaryText,
                            errorMessage: viewModel.translationSummaryErrorMessage,
                            isLoading: viewModel.isTranslationSummaryLoading,
                            copyAction: viewModel.copyTranslationSummaryToPasteboard,
                            closeAction: viewModel.hideTranslationSummary,
                            loadingText: "Summarizing translation...",
                            emptyText: "No summary yet."
                        )
                        .frame(minHeight: 130)
                    }
                    .frame(maxHeight: .infinity)
                } else if viewModel.isTranslationProtocolVisible {
                    VSplitView {
                        historyPanel(
                            text: viewModel.translatedText,
                            entries: viewModel.translationEntries,
                            draftText: viewModel.liveTranslationPreview,
                            fontSize: viewModel.translationFontSize,
                            isDialogueMode: true,
                            placeholder: viewModel.translationPlaceholderText
                        )
                        .frame(minHeight: 180)

                        ResultPanel(
                            title: viewModel.translationProtocolPanelTitle,
                            contentText: viewModel.translationProtocolText,
                            errorMessage: viewModel.translationProtocolErrorMessage,
                            isLoading: viewModel.isTranslationProtocolLoading,
                            copyAction: viewModel.copyTranslationProtocolToPasteboard,
                            closeAction: viewModel.hideTranslationProtocol,
                            loadingText: "Building meeting protocol...",
                            emptyText: "No protocol yet."
                        )
                        .frame(minHeight: 130)
                    }
                    .frame(maxHeight: .infinity)
                } else if viewModel.isTranslationAnswerVisible {
                    VSplitView {
                        historyPanel(
                            text: viewModel.translatedText,
                            entries: viewModel.translationEntries,
                            draftText: viewModel.liveTranslationPreview,
                            fontSize: viewModel.translationFontSize,
                            isDialogueMode: true,
                            placeholder: viewModel.translationPlaceholderText
                        )
                        .frame(minHeight: 180)

                        ResultPanel(
                            title: viewModel.translationAnswerPanelTitle,
                            contentText: viewModel.translationAnswerText,
                            errorMessage: viewModel.translationAnswerErrorMessage,
                            isLoading: viewModel.isTranslationAnswerLoading,
                            copyAction: viewModel.copyTranslationAnswerToPasteboard,
                            closeAction: viewModel.hideTranslationAnswer,
                            loadingText: "Suggesting a translated answer...",
                            emptyText: "No answer suggestion yet."
                        )
                        .frame(minHeight: 130)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    historyPanel(
                        text: viewModel.translatedText,
                        entries: viewModel.translationEntries,
                        draftText: viewModel.liveTranslationPreview,
                        fontSize: viewModel.translationFontSize,
                        isDialogueMode: true,
                        placeholder: viewModel.translationPlaceholderText
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }

    private var clearSubtitlesButton: some View {
        Button(SL("Clear subtitles")) {
            viewModel.startNewSession()
        }
        .buttonStyle(.bordered)
        .disabled(
            viewModel.subtitlesText.isEmpty
                && viewModel.translatedText.isEmpty
                && viewModel.liveSubtitlePreview.isEmpty
        )
    }

    private var primaryActionTitle: String {
        viewModel.hasActiveSession ? SL("Stop Listening") : SL("Start Listening")
    }

    private var primaryActionIcon: String {
        viewModel.hasActiveSession ? "stop.fill" : "play.fill"
    }

    private var primaryActionTint: Color {
        viewModel.hasActiveSession
            ? Color(red: 0.84, green: 0.16, blue: 0.17)
            : Color(red: 0.12, green: 0.70, blue: 0.39)
    }

    private var primaryActionDisabled: Bool {
        viewModel.hasActiveSession
            ? viewModel.isBusy || viewModel.isMicrophoneBusy
            : authStore.isRestoringSession || !authStore.isAuthenticated || !viewModel.canStartSystemListening
    }

    private func handlePrimaryAction() {
        if viewModel.hasActiveSession {
            viewModel.stopActiveSession()
            return
        }

        prepareListeningSetupAfterAuthRefresh()
    }

    private func prepareListeningSetupAfterAuthRefresh() {
        Task { @MainActor in
            do {
                try await authStore.ensureActiveSession()
                isListeningSetupPresented = true
            } catch {
                viewModel.showErrorMessage(authStore.errorMessage ?? error.localizedDescription)
            }
        }
    }

    private func startListeningAfterAuthRefresh() {
        Task { @MainActor in
            do {
                try await authStore.ensureActiveSession()
                viewModel.promptAndStartListening(includeMicrophone: viewModel.startsWithMicrophoneEnabled)
            } catch {
                viewModel.showErrorMessage(authStore.errorMessage ?? error.localizedDescription)
            }
        }
    }

    private var editableTranscriptBinding: Binding<String> {
        Binding(
            get: { viewModel.subtitlesText },
            set: { viewModel.updateTranscriptText($0) }
        )
    }

    private func historyPanel(
        text: Binding<String>,
        draftText: String,
        fontSize: CGFloat,
        placeholder: String
    ) -> some View {
        EditableTextPanel(
            text: text,
            draftText: draftText,
            fontSize: fontSize,
            placeholder: placeholder
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func historyPanel(
        text: String,
        entries: [DialogueEntry],
        draftText: String,
        fontSize: CGFloat,
        isDialogueMode: Bool,
        placeholder: String
    ) -> some View {
        Group {
            if entries.isEmpty
                && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyPanelPlaceholder(text: placeholder)
            } else if isDialogueMode {
                DialogueHistoryPanel(
                    entries: entries,
                    fontSize: fontSize,
                    speakerLabel: viewModel.speakerDisplayLabel(for:),
                    draftText: draftText
                )
            } else {
                ReadOnlyTextPanel(text: text, draftText: draftText, fontSize: fontSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct EditableTextPanel: View {
    @Binding var text: String
    let draftText: String
    let fontSize: CGFloat
    let placeholder: String

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty && draftText.isEmpty {
                    Text(placeholder)
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                AutoScrollingEditableTextView(
                    text: $text,
                    draftText: "",
                    fontSize: fontSize
                )
                    .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LiveDraftStrip(text: draftText, fontSize: fontSize)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.05))
        )
    }
}

private struct AutoScrollingEditableTextView: NSViewRepresentable {
    @Binding var text: String
    let draftText: String
    let fontSize: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        context.coordinator.applyDisplayedText(to: textView)

        DispatchQueue.main.async {
            context.coordinator.scrollToBottom(textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = nsView.documentView as? NSTextView else {
            return
        }

        if textView.string != context.coordinator.displayedText {
            context.coordinator.applyDisplayedText(to: textView)
            DispatchQueue.main.async {
                context.coordinator.scrollToBottom(textView)
            }
        }

        let desiredFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.font != desiredFont {
            textView.font = desiredFont
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoScrollingEditableTextView
        var isPerformingProgrammaticUpdate = false

        init(parent: AutoScrollingEditableTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isPerformingProgrammaticUpdate,
                  let textView = notification.object as? NSTextView else {
                return
            }

            parent.text = editableText(from: textView.string)
            scrollToBottom(textView)
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let protectedRange = protectedDraftRange(in: textView.string) else {
                return true
            }

            if affectedCharRange.length == 0 {
                return affectedCharRange.location < protectedRange.location
            }

            return NSIntersectionRange(affectedCharRange, protectedRange).length == 0
        }

        var displayedText: String {
            let cleanDraft = parent.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanDraft.isEmpty else {
                return parent.text
            }

            return parent.text.isEmpty ? cleanDraft : "\(parent.text)\n\(cleanDraft)"
        }

        func applyDisplayedText(to textView: NSTextView) {
            let displayText = displayedText
            let attributedText = NSMutableAttributedString(
                string: displayText,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular),
                    .foregroundColor: NSColor.labelColor,
                ]
            )

            if let draftRange = protectedDraftRange(in: displayText) {
                attributedText.addAttribute(
                    .foregroundColor,
                    value: NSColor.secondaryLabelColor,
                    range: draftRange
                )
            }

            isPerformingProgrammaticUpdate = true
            textView.textStorage?.setAttributedString(attributedText)
            isPerformingProgrammaticUpdate = false
        }

        private func editableText(from displayedText: String) -> String {
            guard let protectedRange = protectedDraftRange(in: displayedText) else {
                return displayedText
            }

            return (displayedText as NSString).substring(to: protectedRange.location)
        }

        private func protectedDraftRange(in displayedText: String) -> NSRange? {
            let cleanDraft = parent.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanDraft.isEmpty, displayedText.hasSuffix(cleanDraft) else {
                return nil
            }

            let displayLength = (displayedText as NSString).length
            let draftLength = (cleanDraft as NSString).length
            var location = displayLength - draftLength
            if location > 0,
               (displayedText as NSString).substring(with: NSRange(location: location - 1, length: 1)) == "\n" {
                location -= 1
            }
            return NSRange(location: location, length: displayLength - location)
        }

        func scrollToBottom(_ textView: NSTextView) {
            let endRange = NSRange(location: textView.string.utf16.count, length: 0)
            textView.scrollRangeToVisible(endRange)
        }
    }
}

private struct ReadOnlyTextPanel: View {
    let text: String
    let draftText: String
    let fontSize: CGFloat
    @State private var scrollWorkItem: DispatchWorkItem?
    private let bottomAnchor = "read-only-bottom-anchor"

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(text.isEmpty ? " " : text)
                        .foregroundColor(.primary)
                        .font(.system(size: fontSize, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .onAppear {
                    scrollToBottom(using: proxy)
                }
                .onChange(of: text) { _ in
                    scrollToBottom(using: proxy)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LiveDraftStrip(text: draftText, fontSize: fontSize)
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        scrollWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
        scrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
    }
}

private struct EmptyPanelPlaceholder: View {
    let text: String

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Text(SL(text))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LiveDraftStrip: View {
    let text: String
    let fontSize: CGFloat

    private var cleanText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        if !cleanText.isEmpty {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.ultraThinMaterial)

                Text(cleanText)
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }
            .frame(height: max(42, fontSize * 2.55))
            .overlay(alignment: .top) {
                Divider().opacity(0.55)
            }
            .accessibilityLabel(SL("Live draft"))
            .accessibilityValue(cleanText)
        }
    }
}

private struct DialogueHistoryPanel: View {
    let entries: [DialogueEntry]
    let fontSize: CGFloat
    let speakerLabel: (Int) -> String
    let draftText: String
    @State private var scrollWorkItem: DispatchWorkItem?
    private let bottomAnchor = "dialogue-bottom-anchor"
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(entries) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                TimestampBadge(label: Self.timestampFormatter.string(from: entry.timestamp))

                                if let speakerNumber = entry.speakerNumber {
                                    SpeakerBadge(label: speakerLabel(speakerNumber))
                                }

                                Text(entry.text)
                                    .font(.system(size: fontSize, design: .monospaced))
                                    .foregroundStyle(entry.isDraft ? Color.secondary : Color.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
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

            LiveDraftStrip(text: draftText, fontSize: fontSize)
        }
    }

    private var scrollSignature: String {
        guard let lastEntry = entries.last else {
            return "empty"
        }

        return "\(entries.count)-\(lastEntry.id.uuidString)-\(lastEntry.text.count)-\(lastEntry.isDraft)"
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        scrollWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
        scrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
    }

}

private struct SpeakerBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.08))
            )
            .foregroundStyle(.secondary)
    }
}

private struct TimestampBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.10))
            )
            .foregroundStyle(.secondary)
    }
}

private struct MicrophoneOffWarningBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(red: 0.86, green: 0.43, blue: 0.02))
                .frame(width: 24, height: 24)

            Text(SL("Microphone is off. Your replies will not be included in the transcript."))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.58, green: 0.28, blue: 0.02))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.70, green: 0.34, blue: 0.04).opacity(0.72))
            }
            .buttonStyle(.plain)
            .help(SL("Hide warning"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 1.00, green: 0.95, blue: 0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(red: 0.90, green: 0.48, blue: 0.08).opacity(0.32), lineWidth: 1)
        )
    }
}

private struct FontSizeControls: View {
    let canDecrease: Bool
    let canIncrease: Bool
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onDecrease) {
                Image(systemName: "textformat.size.smaller")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!canDecrease)
            .help(SL("Decrease text size"))

            Button(action: onIncrease) {
                Image(systemName: "textformat.size.larger")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!canIncrease)
            .help(SL("Increase text size"))
        }
        .foregroundStyle(.secondary)
    }
}

private struct PanelActionButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void
    let helpText: String
    var accentColor: Color? = nil

    @ViewBuilder
    var body: some View {
        if let accentColor {
            Button(SL(title), action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(accentColor)
                .disabled(!isEnabled)
                .help(SL(helpText))
        } else {
            Button(SL(title), action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isEnabled)
                .help(SL(helpText))
        }
    }
}

private struct SummaryButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        PanelActionButton(
            title: title,
            isEnabled: isEnabled,
            action: action,
            helpText: "Generate a summary for the text in this panel."
        )
    }
}

private struct ResultPanel: View {
    let title: String
    let contentText: String
    let errorMessage: String?
    let isLoading: Bool
    let copyAction: () -> Void
    let closeAction: () -> Void
    let loadingText: String
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(SL(title))
                    .font(.headline)

                Spacer()

                Button(SL("Copy"), action: copyAction)
                    .buttonStyle(.borderless)
                    .disabled(contentText.isEmpty || isLoading)

                Button(action: closeAction) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(SL("Hide panel"))
            }

            Group {
                if isLoading {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView()
                        Text(SL(loadingText))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
                } else if let errorMessage {
                    ScrollView {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                } else if contentText.isEmpty {
                    EmptyPanelPlaceholder(text: emptyText)
                } else {
                    ScrollView {
                        Text(contentText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
        }
    }
}

private struct SmartAssistantPanel: View {
    let contentText: String
    let errorMessage: String?
    let isLoading: Bool
    let loadingText: String
    let emptyText: String

    var body: some View {
        Group {
            if isLoading {
                VStack(alignment: .leading, spacing: 12) {
                    ProgressView()
                    Text(SL(loadingText))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            } else if contentText.isEmpty {
                EmptyPanelPlaceholder(text: emptyText)
            } else {
                ScrollView {
                    Text(contentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct SessionBadge: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(SL(text), systemImage: systemImage)
            .font(.system(.caption, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
            )
            .foregroundStyle(.secondary)
    }
}

private struct LiveStatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(SL(title), systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .frame(height: ToolbarMetrics.badgeHeight)
            .background(
                RoundedRectangle(cornerRadius: ToolbarMetrics.badgeCornerRadius)
                    .fill(tint.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ToolbarMetrics.badgeCornerRadius)
                    .stroke(tint.opacity(0.10), lineWidth: 1)
            )
            .foregroundStyle(tint)
    }
}

private struct SettingStripPill: View {
    let title: String?
    let value: String?
    let systemImage: String
    var tint: Color = .secondary
    var showsChevron = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: title == nil && value == nil ? 14 : 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)

            if let title, let value {
                VStack(alignment: .leading, spacing: 1) {
                    Text(SL(title))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .foregroundStyle(.secondary)
                    Text(SL(value))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }

            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minWidth: title == nil && value == nil ? 52 : nil)
        .frame(height: ToolbarMetrics.controlHeight)
        .background(
            RoundedRectangle(cornerRadius: ToolbarMetrics.cornerRadius)
                .fill(Color.white.opacity(0.56))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ToolbarMetrics.cornerRadius)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}

private struct ToolbarSecondaryButton: View {
    let title: String
    let systemImage: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))

                Text(SL(title))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .padding(.horizontal, 14)
            .frame(height: ToolbarMetrics.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: ToolbarMetrics.cornerRadius)
                    .fill(isActive ? Color.black.opacity(0.08) : Color.white.opacity(0.58))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ToolbarMetrics.cornerRadius)
                    .stroke(Color.black.opacity(isActive ? 0.10 : 0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct InlineStatusMessage: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(SL(text))
                .font(.subheadline)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(tint.opacity(0.10))
        )
    }
}

private struct PrimaryActionButton: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .bold))

                VStack(alignment: .leading, spacing: 1) {
                    Text(SL(title))
                        .font(.system(size: 17, weight: .bold, design: .rounded))

                    if let subtitle {
                        Text(SL(subtitle))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                .multilineTextAlignment(.leading)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .frame(height: ToolbarMetrics.primaryHeight)
            .background(
                RoundedRectangle(cornerRadius: ToolbarMetrics.primaryCornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: tint.opacity(0.28), radius: 16, x: 0, y: 8)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SurfaceCard<Content: View>: View {
    let accent: Color?
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
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 18, x: 0, y: 10)
        .overlay(alignment: .topLeading) {
            if let accent {
                RoundedRectangle(cornerRadius: 24)
                    .fill(accent)
                    .blur(radius: 40)
                    .mask(
                        RoundedRectangle(cornerRadius: 24)
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.12, green: 0.13, blue: 0.15)
        }

        return Color.white.opacity(0.96)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.26) : Color.black.opacity(0.08)
    }
}

private enum ToolbarMetrics {
    static let primaryHeight: CGFloat = 54
    static let primaryCornerRadius: CGFloat = 20
    static let controlHeight: CGFloat = 46
    static let cornerRadius: CGFloat = 16
    static let badgeHeight: CGFloat = 32
    static let badgeCornerRadius: CGFloat = 12
}

private struct MicrophoneControl: View {
    @ObservedObject var viewModel: SubtitleViewModel

    var body: some View {
        Button {
            viewModel.toggleMicrophoneCapture()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isMicrophoneListening ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 14, weight: .semibold))

                Text(SLF("Mic: %@", viewModel.selectedMicrophoneName))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                MicrophoneLevelBars(
                    level: viewModel.microphoneLevel,
                    isActive: viewModel.isMicrophoneListening || viewModel.isMicrophoneTesting
                )
            }
            .foregroundStyle(viewModel.isMicrophoneListening ? .white : .primary)
            .padding(.horizontal, 14)
            .frame(height: ToolbarMetrics.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: ToolbarMetrics.cornerRadius)
                    .fill(
                        viewModel.isMicrophoneListening
                            ? Color(red: 0.84, green: 0.16, blue: 0.17)
                            : Color.white.opacity(0.58)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: ToolbarMetrics.cornerRadius)
                    .stroke(
                        viewModel.isMicrophoneListening
                            ? Color.red.opacity(0.18)
                            : Color.black.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .help(
            viewModel.isMicrophoneListening
                ? SL("Turn microphone off. Right-click to choose a microphone.")
                : SL("Turn microphone on. Right-click to choose a microphone.")
        )
        .disabled(viewModel.isBusy || viewModel.isMicrophoneBusy)
        .contextMenu {
            if viewModel.hasAvailableMicrophones {
                ForEach(viewModel.availableMicrophones) { device in
                    Button {
                        viewModel.selectMicrophone(device.id)
                    } label: {
                        if device.id == viewModel.selectedMicrophoneID {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                    .disabled(device.id == viewModel.selectedMicrophoneID)
                }
            } else {
                Button(SL("No microphone devices available")) {}
                    .disabled(true)
            }

            Divider()

            Button(viewModel.microphoneTestButtonTitle) {
                viewModel.toggleMicrophoneTest()
            }
            .disabled(viewModel.isBusy || viewModel.isMicrophoneBusy || !viewModel.hasAvailableMicrophones)
        }
    }
}

private struct MicrophoneLevelBars: View {
    let level: Double
    let isActive: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0 ..< 4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 4, height: 8 + CGFloat(index * 4))
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }

    private func barColor(for index: Int) -> Color {
        guard isActive else {
            return Color.secondary.opacity(0.25)
        }

        let threshold = Double(index + 1) / 4.0
        return level >= threshold
            ? Color(red: 0.20, green: 0.78, blue: 0.41)
            : Color.white.opacity(0.35)
    }
}

private struct ListeningSetupSheet: View {
    @ObservedObject var viewModel: SubtitleViewModel
    let onStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let sheetWidth: CGFloat = 620
    private let actionButtonSize: CGFloat = 120

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top, spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.92, green: 0.24, blue: 0.18),
                                                Color(red: 0.73, green: 0.11, blue: 0.10),
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 54, height: 54)

                                Image(systemName: "captions.bubble.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(SL("Start a Listening Session"))
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)

                                Text(SL("Choose the input language, decide whether to mix in your microphone, save the session as M4A, and turn translation on only when you need it."))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()
                        }

                        VStack(spacing: 12) {
                            ListeningSetupCard(
                                iconName: "ear.fill",
                                accentColor: Color(red: 0.16, green: 0.42, blue: 0.87),
                                title: "Listening language",
                                subtitle: "Speechara will transcribe the session using this source language."
                            ) {
                                Picker("", selection: $viewModel.selectedSourceLanguage) {
                                    ForEach(SourceLanguageOption.allCases) { language in
                                        Text(language.displayName).tag(language)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 140)
                            }

                            ListeningSetupCard(
                                iconName: "mic.fill",
                                accentColor: Color(red: 0.79, green: 0.23, blue: 0.28),
                                title: "Microphone mix-in",
                                subtitle: "Add your own voice through the selected input device."
                            ) {
                                VStack(alignment: .trailing, spacing: 10) {
                                    Toggle("", isOn: $viewModel.startsWithMicrophoneEnabled)
                                        .labelsHidden()
                                        .toggleStyle(.switch)

                                    Menu {
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
                                            }
                                        } else {
                                            Button(SL("No microphone devices available")) {}
                                                .disabled(true)
                                        }
                                    } label: {
                                        Label(viewModel.selectedMicrophoneName, systemImage: "mic.fill")
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.78)
                                    }
                                    .frame(width: 190)
                                    .disabled(!viewModel.startsWithMicrophoneEnabled)
                                    .opacity(viewModel.startsWithMicrophoneEnabled ? 1 : 0.45)
                                }
                            }

                            ListeningSetupCard(
                                iconName: "waveform",
                                accentColor: Color(red: 0.10, green: 0.59, blue: 0.46),
                                title: "Save full M4A recording",
                                subtitle: "Store the entire captured session locally when you stop listening."
                            ) {
                                Toggle("", isOn: $viewModel.isAudioRecordingEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }

                            ListeningSetupCard(
                                iconName: "globe",
                                accentColor: Color(red: 0.86, green: 0.48, blue: 0.14),
                                title: "Live translation",
                                subtitle: "Speechara will translate only final transcript chunks into the selected target language."
                            ) {
                                VStack(alignment: .trailing, spacing: 10) {
                                    Toggle("", isOn: $viewModel.isTranslationEnabled)
                                        .labelsHidden()
                                        .toggleStyle(.switch)

                                    Picker("", selection: $viewModel.selectedTranslationLanguage) {
                                    ForEach(viewModel.availableTranslationLanguages) { language in
                                        Text(language.displayName).tag(language)
                                    }
                                }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 140)
                                    .disabled(!viewModel.isTranslationEnabled)
                                    .opacity(viewModel.isTranslationEnabled ? 1 : 0.45)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .bottom) {
                    Button(SL("Cancel")) {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                    Spacer(minLength: 24)

                    Button {
                        onStart()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "record.circle.fill")
                                .font(.system(size: 40, weight: .medium))

                            Text(SL("Start Listening"))
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .padding(.horizontal, 10)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.white)
                        .frame(width: actionButtonSize, height: actionButtonSize)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.93, green: 0.18, blue: 0.16),
                                            Color(red: 0.70, green: 0.08, blue: 0.12),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color.red.opacity(0.22), radius: 18, x: 0, y: 10)
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.isBusy)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .frame(
                minWidth: sheetWidth,
                idealWidth: sheetWidth,
                maxWidth: sheetWidth,
                minHeight: 700,
                idealHeight: 732,
                maxHeight: 760,
                alignment: .top
            )
        }
    }

    private var backgroundGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.12, blue: 0.14),
                    Color(red: 0.09, green: 0.13, blue: 0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.97, blue: 0.95),
                Color(red: 0.94, green: 0.97, blue: 1.00),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct ListeningSetupCard<Content: View>: View {
    let iconName: String
    let accentColor: Color
    let title: String
    let subtitle: String
    let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(
        iconName: String,
        accentColor: Color,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.iconName = iconName
        self.accentColor = accentColor
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)

                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(SL(title))
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(SL(subtitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 20)

            content
                .frame(minWidth: 180, alignment: .trailing)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(cardBorderColor, lineWidth: 1)
        )
    }

    private var cardBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.15, green: 0.16, blue: 0.18).opacity(0.96)
        }

        return Color.white.opacity(0.88)
    }

    private var cardBorderColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.08)
        }

        return Color.black.opacity(0.06)
    }
}
