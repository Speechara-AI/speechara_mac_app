import AppKit
import Combine
import Foundation

enum SubtitleStatus: String {
    case idle = "Idle"
    case listening = "Listening"
    case stopped = "Stopped"
}

enum SourceLanguageOption: String, CaseIterable, Identifiable {
    case english

    var id: Self { self }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        }
    }

    var deepgramLanguageCode: String {
        switch self {
        case .english:
            return "en"
        }
    }

    var deepSeekLanguageName: String {
        switch self {
        case .english:
            return "English"
        }
    }

    var summarizeButtonTitle: String {
        switch self {
        case .english:
            return "Summarize"
        }
    }

    var answerButtonTitle: String {
        switch self {
        case .english:
            return "Suggest answer"
        }
    }

    var protocolButtonTitle: String {
        switch self {
        case .english:
            return "Protocol"
        }
    }

    var answerPanelTitle: String {
        switch self {
        case .english:
            return "Suggested answer"
        }
    }

    var protocolPanelTitle: String {
        switch self {
        case .english:
            return "Meeting protocol"
        }
    }
}

enum TranslationLanguageOption: String, CaseIterable, Identifiable {
    case russian
    case german
    case spanish
    case french

    var id: Self { self }

    var displayName: String {
        switch self {
        case .russian:
            return "Russian"
        case .german:
            return "German"
        case .spanish:
            return "Spanish"
        case .french:
            return "French"
        }
    }

    var deepSeekTargetLanguageName: String {
        switch self {
        case .russian:
            return "Russian"
        case .german:
            return "German"
        case .spanish:
            return "Spanish"
        case .french:
            return "French"
        }
    }

    var summarizeButtonTitle: String {
        switch self {
        case .russian:
            return "Резюме"
        case .german:
            return "Zusammenfassen"
        case .spanish:
            return "Resumir"
        case .french:
            return "Résumer"
        }
    }

    var answerButtonTitle: String {
        switch self {
        case .russian:
            return "Подсказать ответ"
        case .german:
            return "Antwort vorschlagen"
        case .spanish:
            return "Sugerir respuesta"
        case .french:
            return "Suggérer une réponse"
        }
    }

    var protocolButtonTitle: String {
        switch self {
        case .russian:
            return "Протокол"
        case .german:
            return "Protokoll"
        case .spanish:
            return "Protocolo"
        case .french:
            return "Protocole"
        }
    }

    var answerPanelTitle: String {
        switch self {
        case .russian:
            return "Подсказка ответа"
        case .german:
            return "Antwortvorschlag"
        case .spanish:
            return "Respuesta sugerida"
        case .french:
            return "Réponse suggérée"
        }
    }

    var protocolPanelTitle: String {
        switch self {
        case .russian:
            return "Протокол встречи"
        case .german:
            return "Besprechungsprotokoll"
        case .spanish:
            return "Protocolo de la reunion"
        case .french:
            return "Protocole de reunion"
        }
    }
}

struct DialogueEntry: Identifiable, Equatable {
    let id: UUID
    let speakerNumber: Int?
    let text: String
    let timestamp: Date

    init(id: UUID = UUID(), speakerNumber: Int?, text: String, timestamp: Date = Date()) {
        self.id = id
        self.speakerNumber = speakerNumber
        self.text = text
        self.timestamp = timestamp
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

private struct SessionDraft: Codable {
    struct DraftTurn: Codable {
        let id: UUID
        let speakerLabel: String?
        let text: String
        let translationSpeakerLabel: String?
        let translationText: String
        let timestamp: Date
        let isClosed: Bool
    }

    let turns: [DraftTurn]
    let subtitlesText: String
    let translatedText: String
    let transcriptSummaryText: String
    let translationSummaryText: String
    let transcriptProtocolText: String
    let translationProtocolText: String
    let transcriptAnswerText: String
    let translationAnswerText: String
}

@MainActor
final class SubtitleViewModel: ObservableObject {
    private static let minimumEditorFontSize: CGFloat = 12
    private static let maximumEditorFontSize: CGFloat = 30
    private static let editorFontStep: CGFloat = 2
    private static let microphoneStartPreferenceDefaultsKey = "speechara.session.startWithMicrophone"
    private static let sessionDraftDefaultsKey = "speechara.session.localDraft.v2"
    private static let autosaveIntervalNanoseconds: UInt64 = 240_000_000
    private static let stableReconstructionContextLines = 2
    private static let stableReconstructionBatchLines = 5
    private static let stableReconstructionDelayNanoseconds: UInt64 = 2_000_000_000

    @Published private(set) var status: SubtitleStatus = .idle
    @Published var subtitlesText = ""
    @Published var translatedText = ""
    @Published private(set) var transcriptEntries = [DialogueEntry]()
    @Published private(set) var translationEntries = [DialogueEntry]()
    @Published var selectedSourceLanguage: SourceLanguageOption = .english
    @Published var isAudioRecordingEnabled = false
    @Published var isTranslationEnabled = true
    @Published var selectedTranslationLanguage: TranslationLanguageOption = .russian
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
    @Published private(set) var isMicrophoneTesting = false
    @Published private(set) var isMicrophoneBusy = false
    @Published private(set) var microphoneLevel = 0.0
    @Published private(set) var microphoneSignalDetected = false
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var translationMessage: String?
    @Published private(set) var lastRecordingPath: String?
    @Published private(set) var transcriptFontSize: CGFloat = 18
    @Published private(set) var translationFontSize: CGFloat = 18
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
    private let deepSeekTranslationService = DeepSeekTranslationService()
    private let deepSeekSummaryService = DeepSeekSummaryService()
    private let deepSeekMeetingProtocolService = DeepSeekMeetingProtocolService()
    private let deepSeekAnswerAssistService = DeepSeekAnswerAssistService()
    private let meetingSessionHistoryService = MeetingSessionHistoryService()
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
    private var draftAutosaveTask: Task<Void, Never>?
    private var pendingTranslationDrafts = [UUID: String]()
    private var translationPreviewTurnID: UUID?
    private var lastSavedDraftFingerprint = ""
    private var meetingHistorySessionID: String?
    private var meetingHistorySessionRevision: Int?
    private var meetingHistoryStartedAt: Date?
    private var meetingHistoryLastSavedSnapshotSignature: String?
    private var meetingHistoryLastCompletedSnapshotSignature: String?
    private var meetingHistorySaveTask: Task<Void, Never>?
    private var meetingHistorySource = "system_audio"
    private var focusModeEnabledForHistory = false
    private var meetingHistoryConversationGeneration = UUID()

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
        startsWithMicrophoneEnabled = defaults.object(forKey: Self.microphoneStartPreferenceDefaultsKey) as? Bool ?? false
        refreshAvailableMicrophones()
        restoreDraftIfAvailable()
    }

    var liveSubtitleDescription: String {
        liveSubtitlePreview.isEmpty ? "Waiting for speech..." : liveSubtitlePreview
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

    var canStopSystemListening: Bool {
        isSystemAudioListening && !isBusy
    }

    var sourceLanguageSummary: String {
        "Input: \(selectedSourceLanguage.displayName)"
    }

    var recordingSummary: String {
        isAudioRecordingEnabled ? "M4A: On" : "M4A: Off"
    }

    var microphoneSummary: String {
        isMicrophoneListening ? "Mic: On" : "Mic: Off"
    }

    var selectedMicrophoneName: String {
        availableMicrophones.first(where: { $0.id == selectedMicrophoneID })?.name ?? "Default microphone"
    }

    var hasAvailableMicrophones: Bool {
        !availableMicrophones.isEmpty
    }

    var microphoneTestButtonTitle: String {
        isMicrophoneTesting ? "Stop test" : "Start test"
    }

    var microphoneTestDescription: String {
        if !hasAvailableMicrophones {
            return "No microphone devices are available."
        }

        if isMicrophoneTesting {
            return microphoneSignalDetected ? "Signal detected. Keep speaking." : "Speak now. Waiting for signal..."
        }

        if isMicrophoneListening {
            return microphoneSignalDetected ? "Microphone signal is live." : "Microphone is on. Waiting for speech..."
        }

        return "Use Test to verify the selected microphone before adding it to the live transcript."
    }

    var translationSummary: String {
        isTranslationEnabled ? "Translate to: \(selectedTranslationLanguage.displayName)" : "Translation: Off"
    }

    var translationPanelTitle: String {
        "\(selectedTranslationLanguage.displayName) translation"
    }

    var assistantActivityText: String? {
        if isTranscriptProtocolLoading || isTranslationProtocolLoading {
            return "Preparing protocol..."
        }

        if isTranscriptAnswerLoading || isTranslationAnswerLoading {
            return "Suggesting answer..."
        }

        if isTranscriptSummaryLoading || isTranslationSummaryLoading {
            return "Summarizing..."
        }

        if !liveTranslationPreview.isEmpty {
            return "Translating..."
        }

        return nil
    }

    var transcriptPlaceholderText: String {
        hasActiveSession
            ? "Transcript is live. You can edit it at any time during testing."
            : "Start listening or turn on the microphone to begin capturing transcript."
    }

    var translationPlaceholderText: String {
        if !isTranslationEnabled {
            return "Translation is off for this session."
        }

        return "Translation will appear here as final transcript chunks arrive."
    }

    var sourceAnswerPlaceholderText: String {
        "Suggested answer will appear here after you ask the assistant for help with the latest question."
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
        "Summary"
    }

    var sourceProtocolPanelTitle: String {
        selectedSourceLanguage.protocolPanelTitle
    }

    var sourceAnswerPanelTitle: String {
        selectedSourceLanguage.answerPanelTitle
    }

    var translationSummaryPanelTitle: String {
        switch selectedTranslationLanguage {
        case .russian:
            return "Резюме"
        case .german:
            return "Zusammenfassung"
        case .spanish:
            return "Resumen"
        case .french:
            return "Résumé"
        }
    }

    var translationAnswerPanelTitle: String {
        selectedTranslationLanguage.answerPanelTitle
    }

    var translationProtocolPanelTitle: String {
        selectedTranslationLanguage.protocolPanelTitle
    }

    func speakerDisplayLabel(for speakerNumber: Int) -> String {
        speakerLabel(for: speakerNumber)
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
        !isTranscriptSummaryLoading && !subtitlesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSummarizeTranslation: Bool {
        !isTranslationSummaryLoading && !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    func startListening(includeMicrophone: Bool = false) {
        guard !isSystemAudioListening, !isBusy else {
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
                try await ensureStreamingSessionStarted()
                try await systemAudioCaptureService.startCapture(recordAudio: false)
                isSystemAudioListening = true
                status = .listening
                meetingHistoryStartedAt = meetingHistoryStartedAt ?? Date()
                meetingHistorySource = includeMicrophone ? "system_audio+microphone" : "system_audio"
                scheduleMeetingHistorySessionStartIfNeeded()

                if includeMicrophone && !isMicrophoneListening {
                    do {
                        try await enableMicrophoneListening()
                    } catch {
                        await mixedAudioStreamMixer.setMicrophoneEnabled(false)
                        stopMicrophoneCaptureIfPossible(force: true)
                        isMicrophoneListening = false
                        updateMicrophoneLiveHandler()
                        errorMessage = error.localizedDescription
                    }
                }
            } catch {
                errorMessage = error.localizedDescription

                if !hasActiveAudioSource {
                    status = .idle
                }
            }
        }
    }

    func startNewSession() {
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

            await completeMeetingHistoryConversationIfNeeded()
            resetMeetingHistoryState()
            clearCurrentSessionForNewSession()
        }
    }

    func stopListening() {
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

    func toggleMicrophoneCapture() {
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
                updateMicrophoneLiveHandler()
                stopMicrophoneCaptureIfPossible()

                if !isSystemAudioListening {
                    await stopStreamingSession(markStopped: true)
                } else {
                    status = .listening
                }

                return
            }

            do {
                try await ensureStreamingSessionStarted()
                try await enableMicrophoneListening()
                meetingHistoryStartedAt = meetingHistoryStartedAt ?? Date()
                meetingHistorySource = isSystemAudioListening ? "system_audio+microphone" : "microphone"
                scheduleMeetingHistorySessionStartIfNeeded()
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

    func clearSubtitles() {
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

    private func completeMeetingHistoryConversationIfNeeded() async {
        _ = await meetingHistorySaveTask?.result
        await persistMeetingHistorySnapshot(status: .completed)
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
        guard meetingHistorySessionID == nil,
              let snapshot = meetingHistorySnapshot(status: .active, allowEmptySession: true) else {
            return
        }

        do {
            let remoteState = try await meetingSessionHistoryService.startSession(snapshot: snapshot)
            meetingHistorySessionID = remoteState.id
            meetingHistorySessionRevision = remoteState.revision
            meetingHistoryLastSavedSnapshotSignature = nil
            meetingHistoryLastCompletedSnapshotSignature = nil
        } catch {
            handleMeetingHistorySyncError(error)
        }
    }

    private func persistMeetingHistorySnapshot(status: MeetingSessionHistoryStatus) async {
        guard let snapshot = meetingHistorySnapshot(
            status: status,
            allowEmptySession: meetingHistoryStartedAt != nil || meetingHistorySessionID != nil
        ) else {
            return
        }

        do {
            if meetingHistorySessionID == nil || meetingHistorySessionRevision == nil {
                let remoteState = try await meetingSessionHistoryService.startSession(snapshot: snapshot)
                meetingHistorySessionID = remoteState.id
                meetingHistorySessionRevision = remoteState.revision
            }

            guard let meetingHistorySessionID,
                  let meetingHistorySessionRevision else {
                return
            }

            let lastSignature = status == .completed
                ? meetingHistoryLastCompletedSnapshotSignature
                : meetingHistoryLastSavedSnapshotSignature

            guard lastSignature != snapshot.signature else {
                return
            }

            let remoteState = try await meetingSessionHistoryService.updateSession(
                id: meetingHistorySessionID,
                revision: meetingHistorySessionRevision,
                snapshot: snapshot
            )

            self.meetingHistorySessionRevision = remoteState.revision
            if status == .completed {
                meetingHistoryLastCompletedSnapshotSignature = snapshot.signature
            } else {
                meetingHistoryLastSavedSnapshotSignature = snapshot.signature
            }
        } catch {
            handleMeetingHistorySyncError(error)
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

        let endedAt = status == .completed ? Date() : nil
        let durationSeconds = max(0, Int((endedAt ?? Date()).timeIntervalSince(startedAt)))

        return MeetingSessionHistorySnapshot(
            title: meetingHistoryTitle,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            status: status,
            inputLanguage: selectedSourceLanguage.deepgramLanguageCode.lowercased(),
            translationLanguage: isTranslationEnabled ? selectedTranslationLanguage.rawValue.lowercased() : nil,
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
                focusMode: focusModeEnabledForHistory
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
            let text = visibleTranslationText(for: turn).trimmingCharacters(in: .whitespacesAndNewlines)
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
                language: selectedTranslationLanguage.rawValue.lowercased(),
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
        meetingHistorySessionRevision = nil
        meetingHistoryStartedAt = nil
        meetingHistoryLastSavedSnapshotSignature = nil
        meetingHistoryLastCompletedSnapshotSignature = nil
        meetingHistorySource = "system_audio"
        meetingHistorySaveTask = nil
    }

    private func handleMeetingHistorySyncError(_ error: Error) {
        if let historyError = error as? MeetingSessionHistoryServiceError,
           case .missingAuthSession = historyError {
            return
        }

        let message = "Meeting history sync failed: \(error.localizedDescription)"
        if errorMessage != message {
            errorMessage = message
        }
    }

    func updateTranscriptText(_ text: String) {
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
            await deepSeekTranslationService.replaceHistory(with: translationHistoryTurns())
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
            outputLanguageName: selectedSourceLanguage.deepSeekLanguageName
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
            languageName: selectedSourceLanguage.deepSeekLanguageName
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
            outputLanguageName: selectedSourceLanguage.deepSeekLanguageName
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

    func setFocusModeEnabled(_ isEnabled: Bool) {
        focusModeEnabledForHistory = isEnabled
    }

    private func configureSystemAudioRouting() {
        systemAudioCaptureService.setLiveAudioDataHandler { [mixedAudioStreamMixer] audioData in
            Task {
                await mixedAudioStreamMixer.appendSystemAudio(audioData)
            }
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
        await mixedAudioStreamMixer.setOutputHandler { [weak self, localAudioRecordingService, liveDeepgramService] audioData in
            await localAudioRecordingService.appendMixedAudio(audioData)

            guard let self else {
                return
            }

            let shouldSend = await MainActor.run {
                self.isStreamingSessionPrepared && self.hasActiveAudioSource
            }
            guard shouldSend else {
                return
            }

            await liveDeepgramService.sendAudio(audioData)
        }
    }

    private func applyDeepgramEvent(_ event: DeepgramTranscriptEvent) {
        switch event {
        case .interim(let result):
            liveSubtitlePreview = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        case .final(let result):
            liveSubtitlePreview = ""
            applyFinalTranscript(result.transcript, speechFinal: result.speechFinal)
        }
    }

    private static func deepgramAPIKey() throws -> String {
        guard let apiKey = AppSecretsStore.shared.resolvedValue(for: .deepgram)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw DeepgramLiveTranscriptionError.missingAPIKey
        }

        return apiKey
    }

    private func applyFinalTranscript(_ transcript: String, speechFinal: Bool) {
        let normalizedTranscript = normalizedTranscriptFragment(transcript)
        guard !normalizedTranscript.isEmpty else {
            if speechFinal {
                finalizeCurrentTurnIfNeeded(force: true)
            }
            return
        }

        let delta = transcriptDelta(current: normalizedTranscript, previous: lastDeepgramFinalTranscript)
        lastDeepgramFinalTranscript = normalizedTranscript

        guard !delta.isEmpty else {
            if speechFinal {
                finalizeCurrentTurnIfNeeded(force: true)
            }
            return
        }

        let turnID = ensureOpenTurn()
        appendDeltaToTurn(delta, turnID: turnID)
        rebuildPublishedState()
        scheduleDraftAutosave()

        if isTranslationAvailable {
            Task {
                await deepSeekTranslationService.enqueueFinalChunk(delta, turnID: turnID)
            }
        }

        if speechFinal || shouldFinalizeTurn(afterAppending: delta) {
            finalizeCurrentTurnIfNeeded(force: true)
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

    private func finalizeCurrentTurnIfNeeded(force: Bool) {
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
        lastDeepgramFinalTranscript = ""
        rebuildPublishedState()
        scheduleDraftAutosave()
        scheduleStableReconstructionIfNeeded()

        if force {
            translationPreviewTurnID = nil
            liveTranslationPreview = ""
        }
    }

    private func prepareTranslationIfPossible() async {
        guard isTranslationEnabled else {
            isTranslationAvailable = false
            translationMessage = nil
            await deepSeekTranslationService.resetSession()
            return
        }

        do {
            let deepSeekAPIKey = try Self.deepSeekAPIKey()
            try await deepSeekTranslationService.startSession(
                apiKey: deepSeekAPIKey,
                sourceLanguageName: selectedSourceLanguage.deepSeekLanguageName,
                targetLanguageName: selectedTranslationLanguage.deepSeekTargetLanguageName,
                eventHandler: { [weak self] event in
                    Task { @MainActor in
                        self?.applyTranslationEvent(event)
                    }
                }
            )
            isTranslationAvailable = true
            translationMessage = nil
            liveTranslationPreview = ""
            await deepSeekTranslationService.replaceHistory(with: translationHistoryTurns())
        } catch {
            isTranslationAvailable = false
            translationMessage = "\(selectedTranslationLanguage.displayName) translation is unavailable: \(error.localizedDescription)"
            liveTranslationPreview = ""
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
        isMicrophoneTesting = false
        updateMicrophoneLiveHandler()
        status = .listening
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

        let deepgramAPIKey = try Self.deepgramAPIKey()
        refreshAvailableMicrophones()

        do {
            try await localAudioRecordingService.startRecording(isEnabled: isAudioRecordingEnabled)
            await mixedAudioStreamMixer.reset()
            await configureMixedAudioOutput()
            try await liveDeepgramService.connect(
                apiKey: deepgramAPIKey,
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
                        self?.errorMessage = "Live transcription was interrupted: \(errorMessage)"
                    }
                }
            )
            prepareMicrophoneServiceHandlers()
            configureSystemAudioRouting()
            updateMicrophoneLiveHandler()
            await mixedAudioStreamMixer.setMicrophoneEnabled(false)
            isTranslationAvailable = false
            await prepareTranslationIfPossible()
            liveSubtitlePreview = ""
            liveTranslationPreview = ""
            isStreamingSessionPrepared = true
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
        var stopError: Error?

        resetMicrophoneService()
        isMicrophoneCaptureActive = false
        isMicrophoneListening = false
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
        finalizeCurrentTurnIfNeeded(force: true)
        await deepSeekTranslationService.resetSession()
        await mixedAudioStreamMixer.reset()
        isTranslationAvailable = false
        isStreamingSessionPrepared = false
        lastRecordingPath = outputURL?.path
        liveSubtitlePreview = ""
        liveTranslationPreview = ""
        pendingTranslationDrafts.removeAll()
        translationPreviewTurnID = nil
        lastDeepgramFinalTranscript = ""
        status = markStopped ? .stopped : .idle
        scheduleDraftAutosave()
        if persistHistoryAsActive {
            scheduleMeetingHistorySnapshotSync(status: .active)
        }

        if let stopError {
            errorMessage = stopError.localizedDescription
        }
    }

    private func cleanupFailedStreamingStartup() async {
        systemAudioCaptureService.setLiveAudioDataHandler(nil)
        resetMicrophoneService()
        await liveDeepgramService.stop()
        await deepSeekTranslationService.resetSession()
        await localAudioRecordingService.cancel()
        await mixedAudioStreamMixer.reset()
        isTranslationAvailable = false
        if isSystemAudioListening {
            _ = try? await systemAudioCaptureService.stopCapture()
        }
        isStreamingSessionPrepared = false
        isSystemAudioListening = false
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
            pendingTranslationDrafts[turnID] = translation
            translationPreviewTurnID = turnID
            liveTranslationPreview = translation
            rebuildPublishedState()
        case .completed(let turnID, let translation):
            pendingTranslationDrafts.removeValue(forKey: turnID)
            if translationPreviewTurnID == turnID {
                translationPreviewTurnID = nil
            }
            liveTranslationPreview = ""
            applyCompletedTranslationChunk(translation, to: turnID)
        case .failed(let message):
            if let translationPreviewTurnID {
                pendingTranslationDrafts.removeValue(forKey: translationPreviewTurnID)
                self.translationPreviewTurnID = nil
            }
            isTranslationAvailable = false
            liveTranslationPreview = ""
            translationMessage = "\(selectedTranslationLanguage.displayName) translation was paused: \(message)"
            rebuildPublishedState()

            Task {
                await deepSeekTranslationService.resetSession()
            }
        }
    }

    private static func deepSeekAPIKey() throws -> String {
        guard let apiKey = AppSecretsStore.shared.resolvedValue(for: .deepseek)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw DeepSeekTranslationError.missingAPIKey
        }

        return apiKey
    }

    private func applyCompletedTranslationChunk(_ translation: String, to turnID: UUID) {
        guard let index = sessionTurns.firstIndex(where: { $0.id == turnID }) else {
            return
        }

        sessionTurns[index].translationText = mergedText(
            existing: sessionTurns[index].translationText,
            addition: translation
        )
        rebuildPublishedState()
        scheduleDraftAutosave()
    }

    private func resetSpeakerNumbering() {
        speakerLabelToNumber.removeAll()
        speakerNumberToLabel.removeAll()
        nextSpeakerNumber = 1
    }

    private func speakerLabel(for speakerNumber: Int) -> String {
        speakerNumberToLabel[speakerNumber] ?? "Speaker \(speakerNumber)"
    }

    private func renderText(from entries: [DialogueEntry], useDialogueLabels: Bool, includeTimestamps: Bool) -> String {
        entries
            .map { entry in
                let content: String
                guard useDialogueLabels, let speakerNumber = entry.speakerNumber else {
                    content = entry.text
                    if includeTimestamps {
                        return "[\(Self.transcriptTimestampFormatter.string(from: entry.timestamp))]\n\(content)"
                    }
                    return content
                }

                content = "\(speakerLabel(for: speakerNumber)): \(entry.text)"
                if includeTimestamps {
                    return "[\(Self.transcriptTimestampFormatter.string(from: entry.timestamp))]\n\(content)"
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
        transcriptEntries = sessionTurns.map { turn in
            DialogueEntry(
                id: turn.id,
                speakerNumber: speakerNumber(for: turn.speakerLabel),
                text: turn.text,
                timestamp: turn.timestamp
            )
        }

        translationEntries = sessionTurns.compactMap { turn in
            let visibleTranslation = visibleTranslationText(for: turn).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !visibleTranslation.isEmpty else {
                return nil
            }

            return DialogueEntry(
                id: turn.id,
                speakerNumber: speakerNumber(for: turn.translationSpeakerLabel ?? turn.speakerLabel),
                text: visibleTranslation,
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

    private func visibleTranslationText(for turn: SessionTurn) -> String {
        let committed = turn.translationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let preview = pendingTranslationDrafts[turn.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !preview.isEmpty else {
            return committed
        }

        guard !committed.isEmpty else {
            return preview
        }

        return mergedText(existing: committed, addition: preview)
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

            guard stableWindowStillMatches(signature: signature, range: selection.range) else {
                return
            }

            sessionTurns.replaceSubrange(selection.range, with: reconstructedTurns)
            nextStableTurnIndex = selection.stableStartOffset + reconstructedTurns.count
            rebuildPublishedState()
            scheduleDraftAutosave()
            if isTranslationAvailable {
                await deepSeekTranslationService.replaceHistory(with: translationHistoryTurns())
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
        let apiKey = try Self.deepSeekAPIKey()

        let inputLines = turns.map { turn in
            let timestamp = Self.transcriptTimestampFormatter.string(from: turn.timestamp)
            if let speakerLabel = turn.speakerLabel, !speakerLabel.isEmpty {
                return "[\(timestamp)] \(speakerLabel): \(turn.text)"
            }

            return "[\(timestamp)] \(turn.text)"
        }
        let joinedInput = inputLines.joined(separator: "\n")

        let request = DeepSeekStructuredDialogueRequest(
            model: "deepseek-chat",
            messages: [
                DeepSeekStructuredDialogueMessage(
                    role: "system",
                    content: """
                    Reconstruct clean readable dialogue from raw live STT.
                    Fix only obvious transcription mistakes, restore phrase boundaries, and split speakers when there is high confidence.
                    Preserve chronology and preserve timestamps from the input lines.
                    Return ONLY valid JSON in this exact shape:
                    [{"timestamp":"HH:mm:ss","speaker":"optional label or empty string","text":"clean text"}]
                    No markdown, no explanations, no code fences.
                    """
                ),
                DeepSeekStructuredDialogueMessage(
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

        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
            return turns
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            return turns
        }

        let completion = try JSONDecoder().decode(DeepSeekStructuredDialogueResponse.self, from: data)
        guard let content = completion.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            return turns
        }

        let cleanedPayload = stripMarkdownCodeFence(from: content)
        guard let payloadData = cleanedPayload.data(using: .utf8),
              let reconstructedLines = try? JSONDecoder().decode([StructuredDialogueLine].self, from: payloadData),
              !reconstructedLines.isEmpty else {
            return turns
        }

        return reconstructedLines.compactMap { line in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }

            return SessionTurn(
                speakerLabel: line.speaker?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                text: text,
                timestamp: parsedTimestampString(line.timestamp) ?? Date(),
                isClosed: true
            )
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

        let translatedBlock = try await deepSeekTranslationService.translateStableBlock(sourceBlock, history: [])
        let translatedLines = parseTranslatedStableLines(from: translatedBlock)
        guard translatedLines.count == turns.count else {
            return turns
        }

        return turns.enumerated().map { offset, turn in
            var updatedTurn = turn
            updatedTurn.translationSpeakerLabel = translatedLines[offset].speakerLabel
            updatedTurn.translationText = translatedLines[offset].text
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
        draftAutosaveTask?.cancel()
        draftAutosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.autosaveIntervalNanoseconds)
            await MainActor.run {
                self?.persistDraftIfNeeded()
            }
        }
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
        [
            subtitlesText,
            translatedText,
            transcriptSummaryText,
            translationSummaryText,
            transcriptProtocolText,
            translationProtocolText,
            transcriptAnswerText,
            translationAnswerText,
            sessionTurns.map(\.text).joined(separator: "|"),
            sessionTurns.map(\.translationText).joined(separator: "|"),
        ]
        .joined(separator: "||")
    }

    private func makeSessionDraft() -> SessionDraft {
        SessionDraft(
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
            "Meeting Protocol",
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

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return
        }

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
                let apiKey = try Self.deepSeekAPIKey()
                let summary = try await deepSeekSummaryService.summarize(
                    apiKey: apiKey,
                    transcript: trimmedTranscript,
                    inputLanguageName: inputLanguageName,
                    outputLanguageName: outputLanguageName
                )
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
                let apiKey = try Self.deepSeekAPIKey()
                let protocolText = try await deepSeekMeetingProtocolService.generateProtocol(
                    apiKey: apiKey,
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
                    transcriptProtocolErrorMessage = "AI protocol failed, showing a local fallback instead."
                case .translation:
                    translationProtocolText = fallback
                    translationProtocolErrorMessage = "AI protocol failed, showing a local fallback instead."
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
                let apiKey = try Self.deepSeekAPIKey()
                let answer = try await deepSeekAnswerAssistService.suggestAnswer(
                    apiKey: apiKey,
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

private struct DeepSeekStructuredDialogueRequest: Encodable {
    let model: String
    let messages: [DeepSeekStructuredDialogueMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct DeepSeekStructuredDialogueMessage: Codable {
    let role: String
    let content: String
}

private struct DeepSeekStructuredDialogueResponse: Decodable {
    let choices: [DeepSeekStructuredDialogueChoice]
}

private struct DeepSeekStructuredDialogueChoice: Decodable {
    let message: DeepSeekStructuredDialogueChoiceMessage
}

private struct DeepSeekStructuredDialogueChoiceMessage: Decodable {
    let content: String?
}

private struct StructuredDialogueLine: Decodable {
    let timestamp: String
    let speaker: String?
    let text: String
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
