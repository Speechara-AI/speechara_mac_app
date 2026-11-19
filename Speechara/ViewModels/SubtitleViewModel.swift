import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum SubtitleStatus: String {
    case idle = "Idle"
    case listening = "Listening"
    case stopped = "Stopped"
}

enum ListeningSessionStartMode: Equatable {
    case newSession
    case continuePrevious
}

@MainActor
private enum ListeningSessionStartPrompt {
    static func ask() -> ListeningSessionStartMode {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = SL("Start listening?")
        alert.informativeText = SL("Start a new session or continue the previous one?")
        alert.addButton(withTitle: SL("Start New"))
        alert.addButton(withTitle: SL("Continue"))

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            return .newSession
        }

        return .continuePrevious
    }
}

@MainActor
private enum ListeningMicrophonePrompt {
    static func ask() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = SL("Turn on microphone?")
        alert.informativeText = SL("Without the microphone, Speechara will not capture what you say.")
        alert.addButton(withTitle: SL("Turn On Microphone"))
        alert.addButton(withTitle: SL("Continue Without Mic"))

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

struct DialogueEntry: Identifiable, Equatable {
    let id: UUID
    let speakerNumber: Int?
    let text: String
    let timestamp: Date
    let isDraft: Bool

    init(
        id: UUID = UUID(),
        speakerNumber: Int?,
        text: String,
        timestamp: Date = Date(),
        isDraft: Bool = false
    ) {
        self.id = id
        self.speakerNumber = speakerNumber
        self.text = text
        self.timestamp = timestamp
        self.isDraft = isDraft
    }
}

private struct SessionTurn: Identifiable, Equatable {
    let id: UUID
    var speakerLabel: String?
    var text: String
    var translationSpeakerLabel: String?
    var translationText: String
    var timestamp: Date
    var isClosed: Bool

    init(
        id: UUID = UUID(),
        speakerLabel: String? = nil,
        text: String,
        translationSpeakerLabel: String? = nil,
        translationText: String = "",
        timestamp: Date = Date(),
        isClosed: Bool = false
    ) {
        self.id = id
        self.speakerLabel = speakerLabel
        self.text = text
        self.translationSpeakerLabel = translationSpeakerLabel
        self.translationText = translationText
        self.timestamp = timestamp
        self.isClosed = isClosed
    }
}


@MainActor
final class SubtitleViewModel: ObservableObject {
    private static let minimumEditorFontSize: CGFloat = 12
    private static let maximumEditorFontSize: CGFloat = 30
    private static let editorFontStep: CGFloat = 2
    private static let microphoneStartPreferenceDefaultsKey = "speechara.session.startWithMicrophone"
    private static let sourceLanguageDefaultsKey = "speechara.session.inputLanguage"
    private static let translationLanguageDefaultsKey = "speechara.session.translationLanguage"
    private static let sessionDraftDefaultsKey = "speechara.session.localDraft.v2"
    private static let stableReconstructionContextLines = 2
    private static let stableReconstructionBatchLines = 5
    private static let stableReconstructionDelayNanoseconds: UInt64 = 2_000_000_000
    private static let utterancePauseNanoseconds: UInt64 = 2_200_000_000
    private static let maximumUtteranceCharacterCount = 520
    private static let maximumUtteranceWordCount = 90

    @Published private(set) var status: SubtitleStatus = .idle
    @Published var subtitlesText = ""
    @Published var translatedText = ""
    @Published private(set) var transcriptEntries = [DialogueEntry]()
    @Published private(set) var translationEntries = [DialogueEntry]()
    @Published var selectedSourceLanguage: SourceLanguageOption = .english {
        didSet {
            defaults.set(selectedSourceLanguage.rawValue, forKey: Self.sourceLanguageDefaultsKey)
            reconcileTranslationSelectionWithSourceLanguage()
        }
    }
    @Published var isAudioRecordingEnabled = false
    @Published var isTranslationEnabled = true
    @Published var selectedTranslationLanguage: TranslationLanguageOption = .russian {
        didSet {
            defaults.set(selectedTranslationLanguage.rawValue, forKey: Self.translationLanguageDefaultsKey)
        }
    }
    @Published var startsWithMicrophoneEnabled = false {
        didSet {
            defaults.set(
                startsWithMicrophoneEnabled,
                forKey: Self.microphoneStartPreferenceDefaultsKey
            )
        }
    }
    @Published private(set) var liveSubtitlePreview = ""
    @Published private(set) var liveTranslationPreview = ""
    @Published private(set) var availableMicrophones = [MicrophoneInputDevice]()
    @Published var selectedMicrophoneID = ""
    @Published private(set) var isSystemAudioListening = false
    @Published private(set) var isMicrophoneListening = false
    @Published private(set) var shouldShowMicrophoneOffWarning = false
    @Published private(set) var isMicrophoneTesting = false
    @Published private(set) var isMicrophoneBusy = false
    @Published private(set) var systemAudioLevel = 0.0
    @Published private(set) var systemAudioSignalDetected = false
    @Published private(set) var microphoneLevel = 0.0
    @Published private(set) var microphoneSignalDetected = false
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var translationMessage: String?
    @Published private(set) var lastRecordingPath: String?
    @Published private(set) var transcriptFontSize: CGFloat = 17
    @Published private(set) var translationFontSize: CGFloat = 17
    @Published private(set) var isTranscriptSummaryVisible = false
    @Published private(set) var isTranscriptSummaryLoading = false
    @Published private(set) var transcriptSummaryText = ""
    @Published private(set) var transcriptSummaryErrorMessage: String?
    @Published private(set) var isTranslationSummaryVisible = false
    @Published private(set) var isTranslationSummaryLoading = false
    @Published private(set) var translationSummaryText = ""
    @Published private(set) var translationSummaryErrorMessage: String?
    @Published private(set) var isTranscriptProtocolVisible = false
    @Published private(set) var isTranscriptProtocolLoading = false
    @Published private(set) var transcriptProtocolText = ""
    @Published private(set) var transcriptProtocolErrorMessage: String?
    @Published private(set) var isTranslationProtocolVisible = false
    @Published private(set) var isTranslationProtocolLoading = false
    @Published private(set) var translationProtocolText = ""
    @Published private(set) var translationProtocolErrorMessage: String?
    @Published private(set) var isTranscriptAnswerVisible = false
    @Published private(set) var isTranscriptAnswerLoading = false
    @Published private(set) var transcriptAnswerText = ""
    @Published private(set) var transcriptAnswerErrorMessage: String?
    @Published private(set) var isTranslationAnswerVisible = false
    @Published private(set) var isTranslationAnswerLoading = false
    @Published private(set) var translationAnswerText = ""
    @Published private(set) var translationAnswerErrorMessage: String?

    private let systemAudioCaptureService = SystemAudioCaptureService()
    private var microphoneCaptureService = MicrophoneCaptureService()
    private let localAudioRecordingService = LocalAudioRecordingService()
    private let mixedAudioStreamMixer = MixedAudioStreamMixer()
    private let liveDeepgramService = DeepgramLiveTranscriptionService()
    private let liveTranslationService = SpeecharaLiveTranslationV2Service()
    private var finalTranslationService: SpeecharaLiveTranslationV2Service { liveTranslationService }
    private let deepSeekSummaryService = DeepSeekSummaryService()
    private let deepSeekMeetingProtocolService = DeepSeekMeetingProtocolService()
    private let deepSeekAnswerAssistService = DeepSeekAnswerAssistService()
    private let meetingSessionHistoryService = MeetingSessionHistoryService()
    private let billingService = SpeecharaBillingService()
    private let speecharaAIProxyService = SpeecharaBackendProxyService()
    private var isTranslationAvailable = false
    private var isStreamingSessionPrepared = false
    private var isMicrophoneCaptureActive = false
    private let defaults: UserDefaults
    private var sessionTurns = [SessionTurn]()
    private var speakerLabelToNumber = [String: Int]()
    private var speakerNumberToLabel = [Int: String]()
    private var nextSpeakerNumber = 1
    private var lastDeepgramFinalTranscript = ""
    private var nextStableTurnIndex = 0
    private var stableReconstructionTask: Task<Void, Never>?
    private var utteranceFinalizationTask: Task<Void, Never>?
    private var translationPreparationTask: Task<Void, Never>?
    private var streamingSessionGeneration = UUID()
    private var pendingTranslationDrafts = [UUID: String]()
    private var translationPreviewTurnID: UUID?
    private var lastSavedDraftFingerprint = ""
    private var meetingHistorySessionID: String?
    private var meetingHistorySessionRevision: Int?
    private var meetingHistoryStartedAt: Date?
    private var meetingHistoryEndedAt: Date?
    private var meetingHistoryAuthUserID: String?
    private var meetingHistoryNeedsLegacyRecovery = false
    private var meetingHistoryAutosaveTask: Task<Void, Never>?
    private var meetingHistoryRetryTask: Task<Void, Never>?
    private var meetingHistoryLastSavedSnapshotSignature: String?
    private var meetingHistoryLastCompletedSnapshotSignature: String?
    private var meetingHistorySaveTask: Task<Void, Never>?
    private var meetingHistorySource = "system_audio"
    private var focusModeEnabledForHistory = false
    private var meetingHistoryConversationGeneration = UUID()
    private var billingUsageIntervalStartedAt: Date?
    private var billingUsageEventSequence = 1
    private var billingUsageSyncTask: Task<Void, Never>?
    private var isReconcilingTranslationSelection = false
    private var isHandlingLiveTranscriptionRuntimeError = false
    private var lastSystemAudioSignalDate: Date?

    private static let transcriptTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static var currentAppVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return info["CFBundleShortVersionString"] as? String
            ?? info["CFBundleVersion"] as? String
            ?? "0"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedSourceLanguage = SourceLanguageOption.supported(
            code: defaults.string(forKey: Self.sourceLanguageDefaultsKey)
        ) ?? .english
        selectedTranslationLanguage = TranslationLanguageOption.supported(
            code: defaults.string(forKey: Self.translationLanguageDefaultsKey)
        ) ?? .russian
        reconcileTranslationSelectionWithSourceLanguage()
        startsWithMicrophoneEnabled = defaults.object(forKey: Self.microphoneStartPreferenceDefaultsKey) as? Bool ?? false
        refreshAvailableMicrophones()
        restoreDraftIfAvailable()
    }

    var liveSubtitleDescription: String {
        liveSubtitlePreview.isEmpty ? SL("Waiting for speech...") : liveSubtitlePreview
    }

    var showsTranscriptDialogueMode: Bool {
        !transcriptEntries.compactMap(\.speakerNumber).isEmpty
    }

    var showsTranslationDialogueMode: Bool {
        !translationEntries.compactMap(\.speakerNumber).isEmpty
    }

    var isListening: Bool {
        status == .listening
    }

    var hasActiveSession: Bool {
        isStreamingSessionPrepared || isSystemAudioListening || isMicrophoneListening || isMicrophoneTesting
    }

    var canStartSystemListening: Bool {
        !isSystemAudioListening && !isBusy
    }

    var canStartAudioOnlyListening: Bool {
        !hasActiveSession && !isBusy && !isMicrophoneBusy
    }

    var canStopSystemListening: Bool {
        isSystemAudioListening && !isBusy
    }

    var sourceLanguageSummary: String {
        SLF("Input: %@", selectedSourceLanguage.displayName)
    }

    var recordingSummary: String {
        isAudioRecordingEnabled ? SL("M4A: On") : SL("M4A: Off")
    }

    var microphoneSummary: String {
        isMicrophoneListening ? SL("Mic: On") : SL("Mic: Off")
    }

    var selectedMicrophoneName: String {
        availableMicrophones.first(where: { $0.id == selectedMicrophoneID })?.name ?? SL("Default microphone")
    }

    var hasAvailableMicrophones: Bool {
        !availableMicrophones.isEmpty
    }

    var microphoneTestButtonTitle: String {
        isMicrophoneTesting ? SL("Stop test") : SL("Start test")
    }

    var microphoneTestDescription: String {
        if !hasAvailableMicrophones {
            return SL("No microphone devices are available.")
        }

        if isMicrophoneTesting {
            return microphoneSignalDetected ? SL("Signal detected. Keep speaking.") : SL("Speak now. Waiting for signal...")
        }

        if isMicrophoneListening {
            return microphoneSignalDetected ? SL("Microphone signal is live.") : SL("Microphone is on. Waiting for speech...")
        }

        return SL("Use Test to verify the selected microphone before adding it to the live transcript.")
    }

    var translationSummary: String {
        isTranslationEnabled ? SLF("Translate to: %@", selectedTranslationLanguage.displayName) : SL("Translation: Off")
    }

    var availableTranslationLanguages: [TranslationLanguageOption] {
        guard let sourceTarget = selectedSourceLanguage.matchingTranslationLanguage else {
            return TranslationLanguageOption.allCases
        }
        return TranslationLanguageOption.allCases.filter { $0 != sourceTarget }
    }

    private var sourceAIOutputLanguage: TranslationLanguageOption {
        if selectedSourceLanguage == .multilingual {
            return isTranslationEnabled ? selectedTranslationLanguage : .english
        }
        return selectedSourceLanguage.matchingTranslationLanguage ?? .english
    }

    var translationPanelTitle: String {
        SLF("%@ translation", selectedTranslationLanguage.displayName)
    }

    var assistantActivityText: String? {
        if isTranscriptProtocolLoading || isTranslationProtocolLoading {
            return SL("Preparing meeting notes...")
        }

        if isTranscriptAnswerLoading || isTranslationAnswerLoading {
            return SL("Suggesting answer...")
        }

        if isTranscriptSummaryLoading || isTranslationSummaryLoading {
            return SL("Summarizing...")
        }

        if !liveTranslationPreview.isEmpty {
            return SL("Translating...")
        }

        return nil
    }

    var transcriptPlaceholderText: String {
        hasActiveSession
            ? SL("Listening… Transcript will appear here.")
            : SL("Start listening to see the transcript here.")
    }

    var translationPlaceholderText: String {
        if !isTranslationEnabled {
            return SL("Translation is off for this session.")
        }

        return SL("Translation will appear as you speak.")
    }

    var sourceAnswerPlaceholderText: String {
        SL("Suggested answer will appear here after you ask the assistant for help with the latest question.")
    }

    var sourceSummaryButtonTitle: String {
        selectedSourceLanguage.summarizeButtonTitle
    }

    var sourceAnswerButtonTitle: String {
        selectedSourceLanguage.answerButtonTitle
    }

    var sourceProtocolButtonTitle: String {
        selectedSourceLanguage.protocolButtonTitle
    }

    var translationSummaryButtonTitle: String {
        selectedTranslationLanguage.summarizeButtonTitle
    }

    var translationAnswerButtonTitle: String {
        selectedTranslationLanguage.answerButtonTitle
    }

    var translationProtocolButtonTitle: String {
        selectedTranslationLanguage.protocolButtonTitle
    }

    var sourceSummaryPanelTitle: String {
        "\(SL("Summary")) · \(selectedSourceLanguage.displayName)"
    }

    var sourceProtocolPanelTitle: String {
        selectedSourceLanguage.protocolPanelTitle
    }

    var sourceAnswerPanelTitle: String {
        selectedSourceLanguage.answerPanelTitle
    }

    var translationSummaryPanelTitle: String {
        "\(SL("Summary")) · \(selectedTranslationLanguage.displayName)"
    }

    var translationAnswerPanelTitle: String {
        selectedTranslationLanguage.answerPanelTitle
    }

    var translationProtocolPanelTitle: String {
        selectedTranslationLanguage.protocolPanelTitle
    }

    private func reconcileTranslationSelectionWithSourceLanguage() {
        guard !isReconcilingTranslationSelection else {
            return
        }

        guard let matchingTranslationLanguage = selectedSourceLanguage.matchingTranslationLanguage,
              selectedTranslationLanguage == matchingTranslationLanguage else {
            return
        }

        isReconcilingTranslationSelection = true

        if let fallbackLanguage = availableTranslationLanguages.first {
            selectedTranslationLanguage = fallbackLanguage
        }

        let shouldDisableTranslation = isTranslationEnabled
        if shouldDisableTranslation {
            isTranslationEnabled = false
        }

        isReconcilingTranslationSelection = false

        guard shouldDisableTranslation else {
            return
        }

        isTranslationAvailable = false
        liveTranslationPreview = ""
        translationPreviewTurnID = nil
        translationMessage = "Live translation was turned off because the source and target languages cannot match."

        let liveTranslationService = self.liveTranslationService
        let finalTranslationService = self.finalTranslationService
        Task {
            await liveTranslationService.resetSession()
            await finalTranslationService.resetSession()
        }
    }

    func speakerDisplayLabel(for speakerNumber: Int) -> String {
        speakerLabel(for: speakerNumber)
    }

    var liveUtteranceTimestamp: Date? {
        sessionTurns.last(where: { !$0.isClosed })?.timestamp
    }

    var liveUtteranceID: UUID? {
        sessionTurns.last(where: { !$0.isClosed })?.id
    }

    var canIncreaseTranscriptFontSize: Bool {
        transcriptFontSize < Self.maximumEditorFontSize
    }

    var canDecreaseTranscriptFontSize: Bool {
        transcriptFontSize > Self.minimumEditorFontSize
    }

    var canIncreaseTranslationFontSize: Bool {
        translationFontSize < Self.maximumEditorFontSize
    }

    var canDecreaseTranslationFontSize: Bool {
        translationFontSize > Self.minimumEditorFontSize
    }

    var canSummarizeSource: Bool {
        !isTranscriptSummaryLoading
            && !subtitlesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSummarizeTranslation: Bool {
        !isTranslationSummaryLoading
            && !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canGenerateSourceProtocol: Bool {
        !isTranscriptProtocolLoading && !subtitlesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canGenerateTranslationProtocol: Bool {
        !isTranslationProtocolLoading && !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSuggestSourceAnswer: Bool {
        !isTranscriptAnswerLoading && !transcriptForAnswerAssist().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSuggestTranslationAnswer: Bool {
        !isTranslationAnswerLoading && !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var lastRecordingDescription: String {
        if let lastRecordingPath {
            return lastRecordingPath
        }

        return isAudioRecordingEnabled ? "No M4A file saved yet." : "M4A recording is disabled."
    }

    var canRevealLastRecording: Bool {
        guard let lastRecordingPath else {
            return false
        }

        return FileManager.default.fileExists(atPath: lastRecordingPath)
    }

    func promptAndStartListening(includeMicrophone: Bool = false) {
        guard !isSystemAudioListening, !isBusy else {
            return
        }

        let startMode = ListeningSessionStartPrompt.ask()
        let shouldIncludeMicrophone = includeMicrophone || ListeningMicrophonePrompt.ask()
        if shouldIncludeMicrophone {
            startsWithMicrophoneEnabled = true
        }
        startListening(mode: startMode, includeMicrophone: shouldIncludeMicrophone)
    }

    func startListening(includeMicrophone: Bool = false) {
        startListening(mode: .continuePrevious, includeMicrophone: includeMicrophone)
    }

    func startListening(mode: ListeningSessionStartMode, includeMicrophone: Bool = false) {
        SpeecharaDiagnostics.session.notice("startListening requested mode=\(String(describing: mode)) includeMicrophone=\(includeMicrophone) isSystemListening=\(self.isSystemAudioListening) isBusy=\(self.isBusy)")
        guard !isSystemAudioListening, !isBusy else {
            SpeecharaDiagnostics.session.warning("startListening ignored because session is already active or busy")
            return
        }

        isBusy = true
        errorMessage = nil
        translationMessage = nil

        Task { @MainActor in
            defer {
                isBusy = false
            }

            do {
                if mode == .newSession {
                    try await prepareNewListeningSession()
                }

                try await startSystemAudioListening(includeMicrophone: includeMicrophone)
            } catch {
                SpeecharaDiagnostics.session.error("startListening failed error=\(error.localizedDescription)")
                errorMessage = error.localizedDescription

                if !hasActiveAudioSource {
                    status = .idle
                }
            }
        }
    }

    private func prepareNewListeningSession() async throws {
        if hasActiveSession {
            await stopStreamingSession(markStopped: false, persistHistoryAsActive: false)
        }

        guard await completeMeetingHistoryConversationIfNeeded() else {
            throw MeetingSessionHistoryServiceError.graphqlRequestFailed(
                "The current meeting could not be saved. Its local draft has been kept. Try again before starting a new meeting."
            )
        }
        resetMeetingHistoryState()
        clearCurrentSessionForNewSession()
    }

    private func startSystemAudioListening(includeMicrophone: Bool) async throws {
        try await ensureStreamingSessionStarted()
        try await systemAudioCaptureService.startCapture(recordAudio: false)
        isSystemAudioListening = true
        status = .listening
        shouldShowMicrophoneOffWarning = !includeMicrophone
        meetingHistoryStartedAt = meetingHistoryStartedAt ?? Date()
        meetingHistoryEndedAt = nil
        meetingHistorySource = includeMicrophone ? "system_audio+microphone" : "system_audio"
        persistDraftIfNeeded()
        markBillingUsageStartedIfNeeded()
        scheduleMeetingHistorySessionStartIfNeeded()

        if includeMicrophone && !isMicrophoneListening {
            do {
                try await enableMicrophoneListening()
            } catch {
                await mixedAudioStreamMixer.setMicrophoneEnabled(false)
                stopMicrophoneCaptureIfPossible(force: true)
                isMicrophoneListening = false
                shouldShowMicrophoneOffWarning = true
                updateMicrophoneLiveHandler()
                errorMessage = error.localizedDescription
            }
        }
    }

    func startNewSession() {
        SpeecharaDiagnostics.session.notice("startNewSession requested active=\(self.hasActiveSession) busy=\(self.isBusy)")
        guard !isBusy, !isMicrophoneBusy else {
            return
        }

        isBusy = true
        errorMessage = nil
        translationMessage = nil

        Task { @MainActor in
            defer {
                isBusy = false
            }

            if hasActiveSession {
                await stopStreamingSession(markStopped: false, persistHistoryAsActive: false)
            }

            guard await completeMeetingHistoryConversationIfNeeded() else { return }
            resetMeetingHistoryState()
            clearCurrentSessionForNewSession()
        }
    }

    func stopListening() {
        SpeecharaDiagnostics.session.notice("stopListening requested systemListening=\(self.isSystemAudioListening) busy=\(self.isBusy)")
        guard isSystemAudioListening, !isBusy else {
            return
        }

        isBusy = true
        errorMessage = nil

        Task { @MainActor in
            defer {
                isBusy = false
            }

            await stopSystemAudioListening(markStopped: true)
        }
    }

    func showErrorMessage(_ message: String) {
        errorMessage = message
    }

    func startAudioOnlyListening() {
        guard canStartAudioOnlyListening else {
            return
        }

        isBusy = true
        isMicrophoneBusy = true
        errorMessage = nil
        translationMessage = nil

        Task { @MainActor in
            defer {
                isBusy = false
                isMicrophoneBusy = false
            }

            do {
                try await ensureStreamingSessionStarted()
                try await enableMicrophoneListening()
                meetingHistoryStartedAt = meetingHistoryStartedAt ?? Date()
                meetingHistoryEndedAt = nil
                meetingHistorySource = "microphone"
                persistDraftIfNeeded()
                scheduleMeetingHistorySessionStartIfNeeded()
            } catch {
                await mixedAudioStreamMixer.setMicrophoneEnabled(false)
                stopMicrophoneCaptureIfPossible(force: true)
                isMicrophoneListening = false
                updateMicrophoneLiveHandler()
                errorMessage = error.localizedDescription

                if !hasActiveAudioSource {
                    status = .idle
                }
            }
        }
    }

    func stopActiveSession() {
        SpeecharaDiagnostics.session.notice("stopActiveSession requested active=\(self.hasActiveSession) busy=\(self.isBusy) microphoneBusy=\(self.isMicrophoneBusy)")
        guard hasActiveSession, !isBusy, !isMicrophoneBusy else {
            return
        }

        isBusy = true
        isMicrophoneBusy = true
        errorMessage = nil

        Task { @MainActor in
            defer {
                isBusy = false
                isMicrophoneBusy = false
            }

            await stopStreamingSession(markStopped: true)
        }
    }

    func toggleMicrophoneCapture() {
        SpeecharaDiagnostics.session.notice(
            "toggleMicrophoneCapture requested enabled=\(self.isMicrophoneListening) system=\(self.isSystemAudioListening) busy=\(self.isBusy) microphoneBusy=\(self.isMicrophoneBusy)"
        )
        guard !isBusy, !isMicrophoneBusy else {
            return
        }

        isMicrophoneBusy = true

        Task { @MainActor in
            defer {
                isMicrophoneBusy = false
            }

            if isMicrophoneListening {
                await mixedAudioStreamMixer.setMicrophoneEnabled(false)
                isMicrophoneListening = false
                shouldShowMicrophoneOffWarning = isSystemAudioListening
                updateMicrophoneLiveHandler()
                stopMicrophoneCaptureIfPossible()

                if !isSystemAudioListening {
                    shouldShowMicrophoneOffWarning = false
                    await stopStreamingSession(markStopped: true)
                } else {
                    status = .listening
                }

                SpeecharaDiagnostics.session.notice(
                    "microphone capture toggled enabled=false system=\(self.isSystemAudioListening)"
                )

                return
            }

            do {
                try await ensureStreamingSessionStarted()
                try await enableMicrophoneListening()
                meetingHistoryStartedAt = meetingHistoryStartedAt ?? Date()
                meetingHistoryEndedAt = nil
                persistDraftIfNeeded()
                meetingHistorySource = isSystemAudioListening ? "system_audio+microphone" : "microphone"
                scheduleMeetingHistorySessionStartIfNeeded()
                SpeecharaDiagnostics.session.notice(
                    "microphone capture toggled enabled=true system=\(self.isSystemAudioListening) device=\(self.selectedMicrophoneName, privacy: .public)"
                )
            } catch {
                await mixedAudioStreamMixer.setMicrophoneEnabled(false)
                stopMicrophoneCaptureIfPossible(force: true)
                isMicrophoneListening = false
                updateMicrophoneLiveHandler()
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleMicrophoneTest() {
        guard !isBusy, !isMicrophoneBusy else {
            return
        }

        isMicrophoneBusy = true

        Task { @MainActor in
            defer {
                isMicrophoneBusy = false
            }

            if isMicrophoneTesting {
                isMicrophoneTesting = false
                updateMicrophoneLiveHandler()
                stopMicrophoneCaptureIfPossible()
                return
            }

            do {
                prepareMicrophoneServiceHandlers()
                try await startMicrophoneCaptureIfNeeded()
                isMicrophoneTesting = true
                updateMicrophoneLiveHandler()
                errorMessage = nil
            } catch {
                stopMicrophoneCaptureIfPossible(force: true)
                isMicrophoneTesting = false
                updateMicrophoneLiveHandler()
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshAvailableMicrophones() {
        let devices = MicrophoneCaptureService.availableDevices()
        availableMicrophones = devices

        guard !devices.isEmpty else {
            selectedMicrophoneID = ""
            return
        }

        if devices.contains(where: { $0.id == selectedMicrophoneID }) {
            return
        }

        selectedMicrophoneID = MicrophoneCaptureService.defaultDeviceID() ?? devices[0].id
    }

    func selectMicrophone(_ deviceID: String) {
        guard selectedMicrophoneID != deviceID else {
            return
        }

        selectedMicrophoneID = deviceID

        guard isMicrophoneCaptureActive else {
            return
        }

        isMicrophoneBusy = true

        Task { @MainActor in
            defer {
                isMicrophoneBusy = false
            }

            let shouldResumeListening = isMicrophoneListening
            let shouldKeepTesting = isMicrophoneTesting

            await mixedAudioStreamMixer.setMicrophoneEnabled(false)
            microphoneCaptureService.stopCapture()
            isMicrophoneCaptureActive = false
            isMicrophoneListening = false
            microphoneLevel = 0
            microphoneSignalDetected = false

            do {
                try await startMicrophoneCaptureIfNeeded()
                isMicrophoneListening = shouldResumeListening
                isMicrophoneTesting = shouldKeepTesting
                await mixedAudioStreamMixer.setMicrophoneEnabled(shouldResumeListening)
                updateMicrophoneLiveHandler()
                errorMessage = nil
            } catch {
                isMicrophoneTesting = false
                stopMicrophoneCaptureIfPossible(force: true)
                updateMicrophoneLiveHandler()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func clearSubtitles() {
        utteranceFinalizationTask?.cancel()
        utteranceFinalizationTask = nil
        stableReconstructionTask?.cancel()
        stableReconstructionTask = nil
        sessionTurns = []
        transcriptEntries = []
        translationEntries = []
        subtitlesText = ""
        translatedText = ""
        liveSubtitlePreview = ""
        liveTranslationPreview = ""
        lastDeepgramFinalTranscript = ""
        nextStableTurnIndex = 0
        pendingTranslationDrafts.removeAll()
        translationPreviewTurnID = nil
        resetSpeakerNumbering()
        transcriptSummaryText = ""
        translationSummaryText = ""
        transcriptSummaryErrorMessage = nil
        translationSummaryErrorMessage = nil
        transcriptProtocolText = ""
        translationProtocolText = ""
        transcriptProtocolErrorMessage = nil
        translationProtocolErrorMessage = nil
        transcriptAnswerText = ""
        translationAnswerText = ""
        transcriptAnswerErrorMessage = nil
        translationAnswerErrorMessage = nil
        isTranscriptSummaryVisible = false
        isTranslationSummaryVisible = false
        isTranscriptProtocolVisible = false
        isTranslationProtocolVisible = false
        isTranscriptAnswerVisible = false
        isTranslationAnswerVisible = false
        defaults.removeObject(forKey: Self.sessionDraftDefaultsKey)
        lastSavedDraftFingerprint = ""
    }

    private func clearCurrentSessionForNewSession() {
        clearSubtitles()
        lastRecordingPath = nil
        errorMessage = nil
        translationMessage = nil
        shouldShowMicrophoneOffWarning = false
        status = .idle
    }

    private func scheduleMeetingHistorySessionStartIfNeeded() {
        guard meetingHistorySessionID == nil else {
            return
        }

        scheduleMeetingHistoryWork { [weak self] in
            await self?.ensureMeetingHistorySessionStartedIfNeeded()
        }
    }

    private func scheduleMeetingHistorySnapshotSync(status: MeetingSessionHistoryStatus) {
        scheduleMeetingHistoryWork { [weak self] in
            await self?.persistMeetingHistorySnapshot(status: status)
        }
    }

    @discardableResult
    private func completeMeetingHistoryConversationIfNeeded() async -> Bool {
        guard meetingHistoryStartedAt != nil || meetingHistorySessionID != nil || !sessionTurns.isEmpty else {
            return true
        }
        meetingHistoryAutosaveTask?.cancel()
        meetingHistoryAutosaveTask = nil
        let previousTask = meetingHistorySaveTask
        let completion = Task { @MainActor [weak self] in
            _ = await previousTask?.result
            guard let self else { return false }
            return await self.saveCompletedMeetingHistoryConversation()
        }
        meetingHistorySaveTask = Task { _ = await completion.value }
        return await completion.value
    }

    private func saveCompletedMeetingHistoryConversation() async -> Bool {
        meetingHistoryEndedAt = meetingHistoryEndedAt ?? sessionTurns.map(\.timestamp).max() ?? Date()
        persistDraftIfNeeded()
        // Save the transcript even if an unrelated speaking note cannot attach.
        let initialStatus: MeetingSessionHistoryStatus = meetingHistoryLastCompletedSnapshotSignature == nil ? .active : .completed
        guard await persistMeetingHistorySnapshot(status: initialStatus, preserveActiveStatus: true) else { return false }
        let speakingNoteReady = await SpeakingNotesStore.shared.flushAndAttach(to: meetingHistorySessionID)
        guard speakingNoteReady else {
            handleMeetingHistorySyncError(SpeakingNotesServiceError(
                message: SL("The meeting remains active in history because its speaking note could not be saved and attached."),
                code: "SPEAKING_NOTE_ATTACH_FAILED"
            ))
            return false
        }
        guard await persistMeetingHistorySnapshot(status: .completed) else { return false }
        SpeakingNotesStore.shared.setMeetingSessionID(nil)
        return true
    }

    // Called after authentication is restored, and again when the app becomes active.
    func resumeMeetingHistorySync() {
        guard !sessionTurns.isEmpty || meetingHistorySessionID != nil else { return }
        if hasActiveSession {
            scheduleMeetingHistorySnapshotSync(status: .active)
        } else {
            scheduleMeetingHistoryWork { [weak self] in
                _ = await self?.saveCompletedMeetingHistoryConversation()
            }
        }
    }

    func prepareForTermination() async {
        // Checkpoint synchronously before waiting on audio or the network.
        persistDraftIfNeeded()
        if hasActiveSession {
            await stopStreamingSession(markStopped: true, persistHistoryAsActive: false)
        }
        _ = await completeMeetingHistoryConversationIfNeeded()
        persistDraftIfNeeded()
    }

    private func scheduleThrottledMeetingHistorySync(delay: UInt64 = 3_000_000_000) {
        guard meetingHistoryAutosaveTask == nil else { return }
        meetingHistoryAutosaveTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self else { return }
            self.meetingHistoryAutosaveTask = nil
            self.resumeMeetingHistorySync()
        }
    }

    private func scheduleMeetingHistoryWork(_ operation: @escaping @MainActor () async -> Void) {
        let generation = meetingHistoryConversationGeneration
        let previousTask = meetingHistorySaveTask
        meetingHistorySaveTask = Task { [weak self] in
            _ = await previousTask?.result
            guard let self else {
                return
            }

            guard generation == self.meetingHistoryConversationGeneration else {
                return
            }

            await operation()
        }
    }

    private func ensureMeetingHistorySessionStartedIfNeeded() async {
        do { try await resolveMeetingHistorySession() }
        catch { handleMeetingHistorySyncError(error) }
    }

    private func resolveMeetingHistorySession() async throws {
        let authSession = try await AuthService.shared.activeSession()
        if let owner = meetingHistoryAuthUserID, owner != authSession.user.id {
            throw MeetingSessionHistoryServiceError.graphqlRequestFailed(
                "This local meeting belongs to another account. Sign in to that account to sync it."
            )
        }
        meetingHistoryAuthUserID = authSession.user.id
        // Checkpoint the owner and start time before any request can be interrupted.
        if meetingHistoryStartedAt == nil { meetingHistoryStartedAt = sessionTurns.map(\.timestamp).min() }
        persistDraftIfNeeded()
        if meetingHistorySessionID != nil, meetingHistorySessionRevision != nil { return }
        guard let snapshot = meetingHistorySnapshot(status: .active, allowEmptySession: true) else { return }
        let recovered = try await meetingSessionHistoryService.findRecoverableSession(
            snapshot: snapshot, allowLegacyRecovery: meetingHistoryNeedsLegacyRecovery
        )
        let remoteState: MeetingSessionHistoryRemoteState
        if let recovered {
            remoteState = recovered
            meetingHistoryStartedAt = recovered.startedAt ?? meetingHistoryStartedAt
            meetingHistorySource = recovered.source ?? meetingHistorySource
        } else {
            remoteState = try await meetingSessionHistoryService.startSession(snapshot: snapshot)
        }
        meetingHistorySessionID = remoteState.id
        meetingHistoryNeedsLegacyRecovery = false
        meetingHistorySessionRevision = remoteState.revision
        SpeakingNotesStore.shared.setMeetingSessionID(remoteState.id)
        meetingHistoryLastSavedSnapshotSignature = nil
        meetingHistoryLastCompletedSnapshotSignature = nil
        persistDraftIfNeeded()
    }

    @discardableResult
    private func persistMeetingHistorySnapshot(
        status requestedStatus: MeetingSessionHistoryStatus,
        preserveActiveStatus: Bool = false
    ) async -> Bool {
        // A queued active save must never reopen a meeting already stopped locally.
        let status: MeetingSessionHistoryStatus = !preserveActiveStatus && !hasActiveSession && meetingHistoryEndedAt != nil
            ? .completed : requestedStatus
        guard let snapshot = meetingHistorySnapshot(
            status: status,
            allowEmptySession: meetingHistoryStartedAt != nil || meetingHistorySessionID != nil
        ) else { return true }

        do {
            try await resolveMeetingHistorySession()
            guard let id = meetingHistorySessionID, let revision = meetingHistorySessionRevision else { return false }
            let lastSignature = status == .completed
                ? meetingHistoryLastCompletedSnapshotSignature : meetingHistoryLastSavedSnapshotSignature
            guard lastSignature != snapshot.signature else { return true }
            let remoteState = try await meetingSessionHistoryService.updateSession(
                id: id, revision: revision, snapshot: snapshot
            )
            meetingHistorySessionRevision = remoteState.revision
            if status == .completed { meetingHistoryLastCompletedSnapshotSignature = snapshot.signature }
            else { meetingHistoryLastSavedSnapshotSignature = snapshot.signature }
            persistDraftIfNeeded()
            meetingHistoryRetryTask?.cancel()
            meetingHistoryRetryTask = nil
            if errorMessage?.hasPrefix("Meeting history sync failed:") == true { errorMessage = nil }
            NotificationCenter.default.post(name: .speecharaMeetingHistoryDidChange, object: nil)
            return true
        } catch {
            handleMeetingHistorySyncError(error)
            return false
        }
    }

    private func meetingHistorySnapshot(
        status: MeetingSessionHistoryStatus,
        allowEmptySession: Bool
    ) -> MeetingSessionHistorySnapshot? {
        let transcriptBlocks = meetingHistoryTranscriptBlocks()
        let translationBlocks = meetingHistoryTranslationBlocks(from: transcriptBlocks)
        let summaryText = preferredMeetingHistorySummaryText
        let protocolText = preferredMeetingHistoryProtocolText
        let suggestedAnswerText = preferredMeetingHistorySuggestedAnswerText
        let hasVisibleSessionContent =
            !transcriptBlocks.isEmpty
            || !translationBlocks.isEmpty
            || summaryText != nil
            || protocolText != nil
            || suggestedAnswerText != nil

        guard allowEmptySession || hasVisibleSessionContent else {
            return nil
        }

        let startedAt = meetingHistoryStartedAt
            ?? sessionTurns.map(\.timestamp).min()
            ?? Date()

        let endedAt = status == .completed
            ? (meetingHistoryEndedAt ?? sessionTurns.map(\.timestamp).max() ?? startedAt) : nil
        let durationSeconds = max(0, Int((meetingHistoryEndedAt ?? endedAt ?? Date()).timeIntervalSince(startedAt)))

        return MeetingSessionHistorySnapshot(
            title: meetingHistoryTitle,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            status: status,
            inputLanguage: selectedSourceLanguage.deepgramLanguageCode,
            translationLanguage: isTranslationEnabled ? selectedTranslationLanguage.languageCode : nil,
            translationEnabled: isTranslationEnabled,
            recordingEnabled: isAudioRecordingEnabled,
            microphoneLabel: selectedMicrophoneName.nilIfEmpty,
            transcriptBlocks: transcriptBlocks,
            translationBlocks: translationBlocks,
            summaryText: summaryText,
            protocolText: protocolText,
            suggestedAnswerText: suggestedAnswerText,
            sessionParams: MeetingSessionHistorySessionParams(
                client: "macos",
                source: meetingHistorySource,
                appVersion: Self.currentAppVersion,
                focusMode: focusModeEnabledForHistory,
                localSessionID: meetingHistoryConversationGeneration.uuidString.lowercased()
            )
        )
    }

    private func meetingHistoryTranscriptBlocks() -> [MeetingSessionTranscriptBlock] {
        sessionTurns
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .enumerated()
            .map { index, turn in
                let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return MeetingSessionTranscriptBlock(
                id: "turn-\(turn.id.uuidString.lowercased())",
                seq: index + 1,
                timestamp: Self.transcriptTimestampFormatter.string(from: turn.timestamp),
                speakerLabel: turn.speakerLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                text: text
            )
        }
    }

    private func meetingHistoryTranslationBlocks(
        from transcriptBlocks: [MeetingSessionTranscriptBlock]
    ) -> [MeetingSessionTranslationBlock] {
        guard isTranslationEnabled else {
            return []
        }

        let transcriptBlocksByID = Dictionary(uniqueKeysWithValues: transcriptBlocks.map { ($0.id, $0) })

        return sessionTurns.compactMap { turn in
            let text = turn.translationText.trimmingCharacters(in: .whitespacesAndNewlines)
            let transcriptBlockID = "turn-\(turn.id.uuidString.lowercased())"
            guard let transcriptBlock = transcriptBlocksByID[transcriptBlockID] else {
                return nil
            }
            guard !text.isEmpty else {
                return nil
            }

            return MeetingSessionTranslationBlock(
                transcriptBlockId: transcriptBlock.id,
                seq: transcriptBlock.seq,
                language: selectedTranslationLanguage.languageCode,
                text: text
            )
        }
    }

    private var meetingHistoryTitle: String? {
        let firstTranscriptLine = sessionTurns
            .lazy
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        guard let firstTranscriptLine else {
            return nil
        }

        return String(firstTranscriptLine.prefix(120)).nilIfEmpty
    }

    private var preferredMeetingHistorySummaryText: String? {
        transcriptSummaryText.nilIfEmpty ?? translationSummaryText.nilIfEmpty
    }

    private var preferredMeetingHistoryProtocolText: String? {
        transcriptProtocolText.nilIfEmpty ?? translationProtocolText.nilIfEmpty
    }

    private var preferredMeetingHistorySuggestedAnswerText: String? {
        transcriptAnswerText.nilIfEmpty ?? translationAnswerText.nilIfEmpty
    }

    private func resetMeetingHistoryState() {
        meetingHistoryConversationGeneration = UUID()
        meetingHistorySessionID = nil
        SpeakingNotesStore.shared.setMeetingSessionID(nil)
        meetingHistorySessionRevision = nil
        meetingHistoryStartedAt = nil
        meetingHistoryEndedAt = nil
        meetingHistoryAuthUserID = nil
        meetingHistoryNeedsLegacyRecovery = false
        meetingHistoryAutosaveTask?.cancel()
        meetingHistoryAutosaveTask = nil
        meetingHistoryRetryTask?.cancel()
        meetingHistoryRetryTask = nil
        meetingHistoryLastSavedSnapshotSignature = nil
        meetingHistoryLastCompletedSnapshotSignature = nil
        meetingHistorySource = "system_audio"
        meetingHistorySaveTask = nil
        billingUsageIntervalStartedAt = nil
        billingUsageEventSequence = 1
    }

    private func handleMeetingHistorySyncError(_ error: Error) {
        let message = "Meeting history sync failed: \(error.localizedDescription)"
        SpeecharaDiagnostics.history.error("\(message, privacy: .public)")
        errorMessage = message
        persistDraftIfNeeded()
        guard meetingHistoryRetryTask == nil else { return }
        meetingHistoryRetryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            guard let self else { return }
            self.meetingHistoryRetryTask = nil
            self.resumeMeetingHistorySync()
        }
    }

    private var billingClientSessionID: String {
        "speechara-macos-session-\(meetingHistoryConversationGeneration.uuidString.lowercased())"
    }

    private func markBillingUsageStartedIfNeeded() {
        guard hasActiveAudioSource, billingUsageIntervalStartedAt == nil else {
            return
        }

        billingUsageIntervalStartedAt = Date().roundedDownToSecond()
    }

    private func scheduleBillingUsageEventSyncIfNeeded() {
        guard let usageEvent = makeBillingUsageEventIfNeeded() else {
            return
        }

        let previousTask = billingUsageSyncTask
        billingUsageSyncTask = Task { [billingService] in
            _ = await previousTask?.result
            _ = try? await billingService.reportUsageEvents([usageEvent])
        }
    }

    private func makeBillingUsageEventIfNeeded() -> SpeecharaBillingUsageEvent? {
        guard let startedAt = billingUsageIntervalStartedAt else {
            return nil
        }

        let elapsedSeconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        billingUsageIntervalStartedAt = nil

        guard elapsedSeconds > 0 else {
            return nil
        }

        let endedAt = startedAt.addingTimeInterval(TimeInterval(elapsedSeconds))
        let event = SpeecharaBillingUsageEvent(
            eventId: "\(billingClientSessionID)-\(billingUsageEventSequence)",
            meetingSessionId: meetingHistorySessionID,
            clientSessionId: billingClientSessionID,
            sourceApp: "macos",
            usageType: "live_listening",
            startedAt: startedAt.billingUsageTimestamp,
            endedAt: endedAt.billingUsageTimestamp,
            durationSeconds: elapsedSeconds
        )
        billingUsageEventSequence += 1
        return event
    }

    func updateTranscriptText(_ text: String) {
        utteranceFinalizationTask?.cancel()
        utteranceFinalizationTask = nil
        let parsedTurns = parseTranscriptEditorTurns(from: text)
        sessionTurns = parsedTurns
        nextStableTurnIndex = sessionTurns.filter(\.isClosed).count
        pendingTranslationDrafts.removeAll()
        translationPreviewTurnID = nil
        liveSubtitlePreview = ""
        liveTranslationPreview = ""
        rebuildPublishedState()
        scheduleDraftAutosave()

        Task {
            let history = translationHistoryTurns()
            await liveTranslationService.replaceHistory(with: history)
            await finalTranslationService.replaceHistory(with: history)
        }
    }

    func increaseTranscriptFontSize() {
        transcriptFontSize = min(transcriptFontSize + Self.editorFontStep, Self.maximumEditorFontSize)
    }

    func decreaseTranscriptFontSize() {
        transcriptFontSize = max(transcriptFontSize - Self.editorFontStep, Self.minimumEditorFontSize)
    }

    func increaseTranslationFontSize() {
        translationFontSize = min(translationFontSize + Self.editorFontStep, Self.maximumEditorFontSize)
    }

    func summarizeSourceText() {
        startSummary(
            target: .source,
            transcript: subtitlesText,
            inputLanguageName: selectedSourceLanguage.deepSeekLanguageName,
            outputLanguageName: sourceAIOutputLanguage.deepSeekTargetLanguageName
        )
    }

    func summarizeTranslatedText() {
        startSummary(
            target: .translation,
            transcript: translatedText,
            inputLanguageName: selectedTranslationLanguage.deepSeekTargetLanguageName,
            outputLanguageName: selectedTranslationLanguage.deepSeekTargetLanguageName
        )
    }

    func generateSourceProtocol() {
        startMeetingProtocol(
            target: .source,
            transcript: subtitlesText,
            languageName: sourceAIOutputLanguage.deepSeekTargetLanguageName
        )
    }

    func generateTranslatedProtocol() {
        startMeetingProtocol(
            target: .translation,
            transcript: translatedText,
            languageName: selectedTranslationLanguage.deepSeekTargetLanguageName
        )
    }

    func suggestSourceAnswer() {
        startAnswerAssist(
            target: .source,
            transcript: transcriptForAnswerAssist(),
            inputLanguageName: selectedSourceLanguage.deepSeekLanguageName,
            outputLanguageName: sourceAIOutputLanguage.deepSeekTargetLanguageName
        )
    }

    func suggestTranslatedAnswer() {
        startAnswerAssist(
            target: .translation,
            transcript: transcriptForAnswerAssist(),
            inputLanguageName: selectedSourceLanguage.deepSeekLanguageName,
            outputLanguageName: selectedTranslationLanguage.deepSeekTargetLanguageName
        )
    }

    func hideTranscriptSummary() {
        isTranscriptSummaryVisible = false
    }

    func hideTranslationSummary() {
        isTranslationSummaryVisible = false
    }

    func hideTranscriptProtocol() {
        isTranscriptProtocolVisible = false
    }

    func hideTranslationProtocol() {
        isTranslationProtocolVisible = false
    }

    func hideTranscriptAnswer() {
        isTranscriptAnswerVisible = false
    }

    func hideTranslationAnswer() {
        isTranslationAnswerVisible = false
    }

    func copyTranscriptToPasteboard() {
        copyToPasteboard(subtitlesText)
    }

    func copyTranslationToPasteboard() {
        copyToPasteboard(translatedText)
    }

    func copyTranscriptSummaryToPasteboard() {
        guard !transcriptSummaryText.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptSummaryText, forType: .string)
    }

    func copyTranslationSummaryToPasteboard() {
        guard !translationSummaryText.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translationSummaryText, forType: .string)
    }

    func copyTranscriptProtocolToPasteboard() {
        guard !transcriptProtocolText.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptProtocolText, forType: .string)
    }

    func copyTranslationProtocolToPasteboard() {
        guard !translationProtocolText.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translationProtocolText, forType: .string)
    }

    func copyTranscriptAnswerToPasteboard() {
        guard !transcriptAnswerText.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptAnswerText, forType: .string)
    }

    func copyTranslationAnswerToPasteboard() {
        guard !translationAnswerText.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translationAnswerText, forType: .string)
    }

    private func copyToPasteboard(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmedText, forType: .string)
    }

    func decreaseTranslationFontSize() {
        translationFontSize = max(translationFontSize - Self.editorFontStep, Self.minimumEditorFontSize)
    }

    func revealLastRecordingInFinder() {
        guard let lastRecordingPath else {
            return
        }

        let recordingURL = URL(fileURLWithPath: lastRecordingPath)
        guard FileManager.default.fileExists(atPath: recordingURL.path) else {
            errorMessage = "The saved M4A file could not be found in Finder."
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([recordingURL])
    }

    func toggleAudioRecording() {
        guard !isBusy else {
            return
        }

        guard isStreamingSessionPrepared else {
            isAudioRecordingEnabled.toggle()
            return
        }

        isBusy = true
        errorMessage = nil

        Task { @MainActor in
            defer {
                isBusy = false
            }

            if isAudioRecordingEnabled {
                do {
                    await mixedAudioStreamMixer.drainRemainingAudio()
                    let temporaryURL = try await localAudioRecordingService.finishRecording()
                    isAudioRecordingEnabled = false
                    if let temporaryURL,
                       let savedURL = try promptToSaveRecording(at: temporaryURL) {
                        lastRecordingPath = savedURL.path
                    }
                    scheduleMeetingHistorySnapshotSync(status: .active)
                } catch {
                    isAudioRecordingEnabled = false
                    errorMessage = error.localizedDescription
                }
                return
            }

            do {
                await mixedAudioStreamMixer.drainRemainingAudio()
                try await localAudioRecordingService.startRecording(isEnabled: true)
                isAudioRecordingEnabled = true
                scheduleMeetingHistorySnapshotSync(status: .active)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func promptToSaveRecording(at temporaryURL: URL) throws -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: temporaryURL.path) else {
            return nil
        }

        let savePanel = NSSavePanel()
        savePanel.title = SL("Save Recording")
        savePanel.message = SL("Choose where to save the M4A recording.")
        savePanel.nameFieldStringValue = temporaryURL.lastPathComponent
        savePanel.allowedContentTypes = [.mpeg4Audio]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false

        NSApp.activate(ignoringOtherApps: true)
        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            try? fileManager.removeItem(at: temporaryURL)
            return nil
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    func setFocusModeEnabled(_ isEnabled: Bool) {
        focusModeEnabledForHistory = isEnabled
    }

    private func configureSystemAudioRouting() {
        systemAudioCaptureService.setAudioLevelHandler { [weak self] level in
            Task { @MainActor in
                self?.applySystemAudioLevel(level)
            }
        }
        systemAudioCaptureService.setLiveAudioDataHandler { [mixedAudioStreamMixer] audioData in
            Task {
                await mixedAudioStreamMixer.appendSystemAudio(audioData)
            }
        }
    }

    private func applySystemAudioLevel(_ level: Double) {
        systemAudioLevel = level
        if level > 0.015 {
            lastSystemAudioSignalDate = Date()
            systemAudioSignalDetected = true
        } else {
            systemAudioSignalDetected = lastSystemAudioSignalDate.map {
                Date().timeIntervalSince($0) < 1.25
            } ?? false
        }
    }

    private func updateMicrophoneLiveHandler() {
        microphoneCaptureService.setLiveAudioDataHandler { [mixedAudioStreamMixer] audioData in
            Task {
                await mixedAudioStreamMixer.appendMicrophoneAudio(audioData)
            }
        }
    }

    private func configureMixedAudioOutput() async {
        await mixedAudioStreamMixer.setOutputHandler { [localAudioRecordingService, liveDeepgramService] audioData in
            await localAudioRecordingService.appendMixedAudio(audioData)
            await liveDeepgramService.sendAudio(audioData)
        }
    }

    private func applyDeepgramEvent(_ event: DeepgramTranscriptEvent) {
        switch event {
        case .interim(let result):
            let summary = SpeecharaDiagnostics.textSummary(result.transcript, limit: 180)
            SpeecharaDiagnostics.transcription.debug(
                "Deepgram interim speechFinal=\(result.speechFinal) text=\(summary, privacy: .public)"
            )
            applyInterimTranscript(result.transcript)
        case .final(let result):
            let summary = SpeecharaDiagnostics.textSummary(result.transcript, limit: 240)
            SpeecharaDiagnostics.transcription.notice(
                "Deepgram final speechFinal=\(result.speechFinal) text=\(summary, privacy: .public)"
            )
            applyFinalTranscript(result.transcript, speechFinal: result.speechFinal)
        }
    }

    private func applyInterimTranscript(_ transcript: String) {
        let normalizedTranscript = normalizedTranscriptFragment(transcript)
        guard !normalizedTranscript.isEmpty else {
            return
        }

        utteranceFinalizationTask?.cancel()
        let turnID = ensureOpenTurn()
        let confirmedText = sessionTurns.first(where: { $0.id == turnID })?.text ?? ""
        let completeDraft = mergedText(existing: confirmedText, addition: normalizedTranscript)
        liveSubtitlePreview = completeDraft
        scheduleUtteranceFinalization(for: turnID)

        guard isTranslationAvailable else {
            return
        }

        Task {
            await liveTranslationService.enqueueInterimChunk(completeDraft, turnID: turnID)
        }
    }

    private func applyFinalTranscript(_ transcript: String, speechFinal: Bool) {
        let normalizedTranscript = normalizedTranscriptFragment(transcript)
        guard !normalizedTranscript.isEmpty else {
            if speechFinal {
                lastDeepgramFinalTranscript = ""
                scheduleUtteranceFinalizationForOpenTurn()
            }
            return
        }

        utteranceFinalizationTask?.cancel()

        let delta = transcriptDelta(current: normalizedTranscript, previous: lastDeepgramFinalTranscript)
        lastDeepgramFinalTranscript = normalizedTranscript
        if speechFinal {
            // Close the transport-level ASR segment without closing the larger
            // utterance block that the user sees in the transcript.
            lastDeepgramFinalTranscript = ""
        }

        guard !delta.isEmpty else {
            if speechFinal {
                scheduleUtteranceFinalizationForOpenTurn()
            }
            return
        }

        let turnID = ensureOpenTurn()
        appendDeltaToTurn(delta, turnID: turnID)
        rebuildPublishedState()
        scheduleDraftAutosave()

        let currentTurnText = sessionTurns.first(where: { $0.id == turnID })?.text ?? delta
        let closesTurn = shouldFinalizeTurn(afterAppending: delta)
            || shouldFinalizeTurnForLength(currentTurnText)

        if isTranslationAvailable, !closesTurn {
            liveSubtitlePreview = currentTurnText
            Task {
                await liveTranslationService.enqueueInterimChunk(currentTurnText, turnID: turnID)
            }
        }

        if closesTurn {
            liveSubtitlePreview = ""
            finalizeCurrentTurnIfNeeded()
        } else {
            if !isTranslationAvailable {
                liveSubtitlePreview = currentTurnText
            }
            scheduleUtteranceFinalization(for: turnID)
        }
    }

    private func transcriptDelta(current: String, previous: String) -> String {
        let trimmedPrevious = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrevious.isEmpty else {
            return current
        }

        if current == trimmedPrevious {
            return ""
        }

        if current.hasPrefix(trimmedPrevious) {
            return current
                .dropFirst(trimmedPrevious.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if trimmedPrevious.hasPrefix(current) {
            return ""
        }

        let prefixLength = commonPrefixLength(between: trimmedPrevious, and: current)
        let suffix = current
            .dropFirst(prefixLength)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? current : suffix
    }

    private func commonPrefixLength(between left: String, and right: String) -> Int {
        var leftIndex = left.startIndex
        var rightIndex = right.startIndex

        while leftIndex < left.endIndex,
              rightIndex < right.endIndex,
              left[leftIndex] == right[rightIndex] {
            left.formIndex(after: &leftIndex)
            right.formIndex(after: &rightIndex)
        }

        return left.distance(from: left.startIndex, to: leftIndex)
    }

    private func normalizedTranscriptFragment(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ensureOpenTurn() -> UUID {
        if let lastTurn = sessionTurns.last, !lastTurn.isClosed {
            return lastTurn.id
        }

        let turn = SessionTurn(text: "", timestamp: Date(), isClosed: false)
        sessionTurns.append(turn)
        return turn.id
    }

    private func appendDeltaToTurn(_ delta: String, turnID: UUID) {
        guard let index = sessionTurns.firstIndex(where: { $0.id == turnID }) else {
            return
        }

        sessionTurns[index].text = mergedText(existing: sessionTurns[index].text, addition: delta)
    }

    private func mergedText(existing: String, addition: String) -> String {
        let trimmedAddition = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddition.isEmpty else {
            return existing
        }

        let trimmedExisting = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExisting.isEmpty else {
            return trimmedAddition
        }

        let joinsWithoutSpace = trimmedAddition.first.map {
            [".", ",", "!", "?", ":", ";", "…"].contains(String($0))
        } ?? false

        if joinsWithoutSpace || trimmedExisting.hasSuffix(" ") {
            return "\(trimmedExisting)\(trimmedAddition)"
        }

        return "\(trimmedExisting) \(trimmedAddition)"
    }

    private func shouldFinalizeTurn(afterAppending delta: String) -> Bool {
        guard let lastCharacter = delta.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }

        return [".", "!", "?", "…"].contains(lastCharacter)
    }

    private func shouldFinalizeTurnForLength(_ text: String) -> Bool {
        if text.count >= Self.maximumUtteranceCharacterCount {
            return true
        }

        return text.split(whereSeparator: \Character.isWhitespace).count
            >= Self.maximumUtteranceWordCount
    }

    private func scheduleUtteranceFinalizationForOpenTurn() {
        guard let turnID = sessionTurns.last(where: { !$0.isClosed })?.id else {
            return
        }
        scheduleUtteranceFinalization(for: turnID)
    }

    private func scheduleUtteranceFinalization(for turnID: UUID) {
        utteranceFinalizationTask?.cancel()
        utteranceFinalizationTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.utterancePauseNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled,
                  let self,
                  self.sessionTurns.last?.id == turnID,
                  self.sessionTurns.last?.isClosed == false else {
                return
            }
            self.finalizeCurrentTurnIfNeeded()
        }
    }

    private func finalizeCurrentTurnIfNeeded() {
        utteranceFinalizationTask?.cancel()
        utteranceFinalizationTask = nil
        liveSubtitlePreview = ""
        guard let lastIndex = sessionTurns.indices.last, !sessionTurns[lastIndex].isClosed else {
            lastDeepgramFinalTranscript = ""
            return
        }

        let trimmedText = sessionTurns[lastIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            sessionTurns.removeLast()
            lastDeepgramFinalTranscript = ""
            rebuildPublishedState()
            return
        }

        sessionTurns[lastIndex].text = trimmedText
        sessionTurns[lastIndex].isClosed = true
        promotePendingTranslationDraftIfAvailable(turnID: sessionTurns[lastIndex].id, turnIndex: lastIndex)

        if isTranslationAvailable {
            let turnID = sessionTurns[lastIndex].id
            Task {
                await finalTranslationService.enqueueFinalChunk(trimmedText, turnID: turnID)
            }
        }

        lastDeepgramFinalTranscript = ""
        rebuildPublishedState()
        scheduleDraftAutosave()
        // Deepgram's final result is the source of truth. A generative cleanup pass
        // must never rewrite words that the user has already seen as final.
    }

    private func promotePendingTranslationDraftIfAvailable(turnID: UUID, turnIndex: Int) {
        guard let draft = pendingTranslationDrafts.removeValue(forKey: turnID)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !draft.isEmpty else {
            return
        }

        sessionTurns[turnIndex].translationText = draft
        if translationPreviewTurnID == turnID {
            translationPreviewTurnID = nil
            liveTranslationPreview = ""
        }
        SpeecharaDiagnostics.translation.notice(
            "promoted latest preview while final translation is pending turn=\(turnID.uuidString)"
        )
    }

    private func prepareTranslationIfPossible(for generation: UUID) async {
        guard generation == streamingSessionGeneration,
              isStreamingSessionPrepared,
              !Task.isCancelled else {
            return
        }

        guard isTranslationEnabled else {
            isTranslationAvailable = false
            translationMessage = nil
            await liveTranslationService.resetSession()
            await finalTranslationService.resetSession()
            return
        }

        let startedAt = Date()
        SpeecharaDiagnostics.translation.notice(
            "background translation preparation started generation=\(generation.uuidString)"
        )

        let eventHandler: @Sendable (DeepSeekTranslationEvent) -> Void = { [weak self] event in
            Task { @MainActor in
                self?.applyTranslationEvent(event)
            }
        }

        do {
            try await liveTranslationService.startSession(
                sourceLanguageCode: selectedSourceLanguage.deepgramLanguageCode,
                sourceLanguageName: selectedSourceLanguage.deepSeekLanguageName,
                targetLanguageCode: selectedTranslationLanguage.languageCode,
                targetLanguageName: selectedTranslationLanguage.deepSeekTargetLanguageName,
                eventHandler: eventHandler
            )
            guard generation == streamingSessionGeneration,
                  isStreamingSessionPrepared,
                  !Task.isCancelled else {
                return
            }
            try await finalTranslationService.startSession(
                sourceLanguageCode: selectedSourceLanguage.deepgramLanguageCode,
                sourceLanguageName: selectedSourceLanguage.deepSeekLanguageName,
                targetLanguageCode: selectedTranslationLanguage.languageCode,
                targetLanguageName: selectedTranslationLanguage.deepSeekTargetLanguageName,
                eventHandler: eventHandler
            )
            guard generation == streamingSessionGeneration,
                  isStreamingSessionPrepared,
                  !Task.isCancelled else {
                return
            }
            isTranslationAvailable = true
            translationMessage = nil
            liveTranslationPreview = ""
            let history = translationHistoryTurns()
            await liveTranslationService.replaceHistory(with: history)
            await finalTranslationService.replaceHistory(with: history)
            await enqueueUntranslatedTurnsForTranslation(generation: generation)
            SpeecharaDiagnostics.translation.notice(
                "background translation preparation completed durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
            )
        } catch {
            guard generation == streamingSessionGeneration,
                  isStreamingSessionPrepared,
                  !Task.isCancelled else {
                return
            }
            await liveTranslationService.resetSession()
            await finalTranslationService.resetSession()
            isTranslationAvailable = false
            translationMessage = SLF("%@ translation is unavailable: %@", selectedTranslationLanguage.displayName, error.localizedDescription)
            liveTranslationPreview = ""
            SpeecharaDiagnostics.translation.error(
                "background translation preparation failed durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1_000)) error=\(error.localizedDescription)"
            )
        }
    }

    private func enqueueUntranslatedTurnsForTranslation(generation: UUID) async {
        let untranslatedTurns = sessionTurns.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.translationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !untranslatedTurns.isEmpty else {
            return
        }

        SpeecharaDiagnostics.translation.notice(
            "backfilling untranslated turns count=\(untranslatedTurns.count)"
        )
        for turn in untranslatedTurns {
            guard generation == streamingSessionGeneration,
                  isStreamingSessionPrepared,
                  isTranslationAvailable,
                  !Task.isCancelled else {
                return
            }
            if turn.isClosed {
                await finalTranslationService.enqueueFinalChunk(turn.text, turnID: turn.id)
            } else {
                await liveTranslationService.enqueueInterimChunk(turn.text, turnID: turn.id)
            }
        }
    }

    private func handleMicrophoneRuntimeError(_ message: String) {
        isMicrophoneCaptureActive = false
        isMicrophoneListening = false
        isMicrophoneTesting = false
        microphoneLevel = 0
        microphoneSignalDetected = false
        errorMessage = message

        resetMicrophoneService()
        updateMicrophoneLiveHandler()

        Task {
            await mixedAudioStreamMixer.setMicrophoneEnabled(false)

            if !self.isSystemAudioListening {
                await self.stopStreamingSession(markStopped: true)
            } else {
                self.status = .listening
            }
        }
    }

    private func applyMicrophoneLevel(_ level: Double) {
        microphoneLevel = level
        microphoneSignalDetected = level > 0.015
    }

    private func enableMicrophoneListening() async throws {
        try await startMicrophoneCaptureIfNeeded()
        await mixedAudioStreamMixer.setMicrophoneEnabled(true)
        isMicrophoneListening = true
        shouldShowMicrophoneOffWarning = false
        isMicrophoneTesting = false
        updateMicrophoneLiveHandler()
        status = .listening
        markBillingUsageStartedIfNeeded()
        errorMessage = nil
    }

    private func startMicrophoneCaptureIfNeeded() async throws {
        refreshAvailableMicrophones()

        guard !selectedMicrophoneID.isEmpty else {
            throw MicrophoneCaptureError.selectedDeviceUnavailable
        }

        guard !isMicrophoneCaptureActive else {
            return
        }

        try await microphoneCaptureService.startCapture(deviceID: selectedMicrophoneID)
        isMicrophoneCaptureActive = true
        updateMicrophoneLiveHandler()
    }

    private func ensureStreamingSessionStarted() async throws {
        guard !isStreamingSessionPrepared else {
            return
        }

        let startupStartedAt = Date()
        streamingSessionGeneration = UUID()
        let generation = streamingSessionGeneration
        refreshAvailableMicrophones()

        do {
            try await localAudioRecordingService.startRecording(isEnabled: isAudioRecordingEnabled)
            await mixedAudioStreamMixer.reset()
            await configureMixedAudioOutput()
            try await liveDeepgramService.connect(
                sourceLanguageCode: selectedSourceLanguage.deepgramLanguageCode,
                diarize: false,
                utterances: true,
                eventHandler: { [weak self] event in
                    Task { @MainActor in
                        self?.applyDeepgramEvent(event)
                    }
                },
                errorHandler: { [weak self] errorMessage in
                    Task { @MainActor in
                        self?.handleLiveTranscriptionRuntimeError(errorMessage)
                    }
                }
            )
            prepareMicrophoneServiceHandlers()
            configureSystemAudioRouting()
            updateMicrophoneLiveHandler()
            await mixedAudioStreamMixer.setMicrophoneEnabled(false)
            isTranslationAvailable = false
            liveSubtitlePreview = ""
            liveTranslationPreview = ""
            isStreamingSessionPrepared = true
            translationPreparationTask?.cancel()
            translationPreparationTask = Task { @MainActor [weak self] in
                await self?.prepareTranslationIfPossible(for: generation)
            }
            SpeecharaDiagnostics.session.notice(
                "streaming session ready for audio durationMs=\(Int(Date().timeIntervalSince(startupStartedAt) * 1_000)); translation continues in background"
            )
        } catch {
            await cleanupFailedStreamingStartup()
            throw error
        }
    }

    private func prepareMicrophoneServiceHandlers() {
        microphoneCaptureService.setErrorHandler { [weak self] errorMessage in
            Task { @MainActor in
                self?.handleMicrophoneRuntimeError(errorMessage)
            }
        }
        microphoneCaptureService.setLevelHandler { [weak self] level in
            Task { @MainActor in
                self?.applyMicrophoneLevel(level)
            }
        }
    }

    private func stopMicrophoneCaptureIfPossible(force: Bool = false) {
        guard isMicrophoneCaptureActive else {
            return
        }

        guard force || (!isMicrophoneListening && !isMicrophoneTesting) else {
            return
        }

        microphoneCaptureService.stopCapture()
        isMicrophoneCaptureActive = false
        microphoneLevel = 0
        microphoneSignalDetected = false
        updateMicrophoneLiveHandler()
    }

    private func handleLiveTranscriptionRuntimeError(_ message: String) {
        SpeecharaDiagnostics.transcription.error("runtime error message=\(message) prepared=\(self.isStreamingSessionPrepared)")
        let interruptionMessage = "Live transcription was interrupted: \(message)"
        errorMessage = interruptionMessage

        guard isStreamingSessionPrepared, !isHandlingLiveTranscriptionRuntimeError else {
            return
        }

        isHandlingLiveTranscriptionRuntimeError = true

        Task { @MainActor in
            await stopStreamingSession(markStopped: true)
            errorMessage = interruptionMessage
            isHandlingLiveTranscriptionRuntimeError = false
        }
    }

    private func stopSystemAudioListening(markStopped: Bool) async {
        var stopError: Error?

        if isSystemAudioListening {
            do {
                _ = try await systemAudioCaptureService.stopCapture()
            } catch {
                stopError = error
            }
        }

        isSystemAudioListening = false
        systemAudioLevel = 0
        systemAudioSignalDetected = false
        lastSystemAudioSignalDate = nil

        if !hasActiveAudioSource {
            await stopStreamingSession(markStopped: markStopped)
        } else {
            status = .listening
            scheduleMeetingHistorySnapshotSync(status: .active)

            if let stopError {
                errorMessage = stopError.localizedDescription
            }
        }
    }

    private func stopStreamingSession(markStopped: Bool, persistHistoryAsActive: Bool = true) async {
        SpeecharaDiagnostics.session.notice("stopStreamingSession begin markStopped=\(markStopped) persistHistoryAsActive=\(persistHistoryAsActive) prepared=\(self.isStreamingSessionPrepared) system=\(self.isSystemAudioListening) mic=\(self.isMicrophoneListening)")
        var stopError: Error?
        meetingHistoryEndedAt = meetingHistoryEndedAt ?? Date()
        persistDraftIfNeeded()

        stableReconstructionTask?.cancel()
        stableReconstructionTask = nil
        translationPreparationTask?.cancel()
        translationPreparationTask = nil
        streamingSessionGeneration = UUID()
        resetMicrophoneService()
        isMicrophoneCaptureActive = false
        isMicrophoneListening = false
        shouldShowMicrophoneOffWarning = false
        isMicrophoneTesting = false
        microphoneLevel = 0
        microphoneSignalDetected = false
        await mixedAudioStreamMixer.setMicrophoneEnabled(false)

        if isSystemAudioListening {
            do {
                _ = try await systemAudioCaptureService.stopCapture()
            } catch {
                stopError = error
            }
        }

        isSystemAudioListening = false
        systemAudioCaptureService.setLiveAudioDataHandler(nil)
        systemAudioCaptureService.setAudioLevelHandler(nil)
        systemAudioLevel = 0
        systemAudioSignalDetected = false
        lastSystemAudioSignalDate = nil

        if isStreamingSessionPrepared {
            try? await Task.sleep(nanoseconds: 50_000_000)
            await mixedAudioStreamMixer.drainRemainingAudio()
        }

        let outputURL: URL?
        if isStreamingSessionPrepared {
            do {
                outputURL = try await localAudioRecordingService.finishRecording()
            } catch {
                if stopError == nil {
                    stopError = error
                }
                outputURL = nil
            }
        } else {
            outputURL = nil
        }

        await liveDeepgramService.stop()
        commitPendingTranslationDrafts()
        finalizeCurrentTurnIfNeeded()
        await liveTranslationService.resetSession()
        await finalTranslationService.resetSession()
        await mixedAudioStreamMixer.reset()
        isTranslationAvailable = false
        isStreamingSessionPrepared = false
        if let outputURL {
            do {
                if let savedURL = try promptToSaveRecording(at: outputURL) {
                    lastRecordingPath = savedURL.path
                }
            } catch {
                if stopError == nil {
                    stopError = error
                }
                try? FileManager.default.removeItem(at: outputURL)
            }
        }
        liveSubtitlePreview = ""
        liveTranslationPreview = ""
        pendingTranslationDrafts.removeAll()
        translationPreviewTurnID = nil
        lastDeepgramFinalTranscript = ""
        scheduleBillingUsageEventSyncIfNeeded()
        status = markStopped ? .stopped : .idle
        persistDraftIfNeeded()
        if persistHistoryAsActive {
            scheduleMeetingHistoryWork { [weak self] in
                guard let self else { return }
                _ = await self.saveCompletedMeetingHistoryConversation()
            }
        }

        if let stopError {
            errorMessage = stopError.localizedDescription
        }
    }

    private func cleanupFailedStreamingStartup() async {
        translationPreparationTask?.cancel()
        translationPreparationTask = nil
        streamingSessionGeneration = UUID()
        systemAudioCaptureService.setLiveAudioDataHandler(nil)
        systemAudioCaptureService.setAudioLevelHandler(nil)
        resetMicrophoneService()
        await liveDeepgramService.stop()
        await liveTranslationService.resetSession()
        await finalTranslationService.resetSession()
        await localAudioRecordingService.cancel()
        await mixedAudioStreamMixer.reset()
        isTranslationAvailable = false
        if isSystemAudioListening {
            _ = try? await systemAudioCaptureService.stopCapture()
        }
        isStreamingSessionPrepared = false
        isSystemAudioListening = false
        systemAudioLevel = 0
        systemAudioSignalDetected = false
        lastSystemAudioSignalDate = nil
        isMicrophoneCaptureActive = false
        isMicrophoneListening = false
        isMicrophoneTesting = false
        microphoneLevel = 0
        microphoneSignalDetected = false
        pendingTranslationDrafts.removeAll()
        translationPreviewTurnID = nil
        lastDeepgramFinalTranscript = ""
    }

    private func resetMicrophoneService() {
        microphoneCaptureService.setLiveAudioDataHandler(nil)
        microphoneCaptureService.setErrorHandler(nil)
        microphoneCaptureService.setLevelHandler(nil)
        microphoneCaptureService.stopCapture()
        microphoneCaptureService = MicrophoneCaptureService()
    }

    private func applyTranslationEvent(_ event: DeepSeekTranslationEvent) {
        switch event {
        case .preview(let turnID, let translation):
            guard isTranslationOutputCompatible(translation, kind: "preview", turnID: turnID) else {
                return
            }
            if let turn = sessionTurns.first(where: { $0.id == turnID }),
               turn.isClosed {
                SpeecharaDiagnostics.translation.debug(
                    "ignored late preview for closed turn=\(turnID.uuidString)"
                )
                return
            }
            pendingTranslationDrafts[turnID] = translation
            translationPreviewTurnID = turnID
            liveTranslationPreview = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        case .completed(let turnID, let translation):
            guard isTranslationOutputCompatible(translation, kind: "final", turnID: turnID) else {
                return
            }
            pendingTranslationDrafts.removeValue(forKey: turnID)
            if translationPreviewTurnID == turnID {
                translationPreviewTurnID = nil
                liveTranslationPreview = ""
            }
            applyCompletedTranslationChunk(translation, to: turnID)
        case .failed(let message):
            if let translationPreviewTurnID {
                pendingTranslationDrafts.removeValue(forKey: translationPreviewTurnID)
                self.translationPreviewTurnID = nil
            }
            isTranslationAvailable = false
            liveTranslationPreview = ""
            translationMessage = SLF("%@ translation was paused: %@", selectedTranslationLanguage.displayName, message)
            rebuildPublishedState()

            Task {
                await liveTranslationService.resetSession()
                await finalTranslationService.resetSession()
            }
        }
    }

    private func isTranslationOutputCompatible(
        _ translation: String,
        kind: String,
        turnID: UUID
    ) -> Bool {
        let targetCode = selectedTranslationLanguage.languageCode
        guard SpeecharaTranslationOutputValidator.isCompatible(
            translation,
            targetLanguageCode: targetCode
        ) else {
            let summary = SpeecharaDiagnostics.textSummary(translation, limit: 120)
            SpeecharaDiagnostics.translation.error(
                "rejected \(kind, privacy: .public) translation with unexpected script turn=\(turnID.uuidString, privacy: .public) target=\(targetCode, privacy: .public) output=\(summary, privacy: .public)"
            )
            return false
        }
        return true
    }

    private func applyCompletedTranslationChunk(_ translation: String, to turnID: UUID) {
        guard let index = sessionTurns.firstIndex(where: { $0.id == turnID }) else {
            return
        }

        sessionTurns[index].translationText = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        rebuildPublishedState()
        scheduleDraftAutosave()

        let history = translationHistoryTurns()
        Task {
            await liveTranslationService.replaceHistory(with: history)
            await finalTranslationService.replaceHistory(with: history)
        }
    }

    private func commitPendingTranslationDrafts() {
        guard !pendingTranslationDrafts.isEmpty else {
            return
        }

        for (turnID, draft) in pendingTranslationDrafts {
            let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDraft.isEmpty,
                  let index = sessionTurns.firstIndex(where: { $0.id == turnID }) else {
                continue
            }

            sessionTurns[index].translationText = mergedText(
                existing: sessionTurns[index].translationText,
                addition: trimmedDraft
            )
        }

        pendingTranslationDrafts.removeAll()
        translationPreviewTurnID = nil
        liveTranslationPreview = ""
        rebuildPublishedState()
        scheduleDraftAutosave()
    }

    private func resetSpeakerNumbering() {
        speakerLabelToNumber.removeAll()
        speakerNumberToLabel.removeAll()
        nextSpeakerNumber = 1
    }

    private func speakerLabel(for speakerNumber: Int) -> String {
        speakerNumberToLabel[speakerNumber] ?? SLF("Speaker %@", String(speakerNumber))
    }

    private func renderText(from entries: [DialogueEntry], useDialogueLabels: Bool, includeTimestamps: Bool) -> String {
        entries
            .map { entry in
                let content: String
                guard useDialogueLabels, let speakerNumber = entry.speakerNumber else {
                    content = entry.text
                    if includeTimestamps {
                        return "[\(Self.transcriptTimestampFormatter.string(from: entry.timestamp))] \(content)"
                    }
                    return content
                }

                content = "\(speakerLabel(for: speakerNumber)): \(entry.text)"
                if includeTimestamps {
                    return "[\(Self.transcriptTimestampFormatter.string(from: entry.timestamp))] \(content)"
                }
                return content
            }
            .joined(separator: "\n")
    }

    private func speakerNumber(for label: String?) -> Int? {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else {
            return nil
        }

        if let existing = speakerLabelToNumber[label] {
            return existing
        }

        let nextNumber = nextSpeakerNumber
        nextSpeakerNumber += 1
        speakerLabelToNumber[label] = nextNumber
        speakerNumberToLabel[nextNumber] = label
        return nextNumber
    }

    private func rebuildPublishedState() {
        normalizeAccidentalTranslationSpeakerLabels()
        removeUnsupportedSpeakerLabels()
        resetSpeakerNumbering()

        transcriptEntries = sessionTurns.compactMap { turn in
            guard turn.isClosed else {
                return nil
            }
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }

            return DialogueEntry(
                id: turn.id,
                speakerNumber: speakerNumber(for: turn.speakerLabel),
                text: text,
                timestamp: turn.timestamp
            )
        }

        translationEntries = sessionTurns.compactMap { turn in
            guard turn.isClosed else {
                return nil
            }
            let committedTranslation = restoredPlainTranslationText(for: turn)
            guard !committedTranslation.isEmpty else {
                return nil
            }

            return DialogueEntry(
                id: turn.id,
                speakerNumber: speakerNumber(for: turn.speakerLabel),
                text: committedTranslation,
                timestamp: turn.timestamp
            )
        }

        subtitlesText = renderText(
            from: transcriptEntries,
            useDialogueLabels: showsTranscriptDialogueMode,
            includeTimestamps: true
        )
        translatedText = renderText(
            from: translationEntries,
            useDialogueLabels: showsTranslationDialogueMode,
            includeTimestamps: true
        )
    }

    private func restoredPlainTranslationText(for turn: SessionTurn) -> String {
        let text = turn.translationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard turn.speakerLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty == nil,
              let accidentalLabel = turn.translationSpeakerLabel?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty else {
            return text
        }

        guard !text.isEmpty else {
            return accidentalLabel
        }
        return "\(accidentalLabel): \(text)"
    }

    private func normalizeAccidentalTranslationSpeakerLabels() {
        for index in sessionTurns.indices {
            guard sessionTurns[index].speakerLabel?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty == nil,
                let accidentalLabel = sessionTurns[index].translationSpeakerLabel?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty else {
                continue
            }

            let text = sessionTurns[index].translationText.trimmingCharacters(in: .whitespacesAndNewlines)
            sessionTurns[index].translationText = text.isEmpty
                ? accidentalLabel
                : "\(accidentalLabel): \(text)"
            sessionTurns[index].translationSpeakerLabel = nil
        }
    }

    private func removeUnsupportedSpeakerLabels() {
        // Deepgram diarization is intentionally disabled for this client. Until the
        // app has a real speaker-identification source, labels inferred by an AI
        // cleanup pass are misleading and must never reach the UI or saved history.
        for index in sessionTurns.indices {
            sessionTurns[index].speakerLabel = nil
            sessionTurns[index].translationSpeakerLabel = nil
        }
    }

    private func parseTranscriptEditorTurns(from text: String) -> [SessionTurn] {
        resetSpeakerNumbering()

        var turns = [SessionTurn]()
        var pendingTimestamp: Date?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            if let inlineTimestampMatch = line.firstMatch(of: /^\[(\d{2}):(\d{2}):(\d{2})\]\s*(.*)$/),
               !String(inlineTimestampMatch.4).isEmpty {
                pendingTimestamp = parsedTimestamp(
                    hours: String(inlineTimestampMatch.1),
                    minutes: String(inlineTimestampMatch.2),
                    seconds: String(inlineTimestampMatch.3)
                )
                let content = String(inlineTimestampMatch.4)
                turns.append(makeTurn(fromDisplayLine: content, timestamp: pendingTimestamp))
                pendingTimestamp = nil
                continue
            }

            if let timeOnlyMatch = line.firstMatch(of: /^\[(\d{2}):(\d{2}):(\d{2})\]$/) {
                pendingTimestamp = parsedTimestamp(
                    hours: String(timeOnlyMatch.1),
                    minutes: String(timeOnlyMatch.2),
                    seconds: String(timeOnlyMatch.3)
                )
                continue
            }

            turns.append(makeTurn(fromDisplayLine: line, timestamp: pendingTimestamp))
            pendingTimestamp = nil
        }

        return turns
    }

    private func makeTurn(fromDisplayLine line: String, timestamp: Date?) -> SessionTurn {
        if let labelMatch = line.firstMatch(of: /^([^:\[][^:]{0,80}):\s*(.*)$/) {
            let label = String(labelMatch.1).trimmingCharacters(in: .whitespacesAndNewlines)
            let text = String(labelMatch.2).trimmingCharacters(in: .whitespacesAndNewlines)
            return SessionTurn(
                speakerLabel: label.isEmpty ? nil : label,
                text: text,
                timestamp: timestamp ?? Date(),
                isClosed: true
            )
        }

        return SessionTurn(
            speakerLabel: nil,
            text: line,
            timestamp: timestamp ?? Date(),
            isClosed: true
        )
    }

    private func transcriptForAnswerAssist() -> String {
        let renderedTranscript = sessionTurns
            .map { turn in
                if let speakerLabel = turn.speakerLabel, !speakerLabel.isEmpty {
                    return "\(speakerLabel): \(turn.text)"
                }

                return turn.text
            }
            .joined(separator: "\n")

        let trimmedRenderedTranscript = renderedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRenderedTranscript.isEmpty {
            return trimmedRenderedTranscript
        }

        return subtitlesText
    }

    private var hasActiveAudioSource: Bool {
        isSystemAudioListening || isMicrophoneListening
    }

    private func parsedTimestamp(hours: String, minutes: String, seconds: String) -> Date {
        let now = Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = Int(hours)
        components.minute = Int(minutes)
        components.second = Int(seconds)
        return Calendar.current.date(from: components) ?? now
    }

    private func translationHistoryTurns() -> [DeepSeekTranslationHistoryTurn] {
        sessionTurns.compactMap { turn in
            let source = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let translation = turn.translationText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty, !translation.isEmpty else {
                return nil
            }

            return DeepSeekTranslationHistoryTurn(source: source, translation: translation)
        }
    }

    private func scheduleStableReconstructionIfNeeded() {
        stableReconstructionTask?.cancel()

        let stableCount = sessionTurns.filter(\.isClosed).count
        guard stableCount > nextStableTurnIndex else {
            return
        }

        stableReconstructionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.stableReconstructionDelayNanoseconds)
            await self?.performStableReconstructionIfNeeded()
        }
    }

    private func performStableReconstructionIfNeeded() async {
        guard isStreamingSessionPrepared, !Task.isCancelled else {
            return
        }
        if !pendingTranslationDrafts.isEmpty || !liveTranslationPreview.isEmpty {
            scheduleStableReconstructionIfNeeded()
            return
        }

        guard let selection = stableWindowSelection() else {
            return
        }

        let snapshot = Array(sessionTurns[selection.range])
        let signature = stableWindowSignature(snapshot)

        do {
            var reconstructedTurns = try await reconstructStableTurns(snapshot)

            if isTranslationAvailable {
                reconstructedTurns = try await translatedStableTurns(reconstructedTurns)
            }

            guard isStreamingSessionPrepared,
                  !Task.isCancelled,
                  stableWindowStillMatches(signature: signature, range: selection.range) else {
                return
            }

            sessionTurns.replaceSubrange(selection.range, with: reconstructedTurns)
            nextStableTurnIndex = selection.stableStartOffset + reconstructedTurns.count
            rebuildPublishedState()
            scheduleDraftAutosave()
            if isTranslationAvailable {
                let history = translationHistoryTurns()
                await liveTranslationService.replaceHistory(with: history)
                await finalTranslationService.replaceHistory(with: history)
            }
        } catch {
            return
        }

        if sessionTurns.filter(\.isClosed).count > nextStableTurnIndex {
            scheduleStableReconstructionIfNeeded()
        }
    }

    private func stableWindowSelection() -> (range: Range<Int>, stableStartOffset: Int)? {
        let stableIndices = sessionTurns.indices.filter { sessionTurns[$0].isClosed }
        guard nextStableTurnIndex < stableIndices.count else {
            return nil
        }

        let stableStartOffset = max(0, nextStableTurnIndex - Self.stableReconstructionContextLines)
        let stableEndOffset = min(stableIndices.count, nextStableTurnIndex + Self.stableReconstructionBatchLines)
        guard stableStartOffset < stableEndOffset else {
            return nil
        }

        let lowerBound = stableIndices[stableStartOffset]
        let upperBound = stableIndices[stableEndOffset - 1] + 1
        return (lowerBound ..< upperBound, stableStartOffset)
    }

    private func stableWindowSignature(_ turns: [SessionTurn]) -> String {
        turns
            .map { turn in
                let timestamp = Self.transcriptTimestampFormatter.string(from: turn.timestamp)
                return "\(turn.id.uuidString)|\(timestamp)|\(turn.speakerLabel ?? "")|\(turn.text)|\(turn.isClosed)"
            }
            .joined(separator: "||")
    }

    private func stableWindowStillMatches(signature: String, range: Range<Int>) -> Bool {
        guard range.lowerBound >= 0, range.upperBound <= sessionTurns.count else {
            return false
        }

        return stableWindowSignature(Array(sessionTurns[range])) == signature
    }

    private func reconstructStableTurns(_ turns: [SessionTurn]) async throws -> [SessionTurn] {
        let inputLines = turns.map { turn in
            let timestamp = Self.transcriptTimestampFormatter.string(from: turn.timestamp)
            if let speakerLabel = turn.speakerLabel, !speakerLabel.isEmpty {
                return "[\(timestamp)] \(speakerLabel): \(turn.text)"
            }

            return "[\(timestamp)] \(turn.text)"
        }
        let joinedInput = inputLines.joined(separator: "\n")

        let completion = try await speecharaAIProxyService.performChatCompletion(
            SpeecharaChatCompletionRequest(
                model: "deepseek-chat",
                messages: [
                    SpeecharaChatMessage(
                        role: "system",
                        content: """
                        Reconstruct clean readable dialogue from raw live STT.
                        Fix only obvious transcription mistakes and punctuation.
                        Preserve chronology, timestamps, and exactly one output item per input line.
                        Never infer, identify, split, merge, or add speakers. Do not add speaker labels.
                        Return ONLY valid JSON in this exact shape:
                        [{"timestamp":"HH:mm:ss","text":"clean text"}]
                        No markdown, no explanations, no code fences.
                        """
                    ),
                    SpeecharaChatMessage(
                        role: "user",
                        content: """
                        Reconstruct this stable dialogue window:

                        \(joinedInput)
                        """
                    ),
                ],
                temperature: 0,
                maxTokens: 900,
                stream: false
            )
        )

        guard let content = completion.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            return turns
        }

        let cleanedPayload = stripMarkdownCodeFence(from: content)
        guard let payloadData = cleanedPayload.data(using: .utf8),
              let reconstructedLines = try? JSONDecoder().decode([StructuredDialogueLine].self, from: payloadData),
              reconstructedLines.count == turns.count else {
            return turns
        }

        return turns.enumerated().map { offset, originalTurn in
            let line = reconstructedLines[offset]
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var updatedTurn = originalTurn
            updatedTurn.speakerLabel = nil
            updatedTurn.translationSpeakerLabel = nil
            updatedTurn.text = text.isEmpty ? originalTurn.text : text
            return updatedTurn
        }
    }

    private func translatedStableTurns(_ turns: [SessionTurn]) async throws -> [SessionTurn] {
        guard !turns.isEmpty else {
            return turns
        }

        let sourceBlock = turns.map { turn in
            let timestamp = Self.transcriptTimestampFormatter.string(from: turn.timestamp)
            if let speakerLabel = turn.speakerLabel, !speakerLabel.isEmpty {
                return "[\(timestamp)] \(speakerLabel): \(turn.text)"
            }
            return "[\(timestamp)] \(turn.text)"
        }
        .joined(separator: "\n")

        let translatedBlock = try await finalTranslationService.translateStableBlock(sourceBlock, history: [])
        let translatedLines = parseTranslatedStableLines(from: translatedBlock)
        guard translatedLines.count == turns.count else {
            return turns
        }

        return turns.enumerated().map { offset, turn in
            var updatedTurn = turn
            let translatedLine = translatedLines[offset]
            if turn.speakerLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil {
                updatedTurn.translationSpeakerLabel = translatedLine.speakerLabel
                updatedTurn.translationText = translatedLine.text
            } else {
                updatedTurn.translationSpeakerLabel = nil
                if let accidentalLabel = translatedLine.speakerLabel {
                    updatedTurn.translationText = "\(accidentalLabel): \(translatedLine.text)"
                } else {
                    updatedTurn.translationText = translatedLine.text
                }
            }
            return updatedTurn
        }
    }

    private func parseTranslatedStableLines(from text: String) -> [(speakerLabel: String?, text: String)] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { rawLine in
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else {
                    return nil
                }

                let withoutTimestamp: String
                if let timestampMatch = line.firstMatch(of: /^\[(\d{2}):(\d{2}):(\d{2})\]\s*(.*)$/) {
                    withoutTimestamp = String(timestampMatch.4)
                } else {
                    withoutTimestamp = line
                }

                if let labelMatch = withoutTimestamp.firstMatch(of: /^([^:\[][^:]{0,80}):\s*(.*)$/) {
                    let label = String(labelMatch.1).trimmingCharacters(in: .whitespacesAndNewlines)
                    let text = String(labelMatch.2).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (label.nilIfEmpty, text)
                }

                return (nil, withoutTimestamp)
            }
    }

    private func stripMarkdownCodeFence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else {
            return trimmed
        }

        let withoutOpeningFence: String
        if let newlineIndex = trimmed.firstIndex(of: "\n") {
            withoutOpeningFence = String(trimmed[trimmed.index(after: newlineIndex)...])
        } else {
            withoutOpeningFence = trimmed
        }

        let withoutClosingFence: String
        if withoutOpeningFence.hasSuffix("```") {
            withoutClosingFence = String(withoutOpeningFence.dropLast(3))
        } else {
            withoutClosingFence = withoutOpeningFence
        }

        return withoutClosingFence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parsedTimestampString(_ timestamp: String) -> Date? {
        let trimmedTimestamp = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmedTimestamp.firstMatch(of: /^(\d{2}):(\d{2}):(\d{2})$/) else {
            return nil
        }

        return parsedTimestamp(
            hours: String(match.1),
            minutes: String(match.2),
            seconds: String(match.3)
        )
    }

    private func scheduleDraftAutosave() {
        persistDraftIfNeeded()
        scheduleThrottledMeetingHistorySync()
    }

    private func persistDraftIfNeeded() {
        let fingerprint = draftFingerprint()
        guard fingerprint != lastSavedDraftFingerprint else {
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(makeSessionDraft()) else {
            return
        }

        defaults.set(data, forKey: Self.sessionDraftDefaultsKey)
        lastSavedDraftFingerprint = fingerprint
    }

    private func restoreDraftIfAvailable() {
        guard let data = defaults.data(forKey: Self.sessionDraftDefaultsKey) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let draft = try? decoder.decode(SessionDraft.self, from: data) else {
            return
        }

        applyDraft(draft)
        lastSavedDraftFingerprint = draftFingerprint()
    }

    private func applyDraft(_ draft: SessionDraft) {
        if let history = draft.history {
            meetingHistorySessionID = history.sessionID
            meetingHistorySessionRevision = history.revision
            meetingHistoryStartedAt = history.startedAt
            meetingHistoryEndedAt = history.endedAt ?? draft.turns.map(\.timestamp).max()
            meetingHistorySource = history.source
            meetingHistoryConversationGeneration = history.conversationID
            meetingHistoryAuthUserID = history.authUserID
            meetingHistoryNeedsLegacyRecovery = history.needsLegacyRecovery ?? false
            selectedSourceLanguage = SourceLanguageOption.supported(code: history.inputLanguage) ?? selectedSourceLanguage
            selectedTranslationLanguage = TranslationLanguageOption.supported(code: history.translationLanguage) ?? selectedTranslationLanguage
            isTranslationEnabled = history.translationEnabled
            isAudioRecordingEnabled = history.recordingEnabled
        } else {
            meetingHistoryNeedsLegacyRecovery = true
            meetingHistoryStartedAt = draft.turns.map(\.timestamp).min()
            meetingHistoryEndedAt = draft.turns.map(\.timestamp).max()
        }
        resetSpeakerNumbering()
        sessionTurns = draft.turns.map { turn in
            if let label = turn.speakerLabel {
                _ = speakerNumber(for: label)
            }
            if let translationLabel = turn.translationSpeakerLabel {
                _ = speakerNumber(for: translationLabel)
            }

            return SessionTurn(
                id: turn.id,
                speakerLabel: turn.speakerLabel,
                text: turn.text,
                translationSpeakerLabel: turn.translationSpeakerLabel,
                translationText: turn.translationText,
                timestamp: turn.timestamp,
                isClosed: turn.isClosed
            )
        }
        transcriptSummaryText = draft.transcriptSummaryText
        translationSummaryText = draft.translationSummaryText
        transcriptProtocolText = draft.transcriptProtocolText
        translationProtocolText = draft.translationProtocolText
        transcriptAnswerText = draft.transcriptAnswerText
        translationAnswerText = draft.translationAnswerText
        nextStableTurnIndex = sessionTurns.filter(\.isClosed).count
        rebuildPublishedState()
    }

    private func draftFingerprint() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: (try? encoder.encode(makeSessionDraft())) ?? Data(), as: UTF8.self)
    }

    private func makeSessionDraft() -> SessionDraft {
        SessionDraft(
            history: MeetingHistoryCheckpoint(
                sessionID: meetingHistorySessionID,
                revision: meetingHistorySessionRevision,
                startedAt: meetingHistoryStartedAt,
                endedAt: meetingHistoryEndedAt,
                source: meetingHistorySource,
                conversationID: meetingHistoryConversationGeneration,
                authUserID: meetingHistoryAuthUserID,
                needsLegacyRecovery: meetingHistoryNeedsLegacyRecovery,
                inputLanguage: selectedSourceLanguage.deepgramLanguageCode,
                translationLanguage: selectedTranslationLanguage.languageCode,
                translationEnabled: isTranslationEnabled,
                recordingEnabled: isAudioRecordingEnabled
            ),
            turns: sessionTurns.map { turn in
                SessionDraft.DraftTurn(
                    id: turn.id,
                    speakerLabel: turn.speakerLabel,
                    text: turn.text,
                    translationSpeakerLabel: turn.translationSpeakerLabel,
                    translationText: turn.translationText,
                    timestamp: turn.timestamp,
                    isClosed: turn.isClosed
                )
            },
            subtitlesText: subtitlesText,
            translatedText: translatedText,
            transcriptSummaryText: transcriptSummaryText,
            translationSummaryText: translationSummaryText,
            transcriptProtocolText: transcriptProtocolText,
            translationProtocolText: translationProtocolText,
            transcriptAnswerText: transcriptAnswerText,
            translationAnswerText: translationAnswerText
        )
    }

    private func localFallbackSummary(from transcript: String) -> String {
        let lines = cleanedTranscriptLines(from: transcript)
        let bullets = Array(lines.prefix(12))
        guard !bullets.isEmpty else {
            return transcript
        }

        return bullets
            .map { "- \($0)" }
            .joined(separator: "\n")
    }

    private func localFallbackProtocol(from transcript: String) -> String {
        let lines = cleanedTranscriptLines(from: transcript)
        guard !lines.isEmpty else {
            return transcript
        }

        let decisions = lines.filter {
            let lowercased = $0.lowercased()
            return lowercased.contains("decide") || lowercased.contains("agreed") || lowercased.contains("will ")
        }
        let questions = lines.filter { $0.contains("?") }
        let topics = Array(lines.prefix(8))

        return [
            "Meeting Notes",
            "",
            "1. Topics Discussed",
            topics.map { "- \($0)" }.joined(separator: "\n"),
            "",
            "2. Decisions Made",
            (decisions.isEmpty ? ["- No explicit decisions detected in the local fallback."] : decisions.map { "- \($0)" }).joined(separator: "\n"),
            "",
            "3. Open Questions",
            (questions.isEmpty ? ["- No explicit open questions detected in the local fallback."] : questions.map { "- \($0)" }).joined(separator: "\n"),
        ]
        .joined(separator: "\n")
    }

    private func localFallbackAnswer(from transcript: String) -> String {
        let lines = cleanedTranscriptLines(from: transcript)
        guard let lastLine = lines.last else {
            return transcript
        }

        if let lastQuestion = lines.last(where: { $0.contains("?") }) {
            return """
            A concise fallback answer can acknowledge the latest question and respond to its main point directly.

            Latest question:
            \(lastQuestion)

            Most recent context:
            \(lastLine)
            """
        }

        return """
        A safe fallback answer is to confirm the latest point and add the most recent concrete detail from the conversation.

        Latest context:
        \(lastLine)
        """
    }

    private func cleanedTranscriptLines(from transcript: String) -> [String] {
        transcript
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { rawLine in
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                return stripLeadingTimestamp(from: line)
            }
            .map {
                $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private func stripLeadingTimestamp(from line: String) -> String {
        if let timestampMatch = line.firstMatch(of: /^\[(\d{2}):(\d{2}):(\d{2})\]\s*(.*)$/) {
            return String(timestampMatch.4)
        }

        return line
    }

    private func startSummary(
        target: SummaryTarget,
        transcript: String,
        inputLanguageName: String,
        outputLanguageName: String
    ) {
        guard !isTranscriptSummaryLoading,
              !isTranslationSummaryLoading,
              !isTranscriptProtocolLoading,
              !isTranslationProtocolLoading,
              !isTranscriptAnswerLoading,
              !isTranslationAnswerLoading else {
            return
        }

        switch target {
        case .source where !transcriptSummaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            isTranscriptSummaryVisible = true
            return
        case .translation where !translationSummaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            isTranslationSummaryVisible = true
            return
        default:
            break
        }

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return
        }

        let summaryGeneration = meetingHistoryConversationGeneration

        switch target {
        case .source:
            isTranscriptProtocolVisible = false
            isTranscriptAnswerVisible = false
            transcriptSummaryText = ""
            transcriptSummaryErrorMessage = nil
            isTranscriptSummaryVisible = true
            isTranscriptSummaryLoading = true
        case .translation:
            isTranslationProtocolVisible = false
            isTranslationAnswerVisible = false
            translationSummaryText = ""
            translationSummaryErrorMessage = nil
            isTranslationSummaryVisible = true
            isTranslationSummaryLoading = true
        }

        Task { @MainActor in
            defer {
                switch target {
                case .source:
                    isTranscriptSummaryLoading = false
                case .translation:
                    isTranslationSummaryLoading = false
                }
            }

            do {
                let summary = try await deepSeekSummaryService.summarize(
                    transcript: trimmedTranscript,
                    inputLanguageName: inputLanguageName,
                    outputLanguageName: outputLanguageName
                )
                guard summaryGeneration == meetingHistoryConversationGeneration else {
                    return
                }
                switch target {
                case .source:
                    transcriptSummaryText = summary
                    transcriptSummaryErrorMessage = nil
                case .translation:
                    translationSummaryText = summary
                    translationSummaryErrorMessage = nil
                }
                scheduleMeetingHistorySnapshotSync(status: .active)
            } catch {
                let fallback = localFallbackSummary(from: trimmedTranscript)
                guard summaryGeneration == meetingHistoryConversationGeneration else {
                    return
                }
                switch target {
                case .source:
                    transcriptSummaryText = fallback
                    transcriptSummaryErrorMessage = "AI summary failed, showing a local fallback instead."
                case .translation:
                    translationSummaryText = fallback
                    translationSummaryErrorMessage = "AI summary failed, showing a local fallback instead."
                }
                scheduleMeetingHistorySnapshotSync(status: .active)
            }
        }
    }

    private func startMeetingProtocol(
        target: ProtocolTarget,
        transcript: String,
        languageName: String
    ) {
        guard !isTranscriptSummaryLoading,
              !isTranslationSummaryLoading,
              !isTranscriptProtocolLoading,
              !isTranslationProtocolLoading,
              !isTranscriptAnswerLoading,
              !isTranslationAnswerLoading else {
            return
        }

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return
        }

        switch target {
        case .source:
            isTranscriptSummaryVisible = false
            isTranscriptAnswerVisible = false
            transcriptProtocolText = ""
            transcriptProtocolErrorMessage = nil
            isTranscriptProtocolVisible = true
            isTranscriptProtocolLoading = true
        case .translation:
            isTranslationSummaryVisible = false
            isTranslationAnswerVisible = false
            translationProtocolText = ""
            translationProtocolErrorMessage = nil
            isTranslationProtocolVisible = true
            isTranslationProtocolLoading = true
        }

        Task { @MainActor in
            defer {
                switch target {
                case .source:
                    isTranscriptProtocolLoading = false
                case .translation:
                    isTranslationProtocolLoading = false
                }
            }

            do {
                let protocolText = try await deepSeekMeetingProtocolService.generateProtocol(
                    transcript: trimmedTranscript,
                    languageName: languageName
                )

                switch target {
                case .source:
                    transcriptProtocolText = protocolText
                    transcriptProtocolErrorMessage = nil
                case .translation:
                    translationProtocolText = protocolText
                    translationProtocolErrorMessage = nil
                }
                scheduleMeetingHistorySnapshotSync(status: .active)
            } catch {
                let fallback = localFallbackProtocol(from: trimmedTranscript)
                switch target {
                case .source:
                    transcriptProtocolText = fallback
                    transcriptProtocolErrorMessage = "AI meeting notes failed, showing a local fallback instead."
                case .translation:
                    translationProtocolText = fallback
                    translationProtocolErrorMessage = "AI meeting notes failed, showing a local fallback instead."
                }
                scheduleMeetingHistorySnapshotSync(status: .active)
            }
        }
    }

    private func startAnswerAssist(
        target: AnswerAssistTarget,
        transcript: String,
        inputLanguageName: String,
        outputLanguageName: String
    ) {
        guard !isTranscriptSummaryLoading,
              !isTranslationSummaryLoading,
              !isTranscriptProtocolLoading,
              !isTranslationProtocolLoading,
              !isTranscriptAnswerLoading,
              !isTranslationAnswerLoading else {
            return
        }

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return
        }

        switch target {
        case .source:
            isTranscriptSummaryVisible = false
            isTranscriptProtocolVisible = false
            transcriptAnswerText = ""
            transcriptAnswerErrorMessage = nil
            isTranscriptAnswerVisible = true
            isTranscriptAnswerLoading = true
        case .translation:
            isTranslationSummaryVisible = false
            isTranslationProtocolVisible = false
            translationAnswerText = ""
            translationAnswerErrorMessage = nil
            isTranslationAnswerVisible = true
            isTranslationAnswerLoading = true
        }

        Task { @MainActor in
            defer {
                switch target {
                case .source:
                    isTranscriptAnswerLoading = false
                case .translation:
                    isTranslationAnswerLoading = false
                }
            }

            do {
                let answer = try await deepSeekAnswerAssistService.suggestAnswer(
                    transcript: trimmedTranscript,
                    inputLanguageName: inputLanguageName,
                    outputLanguageName: outputLanguageName
                )

                switch target {
                case .source:
                    transcriptAnswerText = answer
                    transcriptAnswerErrorMessage = nil
                case .translation:
                    translationAnswerText = answer
                    translationAnswerErrorMessage = nil
                }
            } catch {
                let fallback = localFallbackAnswer(from: trimmedTranscript)
                switch target {
                case .source:
                    transcriptAnswerText = fallback
                    transcriptAnswerErrorMessage = "AI answer assist failed, showing a local fallback instead."
                case .translation:
                    translationAnswerText = fallback
                    translationAnswerErrorMessage = "AI answer assist failed, showing a local fallback instead."
                }
            }
        }
    }
}

private enum SummaryTarget {
    case source
    case translation
}

private enum ProtocolTarget {
    case source
    case translation
}

private enum AnswerAssistTarget {
    case source
    case translation
}

private struct StructuredDialogueLine: Decodable {
    let timestamp: String
    let speaker: String?
    let text: String
}

private extension Date {
    var billingUsageTimestamp: String {
        Self.billingUsageFormatter.string(from: self)
    }

    func roundedDownToSecond() -> Date {
        Date(timeIntervalSince1970: floor(timeIntervalSince1970))
    }

    private static let billingUsageFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
