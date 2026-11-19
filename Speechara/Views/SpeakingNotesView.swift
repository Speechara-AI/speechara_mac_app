import AppKit
import SwiftUI

private enum SpeakingNotesTheme {
    static let accent = Color(red: 0.08, green: 0.45, blue: 0.91)
    static let success = Color(red: 0.20, green: 0.78, blue: 0.54)
    static let warning = Color(red: 0.96, green: 0.62, blue: 0.23)
    static let border = Color.primary.opacity(0.10)
    static let softFill = Color.primary.opacity(0.045)
}

struct SpeakingNotesView: View {
    @ObservedObject var store: SpeakingNotesStore

    var body: some View {
        VStack(spacing: 0) {
            header
            if !store.windowState.collapsed {
                Divider()
                if store.showsLibrary { library }
                else if store.note != nil { noteContent }
            }
        }
        .frame(minWidth: 380, minHeight: store.windowState.collapsed ? 58 : 320)
        .background(.ultraThickMaterial)
        .task {
            if store.showsLibrary { await store.loadLibrary() }
        }
        .onChange(of: store.showsLibrary) { value in
            if value { Task { await store.loadLibrary() } }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "circle.grid.3x3.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .help(SL("Drag window"))

            Image(systemName: "doc.text")
                .font(.system(size: 16, weight: .semibold))

            if let note = store.note, !store.showsLibrary, store.isEditing {
                TextField("Untitled note", text: Binding(
                    get: { note.title },
                    set: store.updateTitle
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            } else {
                Text(store.showsLibrary ? SL("Speaking notes") : store.note?.title ?? SL("Speaking notes"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }

            if !store.showsLibrary, store.note != nil {
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.isDirty ? SpeakingNotesTheme.warning : SpeakingNotesTheme.success)
                        .frame(width: 6, height: 6)
                    Text(store.saveStatus)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
            }

            Spacer(minLength: 4)

            if !store.showsLibrary, store.note != nil, !store.isEditing {
                headerButton("pencil", help: "Rename note") { store.isEditing = true }
            }
            if !store.showsLibrary {
                headerButton("list.bullet", help: "Open speaking notes library") {
                    store.showsLibrary = true
                }
            }
            headerButton(store.windowState.collapsed ? "chevron.up.chevron.down" : "minus", help: store.windowState.collapsed ? "Expand speaking notes" : "Collapse speaking notes") {
                SpeakingNotesWindowController.shared.toggleCollapsed()
            }
            headerButton("xmark", help: "Hide speaking notes") {
                SpeakingNotesWindowController.shared.hide()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .contentShape(Rectangle())
        .background(Color.clear)
    }

    private func headerButton(_ image: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(SL(help))
    }

    private var library: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(SL("Your prepared notes"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(SL("Open a recent note or prepare a new one before the meeting."))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    Task { await store.createNew() }
                } label: {
                    Label(SL("Prepare new"), systemImage: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 13)
                        .frame(height: 38)
                        .background(RoundedRectangle(cornerRadius: 11).fill(SpeakingNotesTheme.accent))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(18)

            Divider().padding(.horizontal, 18)

            if store.isLoadingLibrary && store.recentNotes.isEmpty {
                Spacer()
                ProgressView(SL("Loading notes…"))
                Spacer()
            } else if store.recentNotes.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(SL("No saved notes yet"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(SL("Prepare your first talking points or speech."))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.recentNotes) { item in
                            noteRow(item)
                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }

            errorBanner
        }
    }

    private func noteRow(_ item: SpeakingNoteListItem) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.open(item) }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(item.activeLanguage.displayName) · \(formattedDate(item.updatedAt))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            smallIconButton("doc.on.doc", help: "Duplicate") { Task { await store.duplicate(item) } }
            smallIconButton("trash", help: "Delete", tint: .red) { Task { await store.delete(item) } }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 66)
    }

    private var noteContent: some View {
        VStack(spacing: 0) {
            modeTabs
                .padding(.horizontal, 16)
                .padding(.top, 14)

            Group {
                if store.note?.activeMode == .talkingPoints { talkingPoints }
                else { speech }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if store.isEditing {
                Divider()
                languageRow
                Divider()
                aiActions
                Divider()
                editingFooter
            }

            errorBanner
        }
    }

    private var modeTabs: some View {
        HStack(spacing: 4) {
            modeTab(.talkingPoints, title: "Talking points", image: "checklist")
            modeTab(.speech, title: "Speech", image: "doc.text")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 13).fill(SpeakingNotesTheme.softFill))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(SpeakingNotesTheme.border))
    }

    private func modeTab(_ mode: SpeakingNoteMode, title: String, image: String) -> some View {
        let selected = store.note?.activeMode == mode
        return HStack(spacing: 2) {
            Button {
                store.setMode(mode)
            } label: {
                Label(SL(title), systemImage: image)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(selected ? SpeakingNotesTheme.accent : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color(nsColor: .controlBackgroundColor) : Color.clear))
            }
            .buttonStyle(.plain)

            if selected && !store.isEditing {
                Button { store.isEditing = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8).fill(SpeakingNotesTheme.accent.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(SpeakingNotesTheme.accent)
                .padding(.trailing, 5)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var talkingPoints: some View {
        if store.isEditing {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(store.activeVariant.talkingPoints.enumerated()), id: \.element.id) { index, point in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(SpeakingNotesTheme.border))
                            TextField("Add a talking point", text: Binding(
                                get: { store.activeVariant.talkingPoints.first(where: { $0.id == point.id })?.text ?? "" },
                                set: { store.setPointText(id: point.id, text: $0) }
                            ))
                            .textFieldStyle(.plain)
                            Button { store.removePoint(id: point.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                        Divider()
                    }
                    Button(action: store.addPoint) {
                        Label(SL("Add talking point"), systemImage: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SpeakingNotesTheme.accent)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(store.activeVariant.talkingPoints.enumerated()), id: \.element.id) { index, point in
                        HStack(alignment: .top, spacing: 10) {
                            Button { store.toggleCovered(id: point.id) } label: {
                                Group {
                                    if store.coveredPointIDs.contains(point.id) { Image(systemName: "checkmark") }
                                    else { Text("\(index + 1)") }
                                }
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 25, height: 25)
                                .background(Circle().fill(store.coveredPointIDs.contains(point.id) ? SpeakingNotesTheme.success.opacity(0.16) : Color.clear))
                                .overlay(Circle().stroke(SpeakingNotesTheme.border))
                            }
                            .buttonStyle(.plain)
                            Text(point.text.isEmpty ? SL("Empty talking point") : point.text)
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(store.coveredPointIDs.contains(point.id) ? .secondary : .primary)
                                .strikethrough(store.coveredPointIDs.contains(point.id))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 10)
                        Divider()
                    }
                    if !store.activeVariant.talkingPoints.isEmpty {
                        let covered = store.activeVariant.talkingPoints.filter { store.coveredPointIDs.contains($0.id) }.count
                        ProgressView(value: Double(covered), total: Double(store.activeVariant.talkingPoints.count)) {
                            Text(SLF("%d of %d covered", covered, store.activeVariant.talkingPoints.count))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .tint(SpeakingNotesTheme.success)
                        .padding(.top, 14)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var speech: some View {
        if store.isEditing {
            TextEditor(text: Binding(get: { store.activeVariant.speech }, set: store.setSpeech))
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .scrollContentBackground(.hidden)
        } else {
            ScrollView {
                Text(store.activeVariant.speech.isEmpty ? SL("Your prepared speech will appear here.") : store.activeVariant.speech)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .lineSpacing(10)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
    }

    private var languageRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "translate")
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { store.note?.activeLanguage ?? .en },
                set: store.setLanguage
            )) {
                ForEach(SpeakingNoteLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            if store.automaticallyDetectedLanguage == store.note?.activeLanguage {
                Label(SL("Detected automatically"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
    }

    private var aiActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                aiButton("Generate title", image: "pencil", operation: .generateTitle)
                aiButton("Polish with AI", image: "sparkles", operation: .polish)
                aiButton(
                    store.note?.activeMode == .talkingPoints ? "Generate speech" : "Generate talking points",
                    image: store.note?.activeMode == .talkingPoints ? "doc.text" : "checklist",
                    operation: store.note?.activeMode == .talkingPoints ? .generateSpeech : .generateTalkingPoints
                )
                translateButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(height: 56)
    }

    private func aiButton(_ title: String, image: String, operation: SpeakingNoteTransformOperation) -> some View {
        Button { Task { await store.transform(operation) } } label: {
            HStack(spacing: 6) {
                if store.isTransforming { ProgressView().controlSize(.mini) }
                else { Image(systemName: image) }
                Text(SL(title))
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(SpeakingNotesTheme.accent)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10).fill(SpeakingNotesTheme.softFill))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(SpeakingNotesTheme.border))
        }
        .buttonStyle(.plain)
        .disabled(store.isTransforming)
    }

    private var translateButton: some View {
        HStack(spacing: 0) {
            Button { Task { await store.transform(.translate) } } label: {
                HStack(spacing: 6) {
                    if store.isTransforming { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "translate") }
                    Text(SLF("Translate to: %@", store.targetLanguage.displayName))
                }
                .font(.system(size: 11, weight: .bold))
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isTransforming)

            Rectangle()
                .fill(SpeakingNotesTheme.border)
                .frame(width: 1, height: 18)

            Menu {
                ForEach(SpeakingNoteLanguage.allCases) { language in
                    Button {
                        store.targetLanguage = language
                    } label: {
                        if language == store.targetLanguage {
                            Label(language.displayName, systemImage: "checkmark")
                        } else {
                            Text(language.displayName)
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 28, height: 34)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(store.isTransforming)
            .help(SL("Choose translation language"))
        }
        .foregroundStyle(SpeakingNotesTheme.accent)
        .background(RoundedRectangle(cornerRadius: 10).fill(SpeakingNotesTheme.softFill))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(SpeakingNotesTheme.border))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var editingFooter: some View {
        HStack(spacing: 10) {
            Button {
                store.finishEditing()
                SpeakingNotesWindowController.shared.compactForReading()
            } label: {
                Label(SL("Done editing"), systemImage: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(SpeakingNotesTheme.accent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Text(store.note?.activeMode == .talkingPoints
                 ? SL("Switch to Speech to view the full prepared script.")
                 : SL("Switch to Talking points for a compact checklist."))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = store.errorMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.system(size: 11, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let retryTitle = store.errorRetryTitle {
                    Button(retryTitle) { Task { await store.retryFailedOperation() } }
                        .buttonStyle(.link)
                        .disabled(store.isSaving || store.isTransforming)
                }
                Button { store.clearError() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.orange.opacity(0.10))
        }
    }

    private func smallIconButton(_ image: String, help: String, tint: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image).font(.system(size: 13, weight: .semibold)).frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .help(SL(help))
    }

    private func formattedDate(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

@MainActor
final class SpeakingNotesWindowController: NSObject, NSWindowDelegate {
    static let shared = SpeakingNotesWindowController()

    private var panel: NSPanel?
    private let store = SpeakingNotesStore.shared

    func show(for userID: String?) {
        guard let userID else { return }
        store.configure(userID: userID)
        let panel = panel ?? makePanel()
        restoreFrame(on: panel)
        store.updateWindowState { $0.hidden = false }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        store.updateWindowState { $0.hidden = true }
    }

    func hideForSignOut() {
        hide()
        store.configure(userID: nil)
    }

    func toggleCollapsed() {
        guard let panel else { return }
        let collapsed = !store.windowState.collapsed
        store.updateWindowState { $0.collapsed = collapsed }
        let targetHeight = collapsed ? 58 : max(store.windowState.height, 320)
        panel.contentMinSize = collapsed ? NSSize(width: 380, height: 58) : NSSize(width: 380, height: 320)
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = targetHeight
        frame.origin.y = top - targetHeight
        panel.setFrame(clamped(frame), display: true, animate: true)
    }

    func compactForReading() {
        guard let panel, !store.windowState.collapsed else { return }
        let speechLength = store.activeVariant.speech.count
        let pointCount = store.activeVariant.talkingPoints.count
        let estimated = store.note?.activeMode == .speech
            ? min(CGFloat(300 + speechLength / 3), store.windowState.height)
            : min(CGFloat(220 + pointCount * 54), store.windowState.height)
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = max(320, estimated)
        frame.origin.y = top - frame.height
        panel.setFrame(clamped(frame), display: true, animate: true)
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("speechara-speaking-notes")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentMinSize = NSSize(width: 380, height: 320)
        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView: SpeakingNotesView(store: store))
        self.panel = panel
        return panel
    }

    private func restoreFrame(on panel: NSPanel) {
        let state = store.windowState
        let height = state.collapsed ? 58 : max(320, state.height)
        panel.contentMinSize = state.collapsed ? NSSize(width: 380, height: 58) : NSSize(width: 380, height: 320)
        panel.setFrame(clamped(NSRect(x: state.x, y: state.y, width: max(380, state.width), height: height)), display: true)
    }

    private func saveFrame() {
        guard let panel else { return }
        let frame = panel.frame
        store.updateWindowState {
            $0.x = frame.minX
            $0.y = frame.minY
            $0.width = frame.width
            if !$0.collapsed { $0.height = frame.height }
        }
    }

    private func clamped(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        var result = frame
        result.size.width = min(max(result.width, 380), visible.width)
        result.size.height = min(max(result.height, store.windowState.collapsed ? 58 : 320), visible.height)
        result.origin.x = min(max(result.minX, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.minY, visible.minY), visible.maxY - result.height)
        return result
    }
}
