import Combine
import Foundation

@MainActor
final class SpeakingNotesStore: ObservableObject {
    static let shared = SpeakingNotesStore()

    private enum ErrorRecovery {
        case save
        case resolveConflict
        case transform(SpeakingNoteTransformOperation)
    }

    @Published private(set) var note: SpeakingNote?
    @Published private(set) var recentNotes: [SpeakingNoteListItem] = []
    @Published private(set) var isDirty = false
    @Published private(set) var isSaving = false
    @Published private(set) var isLoadingLibrary = false
    @Published private(set) var isTransforming = false
    @Published private(set) var automaticallyDetectedLanguage: SpeakingNoteLanguage?
    @Published private(set) var errorMessage: String? {
        didSet { errorRecovery = nil }
    }
    @Published var showsLibrary = true
    @Published var isEditing = true
    @Published var targetLanguage = SpeakingNoteLanguage.en
    @Published var coveredPointIDs = Set<String>()
    @Published var windowState = SpeakingNotesWindowState.defaultValue

    private let service: SpeakingNotesGraphQLService
    private let draftStore: SpeakingNotesDraftStore
    private let languageDetector: SpeakingNoteLanguageDetector
    private var userID: String?
    private var workspaceID: String?
    private var meetingSessionID: String?
    private var editGeneration = 0
    private var lastAttachedKey = ""
    private var localSaveTask: Task<Void, Never>?
    private var remoteSaveTask: Task<Void, Never>?
    private var configureTask: Task<Void, Never>?
    private var languageDetectionTask: Task<Void, Never>?
    private var languageWasManuallySelected = false
    private var errorRecovery: ErrorRecovery?

    var errorRetryTitle: String? {
        switch errorRecovery {
        case .save, .resolveConflict: return SL("Retry Save")
        case .transform: return SL("Retry AI")
        case nil: return nil
        }
    }

    func retryFailedOperation() async {
        guard !isSaving, !isTransforming else { return }
        switch errorRecovery {
        case .save: _ = await saveNow()
        case .resolveConflict: await retrySaveAfterConflict()
        case .transform(let operation): await transform(operation)
        case nil: break
        }
    }

    init(
        service: SpeakingNotesGraphQLService = SpeakingNotesGraphQLService(),
        draftStore: SpeakingNotesDraftStore = SpeakingNotesDraftStore(),
        languageDetector: SpeakingNoteLanguageDetector = SpeakingNoteLanguageDetector()
    ) {
        self.service = service
        self.draftStore = draftStore
        self.languageDetector = languageDetector
    }

    var activeVariant: SpeakingNoteVariant {
        note?.activeVariant ?? SpeakingNoteVariant()
    }

    var saveStatus: String {
        if isSaving { return SL("Saving…") }
        if isDirty { return SL("Local draft") }
        return SL("Saved")
    }

    func configure(userID: String?) {
        guard self.userID != userID else { return }
        localSaveTask?.cancel()
        remoteSaveTask?.cancel()
        configureTask?.cancel()
        languageDetectionTask?.cancel()
        self.userID = userID
        workspaceID = nil
        note = nil
        recentNotes = []
        isDirty = false
        errorMessage = nil
        showsLibrary = true
        isEditing = true
        coveredPointIDs = []
        lastAttachedKey = ""
        automaticallyDetectedLanguage = nil
        languageWasManuallySelected = false

        guard let userID else { return }
        let configuredUserID = userID
        if let draft = draftStore.load(userID: userID) {
            note = draft.note
            isDirty = draft.dirty
            windowState = draft.window
            showsLibrary = draft.note == nil
            isEditing = draft.dirty
            workspaceID = draft.note?.workspaceId
            if draft.dirty { scheduleLanguageDetection() }
        } else {
            windowState = .defaultValue
        }

        configureTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.workspaceID = try await self.service.workspaceID()
                guard self.userID == configuredUserID else { return }
                if let current = self.note, !current.isLocal, !self.isDirty {
                    do {
                        self.note = try await self.service.get(id: current.id)
                        self.isEditing = false
                    } catch let error as SpeakingNotesServiceError where error.isNotFound {
                        self.note = nil
                        self.showsLibrary = true
                    }
                }
                if self.isDirty { self.scheduleRemoteSave() }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func loadLibrary() async {
        guard userID != nil, !isLoadingLibrary else { return }
        isLoadingLibrary = true
        defer { isLoadingLibrary = false }
        do {
            recentNotes = try await service.list().items
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createNew() async {
        do {
            let workspaceID = try await resolvedWorkspaceID()
            editGeneration += 1
            note = .local(workspaceID: workspaceID)
            isDirty = true
            showsLibrary = false
            isEditing = true
            coveredPointIDs = []
            resetLanguageDetection()
            errorMessage = nil
            schedulePersistence()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(_ item: SpeakingNoteListItem) async {
        do {
            note = try await service.get(id: item.id)
            editGeneration += 1
            isDirty = false
            showsLibrary = false
            isEditing = false
            coveredPointIDs = []
            resetLanguageDetection()
            errorMessage = nil
            scheduleLocalSave()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func duplicate(_ item: SpeakingNoteListItem) async {
        do {
            _ = try await service.duplicate(id: item.id)
            await loadLibrary()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ item: SpeakingNoteListItem) async {
        do {
            try await service.delete(id: item.id, revision: item.revision)
            if note?.id == item.id {
                note = nil
                isDirty = false
                showsLibrary = true
            }
            await loadLibrary()
            scheduleLocalSave()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTitle(_ title: String) {
        mutate { $0.title = title }
    }

    func setMode(_ mode: SpeakingNoteMode) {
        mutate { $0.activeMode = mode }
    }

    func setLanguage(_ language: SpeakingNoteLanguage) {
        languageDetectionTask?.cancel()
        languageWasManuallySelected = true
        automaticallyDetectedLanguage = nil
        mutate { $0.activeLanguage = language }
    }

    func setSpeech(_ speech: String) {
        mutateVariant { $0.speech = speech }
        scheduleLanguageDetection()
    }

    func addPoint() {
        mutateVariant { $0.talkingPoints.append(SpeakingNotePoint()) }
    }

    func setPointText(id: String, text: String) {
        mutateVariant { variant in
            guard let index = variant.talkingPoints.firstIndex(where: { $0.id == id }) else { return }
            variant.talkingPoints[index].text = text
        }
        scheduleLanguageDetection()
    }

    func removePoint(id: String) {
        mutateVariant { $0.talkingPoints.removeAll { $0.id == id } }
        scheduleLanguageDetection()
    }

    func toggleCovered(id: String) {
        if coveredPointIDs.contains(id) { coveredPointIDs.remove(id) }
        else { coveredPointIDs.insert(id) }
    }

    func finishEditing() {
        isEditing = false
        Task {
            guard await saveNow() != nil else { return }
            guard let note, note.containsText, isUntitled(note.title) else { return }
            await transform(.generateTitle)
        }
    }

    func transform(_ operation: SpeakingNoteTransformOperation) async {
        guard !isTransforming else { return }
        isTransforming = true
        defer { isTransforming = false }
        guard let saved = await saveNow(), !saved.isLocal else { return }
        let generation = editGeneration
        do {
            let transformed = try await service.transform(
                id: saved.id,
                revision: saved.revision,
                operation: operation,
                sourceLanguage: saved.activeLanguage,
                targetLanguage: operation == .translate ? targetLanguage : nil
            )
            guard generation == editGeneration else { return }
            note = transformed
            isDirty = false
            editGeneration += 1
            errorMessage = nil
            scheduleLocalSave()
            _ = await attachIfNeeded()
        } catch {
            guard generation == editGeneration else { return }
            errorMessage = operation == .generateTitle
                ? SLF("Could not generate the note title: %@", error.localizedDescription)
                : SLF("Could not complete the AI action: %@", error.localizedDescription)
            errorRecovery = .transform(operation)
        }
    }

    @discardableResult
    func saveNow() async -> SpeakingNote? {
        remoteSaveTask?.cancel()
        remoteSaveTask = nil
        while isSaving {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        guard let snapshot = note else { return nil }
        guard isDirty else {
            _ = await attachIfNeeded()
            return snapshot
        }

        let generation = editGeneration
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = snapshot.isLocal ? try await service.create(snapshot) : try await service.update(snapshot)
            if editGeneration == generation {
                note = saved
                isDirty = false
            } else if var current = note {
                current.id = saved.id
                current.workspaceId = saved.workspaceId
                current.revision = saved.revision
                current.createdAt = saved.createdAt
                current.updatedAt = saved.updatedAt
                current.lastUsedAt = saved.lastUsedAt
                note = current
            }
            errorMessage = nil
            scheduleLocalSave()
            _ = await attachIfNeeded()
            return note
        } catch let error as SpeakingNotesServiceError where error.isConflict {
            errorMessage = SL("This note changed on another device. Your local draft is safe. Reopen the note to review the server copy, or press Retry Save to overwrite after merging.")
            errorRecovery = .resolveConflict
            scheduleLocalSave()
            return nil
        } catch where isCancellation(error) {
            // Cancellation is expected when a pending debounce is superseded by
            // an explicit save. The draft remains dirty and will be retried.
            scheduleLocalSave()
            scheduleRemoteSave()
            return nil
        } catch {
            errorMessage = SLF("Could not save speaking note. The local draft is safe: %@", error.localizedDescription)
            errorRecovery = .save
            scheduleLocalSave()
            return nil
        }
    }

    func retrySaveAfterConflict() async {
        guard var local = note, !local.isLocal else {
            _ = await saveNow()
            return
        }
        do {
            let remote = try await service.get(id: local.id)
            local.revision = remote.revision
            note = local
            isDirty = true
            _ = await saveNow()
        } catch {
            errorMessage = error.localizedDescription
            errorRecovery = .resolveConflict
        }
    }

    func setMeetingSessionID(_ id: String?) {
        guard meetingSessionID != id else { return }
        meetingSessionID = id
        lastAttachedKey = ""
        if id != nil { Task { await attachIfNeeded() } }
    }

    func flushAndAttach(to meetingSessionID: String?) async -> Bool {
        guard let meetingSessionID else { return true }
        self.meetingSessionID = meetingSessionID
        if note != nil, await saveNow() == nil { return false }
        return await attachIfNeeded(force: true)
    }

    func updateWindowState(_ update: (inout SpeakingNotesWindowState) -> Void) {
        update(&windowState)
        scheduleLocalSave()
    }

    func clearError() { errorMessage = nil }

    private func mutate(_ update: (inout SpeakingNote) -> Void) {
        guard var current = note else { return }
        update(&current)
        current.updatedAt = ISO8601DateFormatter().string(from: Date())
        note = current
        editGeneration += 1
        isDirty = true
        schedulePersistence()
    }

    private func mutateVariant(_ update: (inout SpeakingNoteVariant) -> Void) {
        mutate { current in
            var variant = current.content[current.activeLanguage]
            update(&variant)
            current.content[current.activeLanguage] = variant
        }
    }

    private func schedulePersistence() {
        scheduleLocalSave()
        scheduleRemoteSave()
    }

    private func resetLanguageDetection() {
        languageDetectionTask?.cancel()
        languageDetectionTask = nil
        automaticallyDetectedLanguage = nil
        languageWasManuallySelected = false
    }

    private func scheduleLanguageDetection() {
        languageDetectionTask?.cancel()
        guard !languageWasManuallySelected, let current = note else { return }
        let noteID = current.id
        let sourceLanguage = current.activeLanguage
        let sample = languageDetectionText(for: current.activeVariant)

        guard !sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            automaticallyDetectedLanguage = nil
            return
        }

        languageDetectionTask = Task { [weak self, languageDetector] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) {
                languageDetector.detect(in: sample)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.applyLanguageDetection(
                result,
                sample: sample,
                noteID: noteID,
                sourceLanguage: sourceLanguage
            )
        }
    }

    private func applyLanguageDetection(
        _ result: SpeakingNoteLanguageDetection?,
        sample: String,
        noteID: String,
        sourceLanguage: SpeakingNoteLanguage
    ) {
        guard !languageWasManuallySelected,
              let result,
              result.isReliable,
              var current = note,
              current.id == noteID,
              current.activeLanguage == sourceLanguage,
              languageDetectionText(for: current.activeVariant) == sample
        else { return }

        if result.language == sourceLanguage {
            automaticallyDetectedLanguage = result.language
            return
        }

        let sourceVariant = current.content[sourceLanguage]
        let targetVariant = current.content[result.language]
        let nonEmptyVariants = current.content.variants.values.filter(variantContainsText)

        // Reclassify only a single, newly entered variant. This prevents an
        // automatic guess from overwriting a translation or a multilingual note.
        guard variantContainsText(sourceVariant),
              !variantContainsText(targetVariant),
              nonEmptyVariants.count == 1
        else { return }

        current.content[result.language] = sourceVariant
        current.content.variants.removeValue(forKey: sourceLanguage.rawValue)
        current.activeLanguage = result.language
        current.updatedAt = ISO8601DateFormatter().string(from: Date())
        note = current
        editGeneration += 1
        isDirty = true
        automaticallyDetectedLanguage = result.language
        schedulePersistence()
    }

    private func languageDetectionText(for variant: SpeakingNoteVariant) -> String {
        ([variant.speech] + variant.talkingPoints.map(\.text))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    private func variantContainsText(_ variant: SpeakingNoteVariant) -> Bool {
        !languageDetectionText(for: variant).isEmpty
    }

    private func scheduleLocalSave() {
        localSaveTask?.cancel()
        localSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            self?.persistLocalDraft()
        }
    }

    private func scheduleRemoteSave() {
        remoteSaveTask?.cancel()
        remoteSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, let self else { return }
            // Clear the debounce handle before entering saveNow(). Otherwise
            // saveNow cancels the task that is currently performing the save,
            // which propagates NSURLErrorCancelled from URLSession.
            self.remoteSaveTask = nil
            _ = await self.saveNow()
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func persistLocalDraft() {
        guard let userID else { return }
        let draft = SpeakingNotesLocalDraft(
            authUserId: userID,
            dirty: isDirty,
            note: note,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            window: windowState
        )
        do { try draftStore.save(draft) }
        catch { errorMessage = SLF("Could not protect the local speaking note draft: %@", error.localizedDescription) }
    }

    private func resolvedWorkspaceID() async throws -> String {
        if let workspaceID, !workspaceID.isEmpty { return workspaceID }
        let resolved = try await service.workspaceID()
        workspaceID = resolved
        return resolved
    }

    private func attachIfNeeded(force: Bool = false) async -> Bool {
        guard let meetingSessionID else { return true }
        guard let note else { return true }
        guard !note.isLocal, !isDirty else { return false }
        let key = "\(meetingSessionID):\(note.id):\(note.revision)"
        guard force || key != lastAttachedKey else { return true }
        do {
            _ = try await service.attach(noteID: note.id, to: meetingSessionID)
            lastAttachedKey = key
            return true
        } catch {
            lastAttachedKey = ""
            errorMessage = SLF("Could not attach the speaking note to this meeting: %@", error.localizedDescription)
            return false
        }
    }

    private func isUntitled(_ title: String) -> Bool {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty || value == "untitled note"
    }
}
