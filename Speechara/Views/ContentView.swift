import AppKit
import SwiftUI

private enum SpeecharaWorkspaceLayout: String {
    case columns
    case rows
}

private enum DialoguePanelKind: String, Equatable {
    case transcript
    case translation
}

private struct DialogueScrollTarget: Equatable {
    let entryID: UUID
    let source: DialoguePanelKind
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
    @State private var hoveredDialogueEntryID: UUID?
    @State private var dialogueScrollTarget: DialogueScrollTarget?
    @State private var copiedPanel: DialoguePanelKind?

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
        .frame(minWidth: minimumWorkspaceWidth, minHeight: 760)
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
            SpeakingNotesStore.shared.configure(userID: authStore.currentUser?.id)
            if let userID = authStore.currentUser?.id,
               !SpeakingNotesStore.shared.windowState.hidden {
                SpeakingNotesWindowController.shared.show(for: userID)
            }
        }
        .onChange(of: authStore.currentUser?.id) { userID in
            SpeakingNotesStore.shared.configure(userID: userID)
            if let userID, !SpeakingNotesStore.shared.windowState.hidden {
                SpeakingNotesWindowController.shared.show(for: userID)
            } else if userID == nil {
                SpeakingNotesWindowController.shared.hideForSignOut()
            }
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

    private var minimumWorkspaceWidth: CGFloat {
        // Columns need room for two readable 360 pt panels, the splitter and
        // outer padding. Rows can safely use a substantially narrower window.
        workspaceLayout == .columns ? 800 : 620
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
                if usesScrollableRowsWorkspace {
                    ScrollView {
                        VStack(spacing: gap) {
                            transcriptColumn.frame(height: firstSize)
                            workspaceDivider(available: proxy.size.height)
                            translationColumn.frame(height: secondSize)
                            detachedSummaryPanels
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.bottom, 2)
                    }
                } else if workspaceLayout == .columns {
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

    private var usesScrollableRowsWorkspace: Bool {
        workspaceLayout == .rows
            && (viewModel.isTranscriptSummaryVisible || viewModel.isTranslationSummaryVisible)
    }

    @ViewBuilder
    private var detachedSummaryPanels: some View {
        if viewModel.isTranscriptSummaryVisible {
            detachedSummaryPanel(
                title: viewModel.sourceSummaryPanelTitle,
                contentText: viewModel.transcriptSummaryText,
                errorMessage: viewModel.transcriptSummaryErrorMessage,
                isLoading: viewModel.isTranscriptSummaryLoading,
                contentFontSize: viewModel.transcriptFontSize,
                copyAction: viewModel.copyTranscriptSummaryToPasteboard,
                closeAction: viewModel.hideTranscriptSummary,
                loadingText: "Summarizing transcript..."
            )
        }

        if viewModel.isTranslationSummaryVisible {
            detachedSummaryPanel(
                title: viewModel.translationSummaryPanelTitle,
                contentText: viewModel.translationSummaryText,
                errorMessage: viewModel.translationSummaryErrorMessage,
                isLoading: viewModel.isTranslationSummaryLoading,
                contentFontSize: viewModel.translationFontSize,
                copyAction: viewModel.copyTranslationSummaryToPasteboard,
                closeAction: viewModel.hideTranslationSummary,
                loadingText: "Summarizing translation..."
            )
        }
    }

    private func detachedSummaryPanel(
        title: String,
        contentText: String,
        errorMessage: String?,
        isLoading: Bool,
        contentFontSize: CGFloat,
        copyAction: @escaping () -> Void,
        closeAction: @escaping () -> Void,
        loadingText: String
    ) -> some View {
        SurfaceCard(isElevated: false) {
            ResultPanel(
                title: title,
                contentText: contentText,
                errorMessage: errorMessage,
                isLoading: isLoading,
                contentFontSize: contentFontSize,
                copyAction: copyAction,
                closeAction: closeAction,
                loadingText: loadingText,
                emptyText: "No summary yet.",
                usesInternalScroll: false
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: 180)
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
        SurfaceCard(accent: primaryActionTint.opacity(0.16), contentPadding: 12) {
            ViewThatFits(in: .horizontal) {
                fullToolbar
                compactToolbar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var fullToolbar: some View {
        HStack(alignment: .center, spacing: 12) {
            if !viewModel.hasActiveSession {
                PrimaryActionButton(
                    title: primaryActionTitle,
                    subtitle: SL("system audio"),
                    systemImage: primaryActionIcon,
                    tint: primaryActionTint,
                    action: handlePrimaryAction
                )
                .disabled(primaryActionDisabled)
                .opacity(primaryActionDisabled ? 0.55 : 1)
            } else {
                if !isFocusModeEnabled {
                    PrimaryActionButton(
                        title: primaryActionTitle,
                        subtitle: systemAudioStatusText,
                        systemImage: primaryActionIcon,
                        tint: primaryActionTint,
                        audioLevel: viewModel.systemAudioLevel,
                        isAudioLevelActive: viewModel.isSystemAudioListening,
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
            }

            Spacer(minLength: 12)

            ToolbarSecondaryButton(
                title: "Speaking notes",
                systemImage: "square.and.pencil"
            ) {
                SpeakingNotesWindowController.shared.show(for: authStore.currentUser?.id)
            }

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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactToolbar: some View {
        HStack(alignment: .center, spacing: 10) {
            if !viewModel.hasActiveSession {
                PrimaryActionButton(
                    title: primaryActionTitle,
                    subtitle: nil,
                    systemImage: primaryActionIcon,
                    tint: primaryActionTint,
                    action: handlePrimaryAction
                )
                .disabled(primaryActionDisabled)
                .opacity(primaryActionDisabled ? 0.55 : 1)
            } else {
                if !isFocusModeEnabled {
                    PrimaryActionButton(
                        title: primaryActionTitle,
                        subtitle: nil,
                        systemImage: primaryActionIcon,
                        tint: primaryActionTint,
                        audioLevel: viewModel.systemAudioLevel,
                        isAudioLevelActive: viewModel.isSystemAudioListening,
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
            }

            Spacer(minLength: 8)

            ToolbarSecondaryButton(
                title: "Speaking notes",
                systemImage: "square.and.pencil",
                showsTitle: false
            ) {
                SpeakingNotesWindowController.shared.show(for: authStore.currentUser?.id)
            }

            ToolbarSecondaryButton(
                title: "New",
                systemImage: "plus.circle",
                showsTitle: false
            ) {
                viewModel.startNewSession()
            }

            ToolbarSecondaryButton(
                title: isFocusModeEnabled ? "Exit" : "Focus",
                systemImage: isFocusModeEnabled ? "rectangle.compress.vertical" : "rectangle.expand.vertical",
                isActive: isFocusModeEnabled,
                showsTitle: false
            ) {
                isFocusModeEnabled.toggle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        Button {
            viewModel.toggleAudioRecording()
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
        .disabled(viewModel.isBusy)
    }

    private var transcriptColumn: some View {
        SurfaceCard(contentPadding: 12, isElevated: false) {
            VStack(alignment: .leading, spacing: 12) {
                transcriptPanelHeader

                Divider()
                    .opacity(0.65)

                if viewModel.isTranscriptSummaryVisible && !usesScrollableRowsWorkspace {
                    VSplitView {
                        historyPanel(
                            panelKind: .transcript,
                            text: viewModel.subtitlesText,
                            entries: viewModel.transcriptEntries,
                            draftText: viewModel.liveSubtitlePreview,
                            draftTimestamp: viewModel.liveUtteranceTimestamp,
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
                            contentFontSize: viewModel.transcriptFontSize,
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
                            panelKind: .transcript,
                            text: viewModel.subtitlesText,
                            entries: viewModel.transcriptEntries,
                            draftText: viewModel.liveSubtitlePreview,
                            draftTimestamp: viewModel.liveUtteranceTimestamp,
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
                            contentFontSize: viewModel.transcriptFontSize,
                            copyAction: viewModel.copyTranscriptProtocolToPasteboard,
                            closeAction: viewModel.hideTranscriptProtocol,
                            loadingText: "Building meeting notes...",
                            emptyText: "No meeting notes yet."
                        )
                        .frame(minHeight: 130)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    historyPanel(
                        panelKind: .transcript,
                        text: viewModel.subtitlesText,
                        entries: viewModel.transcriptEntries,
                        draftText: viewModel.liveSubtitlePreview,
                        draftTimestamp: viewModel.liveUtteranceTimestamp,
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
        SurfaceCard(accent: Color.orange.opacity(0.18), isElevated: false) {
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

                Divider()
                    .opacity(0.65)

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
        SurfaceCard(contentPadding: 12, isElevated: false) {
            VStack(alignment: .leading, spacing: 12) {
                translationPanelHeader

                Divider()
                    .opacity(0.65)

                if viewModel.isTranslationSummaryVisible && !usesScrollableRowsWorkspace {
                    VSplitView {
                        historyPanel(
                            panelKind: .translation,
                            text: viewModel.translatedText,
                            entries: viewModel.translationEntries,
                            draftText: viewModel.liveTranslationPreview,
                            draftTimestamp: viewModel.liveUtteranceTimestamp,
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
                            contentFontSize: viewModel.translationFontSize,
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
                            panelKind: .translation,
                            text: viewModel.translatedText,
                            entries: viewModel.translationEntries,
                            draftText: viewModel.liveTranslationPreview,
                            draftTimestamp: viewModel.liveUtteranceTimestamp,
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
                            contentFontSize: viewModel.translationFontSize,
                            copyAction: viewModel.copyTranslationProtocolToPasteboard,
                            closeAction: viewModel.hideTranslationProtocol,
                            loadingText: "Building meeting notes...",
                            emptyText: "No meeting notes yet."
                        )
                        .frame(minHeight: 130)
                    }
                    .frame(maxHeight: .infinity)
                } else if viewModel.isTranslationAnswerVisible {
                    VSplitView {
                        historyPanel(
                            panelKind: .translation,
                            text: viewModel.translatedText,
                            entries: viewModel.translationEntries,
                            draftText: viewModel.liveTranslationPreview,
                            draftTimestamp: viewModel.liveUtteranceTimestamp,
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
                            contentFontSize: viewModel.translationFontSize,
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
                        panelKind: .translation,
                        text: viewModel.translatedText,
                        entries: viewModel.translationEntries,
                        draftText: viewModel.liveTranslationPreview,
                        draftTimestamp: viewModel.liveUtteranceTimestamp,
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

    private var transcriptPanelHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                panelIdentity(
                    title: "Live transcript",
                    systemImage: "captions.bubble.fill",
                    languageCode: viewModel.selectedSourceLanguage.deepgramLanguageCode.uppercased(),
                    languageName: viewModel.selectedSourceLanguage.displayName,
                    isCompact: false
                )

                Spacer(minLength: 8)

                FontSizeControls(
                    currentSize: viewModel.transcriptFontSize,
                    canDecrease: viewModel.canDecreaseTranscriptFontSize,
                    canIncrease: viewModel.canIncreaseTranscriptFontSize,
                    onDecrease: viewModel.decreaseTranscriptFontSize,
                    onIncrease: viewModel.increaseTranscriptFontSize
                )

                transcriptCopyButton

                Divider().frame(height: 18)
                workspaceLayoutPicker
                transcriptAIActionBlock
            }

            HStack(spacing: 8) {
                panelIdentity(
                    title: "Live transcript",
                    systemImage: "captions.bubble.fill",
                    languageCode: viewModel.selectedSourceLanguage.deepgramLanguageCode.uppercased(),
                    languageName: viewModel.selectedSourceLanguage.displayName,
                    isCompact: true
                )

                Spacer(minLength: 4)
                transcriptCopyButton
                transcriptAIActionBlock(isCompact: true)
                transcriptViewMenu
            }
        }
    }

    private var translationPanelHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                panelIdentity(
                    title: "Live translation",
                    systemImage: "globe",
                    languageCode: viewModel.selectedTranslationLanguage.languageCode.uppercased(),
                    languageName: viewModel.selectedTranslationLanguage.displayName,
                    isCompact: false
                )

                Spacer(minLength: 8)

                FontSizeControls(
                    currentSize: viewModel.translationFontSize,
                    canDecrease: viewModel.canDecreaseTranslationFontSize,
                    canIncrease: viewModel.canIncreaseTranslationFontSize,
                    onDecrease: viewModel.decreaseTranslationFontSize,
                    onIncrease: viewModel.increaseTranslationFontSize
                )

                translationCopyButton
                translationAIActionBlock
            }

            HStack(spacing: 8) {
                panelIdentity(
                    title: "Live translation",
                    systemImage: "globe",
                    languageCode: viewModel.selectedTranslationLanguage.languageCode.uppercased(),
                    languageName: viewModel.selectedTranslationLanguage.displayName,
                    isCompact: true
                )

                Spacer(minLength: 4)
                translationCopyButton
                translationAIActionBlock(isCompact: true)
                translationViewMenu
            }
        }
    }

    private func panelIdentity(
        title: String,
        systemImage: String,
        languageCode: String,
        languageName: String,
        isCompact: Bool
    ) -> some View {
        HStack(spacing: 8) {
            if isCompact {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .help(SL(title))
                    .accessibilityLabel(SL(title))
            } else {
                Text(SL(title))
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
            }

            LanguageCodeBadge(code: languageCode, languageName: languageName)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var transcriptCopyButton: some View {
        copyAllButton(
            panel: .transcript,
            helpText: "Copy entire transcript",
            isEnabled: !viewModel.subtitlesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            action: viewModel.copyTranscriptToPasteboard
        )
    }

    private var translationCopyButton: some View {
        copyAllButton(
            panel: .translation,
            helpText: "Copy entire translation",
            isEnabled: !viewModel.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            action: viewModel.copyTranslationToPasteboard
        )
    }

    private var transcriptAIActionBlock: some View {
        transcriptAIActionBlock(isCompact: false)
    }

    private func transcriptAIActionBlock(isCompact: Bool) -> some View {
        AIActionBlock(
            suggestTitle: viewModel.sourceAnswerButtonTitle,
            canSuggest: viewModel.canSuggestSourceAnswer,
            isSuggesting: viewModel.isTranscriptAnswerLoading,
            suggestAction: viewModel.suggestSourceAnswer,
            summaryTitle: viewModel.sourceSummaryButtonTitle,
            canSummarize: viewModel.canSummarizeSource,
            summaryAction: viewModel.summarizeSourceText,
            canCreateMeetingNotes: viewModel.canGenerateSourceProtocol,
            meetingNotesAction: viewModel.generateSourceProtocol,
            isCompact: isCompact
        )
    }

    private var translationAIActionBlock: some View {
        translationAIActionBlock(isCompact: false)
    }

    private func translationAIActionBlock(isCompact: Bool) -> some View {
        AIActionBlock(
            suggestTitle: viewModel.translationAnswerButtonTitle,
            canSuggest: viewModel.canSuggestTranslationAnswer,
            isSuggesting: viewModel.isTranslationAnswerLoading,
            suggestAction: viewModel.suggestTranslatedAnswer,
            summaryTitle: viewModel.translationSummaryButtonTitle,
            canSummarize: viewModel.canSummarizeTranslation,
            summaryAction: viewModel.summarizeTranslatedText,
            canCreateMeetingNotes: viewModel.canGenerateTranslationProtocol,
            meetingNotesAction: viewModel.generateTranslatedProtocol,
            isCompact: isCompact
        )
    }

    private var transcriptViewMenu: some View {
        panelViewMenu(
            canDecrease: viewModel.canDecreaseTranscriptFontSize,
            canIncrease: viewModel.canIncreaseTranscriptFontSize,
            onDecrease: viewModel.decreaseTranscriptFontSize,
            onIncrease: viewModel.increaseTranscriptFontSize
        )
    }

    private var translationViewMenu: some View {
        panelViewMenu(
            canDecrease: viewModel.canDecreaseTranslationFontSize,
            canIncrease: viewModel.canIncreaseTranslationFontSize,
            onDecrease: viewModel.decreaseTranslationFontSize,
            onIncrease: viewModel.increaseTranslationFontSize
        )
    }

    private func panelViewMenu(
        canDecrease: Bool,
        canIncrease: Bool,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void
    ) -> some View {
        Menu {
            Button(action: onDecrease) {
                Label(SL("Decrease text size"), systemImage: "textformat.size.smaller")
            }
            .disabled(!canDecrease)

            Button(action: onIncrease) {
                Label(SL("Increase text size"), systemImage: "textformat.size.larger")
            }
            .disabled(!canIncrease)

            Divider()

            Picker(SL("Panel layout"), selection: $workspaceLayoutRawValue) {
                Label(SL("Side by side"), systemImage: "rectangle.split.2x1")
                    .tag(SpeecharaWorkspaceLayout.columns.rawValue)
                Label(SL("Stacked"), systemImage: "rectangle.split.1x2")
                    .tag(SpeecharaWorkspaceLayout.rows.rawValue)
            }
        } label: {
            Label(SL("View"), systemImage: "slider.horizontal.3")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(SL("View options"))
    }

    private func copyAllButton(
        panel: DialoguePanelKind,
        helpText: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let isCopied = copiedPanel == panel

        return Button {
            action()
            showCopyConfirmation(for: panel)
        } label: {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 28)
        }
        .buttonStyle(FeedbackToolbarButtonStyle(isConfirmed: isCopied))
        .disabled(!isEnabled)
        .help(isCopied ? SL("Copied") : SL(helpText))
        .accessibilityLabel(isCopied ? SL("Copied") : SL(helpText))
    }

    private func showCopyConfirmation(for panel: DialoguePanelKind) {
        withAnimation(.easeOut(duration: 0.12)) {
            copiedPanel = panel
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard copiedPanel == panel else {
                return
            }

            withAnimation(.easeOut(duration: 0.18)) {
                copiedPanel = nil
            }
        }
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

    private var systemAudioStatusText: String {
        viewModel.systemAudioSignalDetected ? SL("Audio detected") : SL("Waiting for audio")
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
    }

    @ViewBuilder
    private func historyPanel(
        panelKind: DialoguePanelKind,
        text: String,
        entries: [DialogueEntry],
        draftText: String,
        draftTimestamp: Date?,
        fontSize: CGFloat,
        isDialogueMode: Bool,
        placeholder: String
    ) -> some View {
        Group {
            if entries.isEmpty
                && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyPanelPlaceholder(
                    text: placeholder,
                    isWorkspaceEmptyState: true,
                    animatesWaveform: viewModel.hasActiveSession
                )
            } else if isDialogueMode {
                DialogueHistoryPanel(
                    entries: entries,
                    fontSize: fontSize,
                    speakerLabel: viewModel.speakerDisplayLabel(for:),
                    draftText: draftText,
                    draftTimestamp: draftTimestamp,
                    draftID: viewModel.liveUtteranceID,
                    hoveredEntryID: $hoveredDialogueEntryID,
                    panelKind: panelKind,
                    scrollTarget: $dialogueScrollTarget
                )
            } else {
                ReadOnlyTextPanel(text: text, draftText: draftText, fontSize: fontSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EditableTextPanel: View {
    @Binding var text: String
    let draftText: String
    let fontSize: CGFloat
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty && draftText.isEmpty {
                Text(placeholder)
                    .font(.system(size: fontSize))
                    .lineSpacing(fontSize * 0.32)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }

            AutoScrollingEditableTextView(
                text: $text,
                draftText: draftText,
                fontSize: fontSize
            )
                .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private struct AutoScrollingEditableTextView: NSViewRepresentable {
    @Binding var text: String
    let draftText: String
    let fontSize: CGFloat
    fileprivate static let readingParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.5
        return style
    }()

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
        let textFont = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        textView.font = textFont
        textView.defaultParagraphStyle = Self.readingParagraphStyle
        textView.typingAttributes = [
            .font: textFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: Self.readingParagraphStyle,
        ]
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

        let desiredFont = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        if textView.font != desiredFont {
            let fullTextRange = NSRange(location: 0, length: textView.string.utf16.count)
            if fullTextRange.length > 0 {
                textView.textStorage?.addAttribute(.font, value: desiredFont, range: fullTextRange)
            }
            textView.font = desiredFont
        }
        textView.defaultParagraphStyle = Self.readingParagraphStyle
        textView.typingAttributes = [
            .font: desiredFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: Self.readingParagraphStyle,
        ]
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
                    .font: NSFont.systemFont(ofSize: parent.fontSize, weight: .regular),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: AutoScrollingEditableTextView.readingParagraphStyle,
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    Text(text.isEmpty ? " " : text)
                        .foregroundColor(.primary)
                        .font(.system(size: fontSize))
                        .lineSpacing(fontSize * 0.32)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    if !cleanDraft.isEmpty {
                        Text(cleanDraft)
                            .foregroundStyle(.secondary)
                            .font(.system(size: fontSize))
                            .lineSpacing(fontSize * 0.32)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .accessibilityLabel(SL("Live draft"))
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            .onAppear {
                scrollToBottom(using: proxy)
            }
            .onChange(of: text) { _ in
                scrollToBottom(using: proxy)
            }
            .onChange(of: draftText) { _ in
                scrollToBottom(using: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var cleanDraft: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines)
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
    var isWorkspaceEmptyState = false
    var animatesWaveform = false

    @ViewBuilder
    var body: some View {
        if isWorkspaceEmptyState {
            HStack(spacing: 12) {
                WaitingWaveform(isAnimating: animatesWaveform)

                Text(SL(text))
                    .font(.system(size: 16, weight: .regular))
                    .lineSpacing(5)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 6)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack {
                Spacer(minLength: 0)
                Text(SL(text))
                    .font(.system(size: 16))
                    .lineSpacing(5)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(24)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct WaitingWaveform: View {
    let isAnimating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !isAnimating)) { context in
            let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 3.2

            HStack(alignment: .center, spacing: 2) {
                ForEach(0 ..< 7, id: \.self) { index in
                    Capsule()
                        .fill(Color.secondary.opacity(0.34))
                        .frame(
                            width: 2.5,
                            height: barHeight(index: index, phase: phase)
                        )
                }
            }
            .frame(width: 30, height: 18)
        }
        .accessibilityHidden(true)
    }

    private func barHeight(index: Int, phase: TimeInterval) -> CGFloat {
        guard isAnimating, !reduceMotion else {
            return 5 + CGFloat((index * 3) % 8)
        }

        let wave = abs(sin(phase + Double(index) * 0.72))
        return 4 + CGFloat(wave) * 12
    }
}

private struct DialogueEntryOffsetPreferenceKey: PreferenceKey {
    static var defaultValue = [UUID: CGFloat]()

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct DialogueHistoryPanel: View {
    let entries: [DialogueEntry]
    let fontSize: CGFloat
    let speakerLabel: (Int) -> String
    let draftText: String
    let draftTimestamp: Date?
    let draftID: UUID?
    @Binding var hoveredEntryID: UUID?
    let panelKind: DialoguePanelKind
    @Binding var scrollTarget: DialogueScrollTarget?
    @State private var scrollWorkItem: DispatchWorkItem?
    @State private var isPointerInside = false
    private let bottomAnchor = "dialogue-bottom-anchor"
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        dialogueBlock(
                            entryID: entry.id,
                            text: entry.text,
                            timestamp: entry.timestamp,
                            speakerNumber: entry.speakerNumber,
                            isDraft: entry.isDraft
                        )
                        .id(entry.id)
                    }

                    if !cleanDraft.isEmpty {
                        dialogueBlock(
                            entryID: draftID,
                            text: cleanDraft,
                            timestamp: draftTimestamp ?? Date(),
                            speakerNumber: nil,
                            isDraft: true
                        )
                        .accessibilityLabel(SL("Live draft"))
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .onAppear {
                scrollToBottom(using: proxy)
            }
            .onChange(of: scrollSignature) { _ in
                scrollToBottom(using: proxy)
            }
            .onChange(of: scrollTarget) { target in
                scrollToSynchronizedTarget(target, using: proxy)
            }
            .onChange(of: availableEntryIDs) { _ in
                scrollToSynchronizedTarget(scrollTarget, using: proxy)
            }
            .onPreferenceChange(DialogueEntryOffsetPreferenceKey.self) { offsets in
                publishTopVisibleEntry(from: offsets)
            }
        }
        .coordinateSpace(name: coordinateSpaceName)
        .onHover { isHovering in
            isPointerInside = isHovering
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var coordinateSpaceName: String {
        "speechara-dialogue-scroll-\(panelKind.rawValue)"
    }

    private var availableEntryIDs: [UUID] {
        entries.map(\.id)
    }

    private var scrollSignature: String {
        let entrySignature: String
        if let lastEntry = entries.last {
            entrySignature = "\(entries.count)-\(lastEntry.id.uuidString)-\(lastEntry.text.count)-\(lastEntry.isDraft)"
        } else {
            entrySignature = "empty"
        }

        return "\(entrySignature)-\(cleanDraft)"
    }

    private var cleanDraft: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dialogueBlock(
        entryID: UUID?,
        text: String,
        timestamp: Date,
        speakerNumber: Int?,
        isDraft: Bool
    ) -> some View {
        inlineDialogueText(
            text: text,
            timestamp: timestamp,
            speakerNumber: speakerNumber,
            isDraft: isDraft
        )
        .lineSpacing(fontSize * 0.32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHighlighted(entryID) ? Color.accentColor.opacity(0.11) : Color.clear)

                if let entryID {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: DialogueEntryOffsetPreferenceKey.self,
                            value: [entryID: geometry.frame(in: .named(coordinateSpaceName)).minY]
                        )
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            updateHoveredEntry(entryID, isHovering: isHovering)
        }
        .animation(.easeOut(duration: 0.12), value: hoveredEntryID)
    }

    private func isHighlighted(_ entryID: UUID?) -> Bool {
        guard let entryID else {
            return false
        }
        return hoveredEntryID == entryID
    }

    private func updateHoveredEntry(_ entryID: UUID?, isHovering: Bool) {
        guard let entryID else {
            return
        }

        if isHovering {
            hoveredEntryID = entryID
        } else if hoveredEntryID == entryID {
            hoveredEntryID = nil
        }
    }

    private func publishTopVisibleEntry(from offsets: [UUID: CGFloat]) {
        guard isPointerInside, !offsets.isEmpty else {
            return
        }

        let topInset: CGFloat = 6
        let entriesAboveTop = offsets.filter { $0.value <= topInset }
        let visibleEntry = entriesAboveTop.max(by: { $0.value < $1.value })
            ?? offsets.min(by: { $0.value < $1.value })

        guard let entryID = visibleEntry?.key else {
            return
        }

        let nextTarget = DialogueScrollTarget(entryID: entryID, source: panelKind)
        guard scrollTarget != nextTarget else {
            return
        }
        scrollTarget = nextTarget
    }

    private func scrollToSynchronizedTarget(
        _ target: DialogueScrollTarget?,
        using proxy: ScrollViewProxy
    ) {
        guard let target,
              target.source != panelKind,
              availableEntryIDs.contains(target.entryID) else {
            return
        }

        proxy.scrollTo(target.entryID, anchor: .top)
    }

    private func inlineDialogueText(
        text: String,
        timestamp: Date,
        speakerNumber: Int?,
        isDraft: Bool
    ) -> Text {
        var prefix = Text(verbatim: "\(Self.timestampFormatter.string(from: timestamp)) ")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(Color.secondary.opacity(0.55))

        if let speakerNumber {
            prefix = prefix
                + Text(verbatim: "\(speakerLabel(speakerNumber)) · ")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
        }

        return prefix
            + Text(verbatim: text)
                .font(.system(size: fontSize))
                .foregroundColor(isDraft ? .secondary : .primary)
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

private struct LanguageCodeBadge: View {
    let code: String
    let languageName: String

    var body: some View {
        Text(code)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.5)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(Color.accentColor)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
            )
            .help(SLF("Input: %@", languageName))
            .accessibilityLabel(SLF("Input: %@", languageName))
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
    let currentSize: CGFloat
    let canDecrease: Bool
    let canIncrease: Bool
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onDecrease) {
                Image(systemName: "textformat.size.smaller")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(FeedbackToolbarButtonStyle())
            .disabled(!canDecrease)
            .help(SL("Decrease text size"))

            Text(verbatim: "\(Int(currentSize))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 22)
                .accessibilityHidden(true)

            Button(action: onIncrease) {
                Image(systemName: "textformat.size.larger")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(FeedbackToolbarButtonStyle())
            .disabled(!canIncrease)
            .help(SL("Increase text size"))
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(Int(currentSize))")
    }
}

private struct FeedbackToolbarButtonStyle: ButtonStyle {
    var isConfirmed = false

    func makeBody(configuration: Configuration) -> some View {
        FeedbackToolbarButton(
            configuration: configuration,
            isConfirmed: isConfirmed
        )
    }

    private struct FeedbackToolbarButton: View {
        @Environment(\.isEnabled) private var isEnabled

        let configuration: Configuration
        let isConfirmed: Bool

        var body: some View {
            configuration.label
                .foregroundStyle(foregroundColor)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .opacity(isEnabled ? 1 : 0.38)
                .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.14), value: isConfirmed)
        }

        private var foregroundColor: Color {
            if isConfirmed {
                return Color.green
            }

            return configuration.isPressed ? Color.accentColor : Color.secondary
        }

        private var backgroundColor: Color {
            if isConfirmed {
                return Color.green.opacity(0.16)
            }

            if configuration.isPressed {
                return Color.accentColor.opacity(0.18)
            }

            return Color.primary.opacity(0.055)
        }

        private var borderColor: Color {
            if isConfirmed {
                return Color.green.opacity(0.42)
            }

            if configuration.isPressed {
                return Color.accentColor.opacity(0.45)
            }

            return Color.primary.opacity(0.10)
        }
    }
}

private struct AIActionBlock: View {
    let suggestTitle: String
    let canSuggest: Bool
    let isSuggesting: Bool
    let suggestAction: () -> Void
    let summaryTitle: String
    let canSummarize: Bool
    let summaryAction: () -> Void
    let canCreateMeetingNotes: Bool
    let meetingNotesAction: () -> Void
    var isCompact = false

    private let primaryColor = Color(red: 0.22, green: 0.46, blue: 0.96)
    private let aiColor = Color(red: 0.56, green: 0.35, blue: 0.88)

    var body: some View {
        HStack(spacing: 7) {
            if !isCompact {
                Label("AI", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(aiColor)
                    .padding(.horizontal, 4)

                Divider()
                    .frame(height: 20)
            }

            Button(action: suggestAction) {
                HStack(spacing: 6) {
                    if isSuggesting {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                    }

                    Text(SL(suggestTitle))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(primaryColor.opacity(canSuggest || isSuggesting ? 1 : 0.35))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSuggest)
            .help(SL("Primary AI action: draft a reply to the latest question."))

            Menu {
                Button(action: summaryAction) {
                    Label(SL(summaryTitle), systemImage: "text.alignleft")
                }
                .disabled(!canSummarize)

                Button(action: meetingNotesAction) {
                    Label(SL("Meeting notes"), systemImage: "doc.text")
                }
                .disabled(!canCreateMeetingNotes)
            } label: {
                Text(SL("Summary"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!canSummarize && !canCreateMeetingNotes)
            .help(SL("Secondary AI actions"))
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(aiColor.opacity(0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(aiColor.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ResultPanel: View {
    let title: String
    let contentText: String
    let errorMessage: String?
    let isLoading: Bool
    let contentFontSize: CGFloat
    let copyAction: () -> Void
    let closeAction: () -> Void
    let loadingText: String
    let emptyText: String
    var usesInternalScroll = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(SL(title))
                    .font(.system(size: 15, weight: .semibold))

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

            Divider()
                .opacity(0.65)

            resultContent
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        if isLoading {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView()
                Text(SL(loadingText))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(12)
        } else if let errorMessage {
            if usesInternalScroll {
                    ScrollView {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(12)
            } else {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
        } else if contentText.isEmpty {
            EmptyPanelPlaceholder(text: emptyText)
                .frame(minHeight: 120)
        } else {
            if usesInternalScroll {
                    ScrollView {
                        Text(contentText)
                            .font(.system(size: contentFontSize))
                            .lineSpacing(contentFontSize * 0.32)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(12)
            } else {
                Text(contentText)
                    .font(.system(size: contentFontSize))
                    .lineSpacing(contentFontSize * 0.32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
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
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    var showsTitle = true
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))

                if showsTitle {
                    Text(SL(title))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .padding(.horizontal, showsTitle ? 14 : 0)
            .frame(width: showsTitle ? nil : ToolbarMetrics.controlHeight)
            .frame(height: ToolbarMetrics.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: ToolbarMetrics.cornerRadius)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ToolbarMetrics.cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: colorScheme == .dark ? 6 : 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .animation(.easeOut(duration: 0.14), value: isActive)
        .help(SL(title))
        .accessibilityLabel(SL(title))
    }

    private var backgroundColor: Color {
        if colorScheme == .dark {
            if isActive {
                return Color.accentColor.opacity(isHovered ? 0.28 : 0.22)
            }
            return Color.white.opacity(isHovered ? 0.10 : 0.055)
        }

        if isActive {
            return Color.accentColor.opacity(isHovered ? 0.16 : 0.11)
        }
        return Color.white.opacity(isHovered ? 0.78 : 0.60)
    }

    private var borderColor: Color {
        if colorScheme == .dark {
            return isActive
                ? Color.accentColor.opacity(0.42)
                : Color.white.opacity(isHovered ? 0.16 : 0.09)
        }

        return isActive
            ? Color.accentColor.opacity(0.30)
            : Color.black.opacity(isHovered ? 0.10 : 0.06)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.24) : Color.black.opacity(0.04)
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
    var audioLevel: Double?
    var isAudioLevelActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))

                VStack(alignment: .leading, spacing: 1) {
                    Text(SL(title))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .truncationMode(.tail)

                    if let subtitle {
                        Text(SL(subtitle))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                .multilineTextAlignment(.leading)
                .layoutPriority(1)

                if let audioLevel {
                    AudioLevelBars(
                        level: audioLevel,
                        isActive: isAudioLevelActive
                    )
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
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
    let contentPadding: CGFloat
    let isElevated: Bool
    let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(
        accent: Color? = nil,
        contentPadding: CGFloat = 20,
        isElevated: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.contentPadding = contentPadding
        self.isElevated = isElevated
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(contentPadding)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(
            color: isElevated ? shadowColor : .clear,
            radius: isElevated ? 18 : 0,
            x: 0,
            y: isElevated ? 10 : 0
        )
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
    static let primaryHeight: CGFloat = 46
    static let primaryCornerRadius: CGFloat = 16
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

                AudioLevelBars(
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

private struct AudioLevelBars: View {
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
                                subtitle: "Choose a language or let Speechara detect it automatically."
                            ) {
                                Picker("", selection: $viewModel.selectedSourceLanguage) {
                                    ForEach(SourceLanguageOption.allCases) { language in
                                        Text(language.displayName).tag(language)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 230)
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
                                    .frame(width: 230)
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
