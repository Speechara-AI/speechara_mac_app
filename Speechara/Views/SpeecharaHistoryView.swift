import AppKit
import SwiftUI

private enum SpeecharaHistoryTheme {
    static let primaryText = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.10, 0.16, 0.24),
        dark: SpeecharaRGBA(0.92, 0.95, 0.98)
    )
    static let secondaryText = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.34, 0.42, 0.54),
        dark: SpeecharaRGBA(0.70, 0.77, 0.86)
    )
    static let tertiaryText = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.47, 0.54, 0.64),
        dark: SpeecharaRGBA(0.56, 0.63, 0.74)
    )
    static let cardFill = Color.speecharaDynamic(
        light: SpeecharaRGBA(1.00, 1.00, 1.00, 0.86),
        dark: SpeecharaRGBA(0.11, 0.13, 0.16, 0.94)
    )
    static let elevatedFill = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.96, 0.97, 0.99),
        dark: SpeecharaRGBA(0.15, 0.17, 0.21)
    )
    static let border = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.84, 0.88, 0.94),
        dark: SpeecharaRGBA(0.24, 0.29, 0.36)
    )
    static let accent = Color(red: 0.17, green: 0.54, blue: 0.95)
    static let accentFill = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.90, 0.95, 1.00),
        dark: SpeecharaRGBA(0.13, 0.25, 0.38)
    )
    static let neutralTint = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.47, 0.54, 0.64),
        dark: SpeecharaRGBA(0.56, 0.63, 0.74)
    )
    static let backgroundTop = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.98, 0.98, 0.97),
        dark: SpeecharaRGBA(0.09, 0.10, 0.13)
    )
    static let backgroundBottom = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.94, 0.96, 0.99),
        dark: SpeecharaRGBA(0.07, 0.11, 0.16)
    )
    static let searchIcon = Color.speecharaDynamic(
        light: SpeecharaRGBA(0.58, 0.70, 0.88),
        dark: SpeecharaRGBA(0.52, 0.72, 0.96)
    )
}

private enum SpeecharaHistoryDetailTab: String, CaseIterable, Identifiable {
    case transcribe
    case translate
    case summary

    var id: Self { self }

    var title: String {
        switch self {
        case .transcribe:
            return "Transcribe"
        case .translate:
            return "Translate"
        case .summary:
            return "Summary"
        }
    }

    var systemImage: String {
        switch self {
        case .transcribe:
            return "text.alignleft"
        case .translate:
            return "globe"
        case .summary:
            return "sparkles"
        }
    }
}

struct SpeecharaHistoryView: View {
    @StateObject private var viewModel = SpeecharaHistoryViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                searchField
                content
            }
            .padding(32)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .task {
            await viewModel.loadIfNeeded()
        }
        .sheet(isPresented: $viewModel.isDetailPresented, onDismiss: viewModel.dismissDetail) {
            SpeecharaHistoryDetailSheet(viewModel: viewModel)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("History")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(SpeecharaHistoryTheme.primaryText)

                Text("This page loads saved meeting sessions from the backend and shows a compact overview. Open any card to inspect the full transcript, translation, summary, protocol, and suggested reply.")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeecharaHistoryTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            SpeecharaHistoryCountBadge(count: viewModel.sessions.count)
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SpeecharaHistoryTheme.searchIcon)

            TextField(
                "Search transcript, translation, summary, or protocol",
                text: $viewModel.searchText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .medium, design: .rounded))
            .foregroundStyle(SpeecharaHistoryTheme.primaryText)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SpeecharaHistoryTheme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(SpeecharaHistoryTheme.elevatedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(SpeecharaHistoryTheme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.sessions.isEmpty {
            SpeecharaHistoryLoadingCard(text: "Loading session history…")
        } else if let errorMessage = viewModel.errorMessage, viewModel.sessions.isEmpty {
            SpeecharaHistoryErrorCard(
                text: errorMessage,
                retryTitle: "Retry"
            ) {
                Task {
                    await viewModel.refresh()
                }
            }
        } else if viewModel.sessions.isEmpty {
            SpeecharaHistoryEmptyCard(
                title: "No history yet",
                subtitle: "Saved meeting sessions will appear here as soon as they are available in the backend."
            )
        } else {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.sessions) { item in
                    SpeecharaHistorySessionCard(
                        item: item,
                        isOpening: viewModel.isLoadingDetail && viewModel.selectedSessionSummary?.id == item.id
                    ) {
                        Task {
                            await viewModel.openSession(item)
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    SpeecharaHistoryErrorCard(
                        text: errorMessage,
                        retryTitle: "Refresh list"
                    ) {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                }

                if viewModel.nextCursor != nil {
                    Button {
                        Task {
                            await viewModel.loadMore()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(SpeecharaHistoryTheme.accent)
                            }

                            Text(viewModel.isLoadingMore ? SL("Loading more…") : SL("Load more"))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(SpeecharaHistoryTheme.primaryText)
                        .padding(.horizontal, 18)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(SpeecharaHistoryTheme.elevatedFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(SpeecharaHistoryTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoadingMore)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }
}

@MainActor
final class SpeecharaHistoryViewModel: ObservableObject {
    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else {
                return
            }

            scheduleSearchReload()
        }
    }

    @Published private(set) var sessions: [MeetingSessionHistoryListItem] = []
    @Published private(set) var nextCursor: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?

    @Published private(set) var selectedSessionSummary: MeetingSessionHistoryListItem?
    @Published private(set) var selectedSessionDetail: MeetingSessionHistoryDetail?
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var detailErrorMessage: String?
    @Published private(set) var isSummaryLoading = false
    @Published private(set) var detailSummaryText: String?
    @Published private(set) var summaryErrorMessage: String?
    @Published fileprivate var selectedDetailTab: SpeecharaHistoryDetailTab = .transcribe
    @Published var isDetailPresented = false

    private let historyService: MeetingSessionHistoryService
    private let deepSeekSummaryService: DeepSeekSummaryService
    private var hasLoadedInitialPage = false
    private var lastAppliedNormalizedQuery: String?
    private var searchReloadTask: Task<Void, Never>?

    init(
        historyService: MeetingSessionHistoryService = MeetingSessionHistoryService(),
        deepSeekSummaryService: DeepSeekSummaryService = DeepSeekSummaryService()
    ) {
        self.historyService = historyService
        self.deepSeekSummaryService = deepSeekSummaryService
    }

    deinit {
        searchReloadTask?.cancel()
    }

    func loadIfNeeded() async {
        guard !hasLoadedInitialPage else {
            return
        }

        hasLoadedInitialPage = true
        await reload(force: true)
    }

    func refresh() async {
        await reload(force: true)
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, let nextCursor else {
            return
        }

        isLoadingMore = true
        defer {
            isLoadingMore = false
        }

        do {
            let page = try await historyService.fetchSessions(
                query: makeListQuery(cursor: nextCursor)
            )

            sessions.append(contentsOf: page.items)
            self.nextCursor = page.nextCursor
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openSession(_ item: MeetingSessionHistoryListItem) async {
        selectedSessionSummary = item
        selectedSessionDetail = nil
        detailErrorMessage = nil
        detailSummaryText = nil
        summaryErrorMessage = nil
        selectedDetailTab = .transcribe
        isLoadingDetail = true
        isDetailPresented = true

        defer {
            isLoadingDetail = false
        }

        do {
            let detail = try await historyService.fetchSessionDetail(id: item.id)
            selectedSessionDetail = detail
            detailSummaryText = detail.summaryText?.nilIfEmpty
        } catch {
            detailErrorMessage = error.localizedDescription
        }
    }

    func retrySelectedSession() async {
        guard let selectedSessionSummary else {
            return
        }

        await openSession(selectedSessionSummary)
    }

    func copySelectedTranscriptToPasteboard() {
        guard let transcriptText = selectedSessionDetail?.copyableTranscriptText else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptText, forType: .string)
    }

    func visibleSummaryText(for detail: MeetingSessionHistoryDetail) -> String? {
        detailSummaryText?.nilIfEmpty ?? detail.summaryText?.nilIfEmpty
    }

    func canSummarize(_ detail: MeetingSessionHistoryDetail) -> Bool {
        detail.copyableTranscriptText != nil
            && !isSummaryLoading
            && visibleSummaryText(for: detail) == nil
    }

    func summarizeSelectedTranscript() {
        guard !isSummaryLoading,
              let detail = selectedSessionDetail,
              let transcriptText = detail.copyableTranscriptText,
              visibleSummaryText(for: detail) == nil else {
            return
        }

        isSummaryLoading = true
        summaryErrorMessage = nil
        selectedDetailTab = .summary

        Task { @MainActor in
            defer {
                isSummaryLoading = false
            }

            let summaryText: String
            do {
                summaryText = try await deepSeekSummaryService.summarize(
                    transcript: transcriptText,
                    inputLanguageName: detail.summaryLanguageName,
                    outputLanguageName: detail.summaryLanguageName
                )
            } catch {
                summaryText = Self.localFallbackSummary(from: transcriptText)
                if selectedSessionDetail?.id == detail.id {
                    summaryErrorMessage = SL("AI summary failed, showing a local fallback instead.")
                }
            }

            if selectedSessionDetail?.id == detail.id {
                detailSummaryText = summaryText
            }

            await persistSummary(summaryText, basedOn: detail)
        }
    }

    func dismissDetail() {
        isDetailPresented = false
        selectedSessionSummary = nil
        selectedSessionDetail = nil
        detailErrorMessage = nil
        detailSummaryText = nil
        summaryErrorMessage = nil
        selectedDetailTab = .transcribe
        isLoadingDetail = false
        isSummaryLoading = false
    }

    private func scheduleSearchReload() {
        guard hasLoadedInitialPage else {
            return
        }

        searchReloadTask?.cancel()
        searchReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled, let self else {
                return
            }

            await self.reload(force: true)
        }
    }

    private func reload(force: Bool) async {
        guard !isLoading else {
            return
        }

        let normalizedQuery = normalizedSearchText
        if !force, normalizedQuery == lastAppliedNormalizedQuery {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            let page = try await historyService.fetchSessions(
                query: makeListQuery(cursor: nil)
            )

            sessions = page.items
            nextCursor = page.nextCursor
            errorMessage = nil
            lastAppliedNormalizedQuery = normalizedQuery
        } catch {
            sessions = []
            nextCursor = nil
            errorMessage = error.localizedDescription
        }
    }

    private func persistSummary(_ summaryText: String, basedOn detail: MeetingSessionHistoryDetail) async {
        do {
            _ = try await historyService.updateSession(
                id: detail.id,
                revision: detail.revision,
                snapshot: detail.snapshot(replacingSummaryText: summaryText)
            )

            await refreshListAfterSummarySave()

            guard selectedSessionDetail?.id == detail.id else {
                return
            }

            let refreshedDetail = try await historyService.fetchSessionDetail(id: detail.id)
            guard selectedSessionDetail?.id == detail.id else {
                return
            }

            selectedSessionDetail = refreshedDetail
            detailSummaryText = refreshedDetail.summaryText?.nilIfEmpty ?? summaryText
        } catch {
            if selectedSessionDetail?.id == detail.id {
                appendSummaryError(SLF("Summary generated, but could not be saved: %@", error.localizedDescription))
            }
        }
    }

    private func appendSummaryError(_ message: String) {
        if let summaryErrorMessage, !summaryErrorMessage.isEmpty {
            self.summaryErrorMessage = "\(summaryErrorMessage)\n\(message)"
        } else {
            summaryErrorMessage = message
        }
    }

    private func refreshListAfterSummarySave() async {
        do {
            let page = try await historyService.fetchSessions(
                query: makeListQuery(cursor: nil)
            )

            sessions = page.items
            nextCursor = page.nextCursor
            errorMessage = nil
            lastAppliedNormalizedQuery = normalizedSearchText

            if let selectedSessionSummary,
               let refreshedSummary = sessions.first(where: { $0.id == selectedSessionSummary.id }) {
                self.selectedSessionSummary = refreshedSummary
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func localFallbackSummary(from transcript: String) -> String {
        let lines = transcript
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .removingLeadingTimestamp
            }
            .filter { !$0.isEmpty }

        let bullets = Array(lines.prefix(12))
        guard !bullets.isEmpty else {
            return transcript
        }

        return bullets.map { "- \($0)" }.joined(separator: "\n")
    }

    private var normalizedSearchText: String? {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func makeListQuery(cursor: String?) -> MeetingSessionHistoryListQuery {
        MeetingSessionHistoryListQuery(
            limit: 20,
            cursor: cursor,
            searchQuery: normalizedSearchText,
            dateFrom: nil,
            dateTo: nil
        )
    }
}

private struct SpeecharaHistorySessionCard: View {
    let item: MeetingSessionHistoryListItem
    let isOpening: Bool
    let openAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.resolvedTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(SpeecharaHistoryTheme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    SpeecharaHistoryMetaPill(
                        title: item.startedAt.formattedForHistory,
                        systemImage: "calendar"
                    )

                    if let wordCount = item.wordCount {
                        SpeecharaHistoryMetaPill(
                            title: SLF("%@ words", String(wordCount)),
                            systemImage: "clock"
                        )
                    }

                    if let lineCount = item.lineCount {
                        SpeecharaHistoryMetaPill(
                            title: SLF("%@ lines", String(lineCount)),
                            systemImage: "text.alignleft"
                        )
                    }

                    if let languagePairLabel = item.languagePairLabel {
                        SpeecharaHistoryMetaPill(
                            title: languagePairLabel,
                            systemImage: "globe"
                        )
                    }
                }

                Text(item.previewText?.nilIfEmpty ?? "Preview text is not available yet.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeecharaHistoryTheme.secondaryText)
                    .lineLimit(3)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        SpeecharaHistoryStatusPill(
                            title: item.translationEnabled ? "Translation on" : "Translation off",
                            tint: item.translationEnabled ? Color(red: 0.18, green: 0.70, blue: 0.95) : SpeecharaHistoryTheme.neutralTint
                        )

                        SpeecharaHistoryStatusPill(
                            title: item.recordingEnabled ? "Recording on" : "Recording off",
                            tint: item.recordingEnabled ? Color(red: 0.21, green: 0.79, blue: 0.52) : SpeecharaHistoryTheme.neutralTint
                        )

                        SpeecharaHistoryStatusPill(
                            title: item.hasSummary ? "Summary ready" : "Summary missing",
                            tint: item.hasSummary ? Color(red: 0.26, green: 0.84, blue: 0.60) : SpeecharaHistoryTheme.neutralTint
                        )

                        SpeecharaHistoryStatusPill(
                            title: item.hasProtocol ? "Protocol ready" : "Protocol missing",
                            tint: item.hasProtocol ? Color(red: 0.28, green: 0.76, blue: 0.95) : SpeecharaHistoryTheme.neutralTint
                        )

                        SpeecharaHistoryStatusPill(
                            title: item.hasSuggestedAnswer ? "Reply draft ready" : "Reply draft missing",
                            tint: item.hasSuggestedAnswer ? Color(red: 0.94, green: 0.60, blue: 0.22) : SpeecharaHistoryTheme.neutralTint
                        )
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 12) {
                Text(item.durationLabel)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(SpeecharaHistoryTheme.primaryText)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(
                        Capsule()
                            .fill(SpeecharaHistoryTheme.elevatedFill)
                    )
                    .overlay(
                        Capsule()
                            .stroke(SpeecharaHistoryTheme.border, lineWidth: 1)
                    )

                Button(action: openAction) {
                    HStack(spacing: 8) {
                        if isOpening {
                            ProgressView()
                                .controlSize(.small)
                                .tint(SpeecharaHistoryTheme.accent)
                        } else {
                            Image(systemName: "eye")
                                .font(.system(size: 13, weight: .semibold))
                        }

                        Text(isOpening ? SL("Opening…") : SL("Open"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(SpeecharaHistoryTheme.primaryText)
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .background(
                        Capsule()
                            .fill(SpeecharaHistoryTheme.elevatedFill)
                    )
                    .overlay(
                        Capsule()
                            .stroke(SpeecharaHistoryTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(SpeecharaHistoryTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(SpeecharaHistoryTheme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 12)
    }
}

private struct SpeecharaHistoryDetailSheet: View {
    @ObservedObject var viewModel: SpeecharaHistoryViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    SpeecharaHistoryTheme.backgroundTop,
                    SpeecharaHistoryTheme.backgroundBottom,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                detailHeader

                if viewModel.isLoadingDetail && viewModel.selectedSessionDetail == nil {
                    SpeecharaHistoryLoadingCard(text: "Loading full session…")
                } else if let detailErrorMessage = viewModel.detailErrorMessage,
                          viewModel.selectedSessionDetail == nil {
                    SpeecharaHistoryErrorCard(
                        text: detailErrorMessage,
                        retryTitle: "Retry"
                    ) {
                        Task {
                            await viewModel.retrySelectedSession()
                        }
                    }
                } else if let detail = viewModel.selectedSessionDetail {
                    SpeecharaHistoryDetailTabBar(selection: $viewModel.selectedDetailTab)

                    ScrollView {
                        detailContent(detail)
                            .padding(.bottom, 28)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(28)
            .frame(maxWidth: 1120, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 1120, minHeight: 760)
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.selectedSessionDetail?.resolvedTitle ?? viewModel.selectedSessionSummary?.resolvedTitle ?? "History")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(SpeecharaHistoryTheme.primaryText)

            if let detail = viewModel.selectedSessionDetail {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        SpeecharaHistoryMetaPill(
                            title: detail.startedAt.formattedForHistory,
                            systemImage: "calendar"
                        )

                        SpeecharaHistoryMetaPill(
                            title: detail.durationLabel,
                            systemImage: "clock"
                        )

                        if let wordCount = detail.wordCount {
                            SpeecharaHistoryMetaPill(
                                title: SLF("%@ words", String(wordCount)),
                                systemImage: "text.word.spacing"
                            )
                        }

                        if let lineCount = detail.lineCount {
                            SpeecharaHistoryMetaPill(
                                title: SLF("%@ lines", String(lineCount)),
                                systemImage: "text.alignleft"
                            )
                        }

                        SpeecharaHistoryMetaPill(
                            title: SLF("revision %@", String(detail.revision)),
                            systemImage: "number"
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailContent(_ detail: MeetingSessionHistoryDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            switch viewModel.selectedDetailTab {
            case .transcribe:
                transcriptPanel(detail)
                compactMetadataFooter(detail)
            case .translate:
                translationPanel(detail)
                compactMetadataFooter(detail)
            case .summary:
                summaryPanel(detail)

                if let protocolText = detail.protocolText?.nilIfEmpty {
                    SpeecharaHistoryDetailPanel(title: "Protocol") {
                        SpeecharaDetailTextContent(text: protocolText)
                    }
                }

                if let suggestedAnswerText = detail.suggestedAnswerText?.nilIfEmpty {
                    SpeecharaHistoryDetailPanel(title: "Suggested reply") {
                        SpeecharaDetailTextContent(text: suggestedAnswerText)
                    }
                }
            }
        }
    }

    private func transcriptPanel(_ detail: MeetingSessionHistoryDetail) -> some View {
        SpeecharaHistoryDetailPanel(
            title: "Transcript",
            accessory: {
                HStack(spacing: 8) {
                    SpeecharaHistoryPanelActionButton(
                        title: "Summarize",
                        systemImage: "sparkles",
                        isEnabled: viewModel.canSummarize(detail),
                        isLoading: viewModel.isSummaryLoading,
                        action: viewModel.summarizeSelectedTranscript
                    )

                    SpeecharaHistoryPanelActionButton(
                        title: "Copy transcript",
                        systemImage: "doc.on.doc",
                        isEnabled: detail.copyableTranscriptText != nil,
                        action: viewModel.copySelectedTranscriptToPasteboard
                    )
                }
            }
        ) {
            if let transcriptJson = detail.transcriptJson, !transcriptJson.isEmpty {
                SpeecharaTranscriptBlockList(blocks: transcriptJson)
            } else {
                SpeecharaDetailTextContent(text: detail.transcriptText?.nilIfEmpty ?? "Transcript is not available.")
            }
        }
    }

    private func translationPanel(_ detail: MeetingSessionHistoryDetail) -> some View {
        SpeecharaHistoryDetailPanel(title: "Translation") {
            if let translationJson = detail.translationJson, !translationJson.isEmpty {
                SpeecharaTranslationBlockList(blocks: translationJson)
            } else {
                SpeecharaDetailTextContent(text: detail.translationText?.nilIfEmpty ?? "Translation is not available.")
            }
        }
    }

    private func summaryPanel(_ detail: MeetingSessionHistoryDetail) -> some View {
        SpeecharaHistoryDetailPanel(
            title: "Summary",
            accessory: {
                SpeecharaHistoryPanelActionButton(
                    title: "Summarize",
                    systemImage: "sparkles",
                    isEnabled: viewModel.canSummarize(detail),
                    isLoading: viewModel.isSummaryLoading,
                    action: viewModel.summarizeSelectedTranscript
                )
            }
        ) {
            SpeecharaHistorySummaryContent(
                text: viewModel.visibleSummaryText(for: detail),
                errorMessage: viewModel.summaryErrorMessage,
                isLoading: viewModel.isSummaryLoading
            )
        }
    }

    @ViewBuilder
    private func compactMetadataFooter(_ detail: MeetingSessionHistoryDetail) -> some View {
        let firstLine = [
            detail.statusLabel,
            detail.sessionParams?.source.nilIfEmpty,
            detail.processedByApp?.nilIfEmpty ?? detail.sessionParams?.client.nilIfEmpty,
            detail.microphoneLabel?.nilIfEmpty,
        ]
        .compactMap { $0 }
        .joined(separator: " • ")

        let secondLine = [
            detail.inputLanguage?.uppercased(),
            detail.translationLanguage?.uppercased() ?? "No translation",
        ]
        .compactMap { $0 }
        .joined(separator: " -> ")

        VStack(alignment: .leading, spacing: 4) {
            if !firstLine.isEmpty {
                Text(firstLine)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeecharaHistoryTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }

            if !secondLine.isEmpty {
                Text(secondLine)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeecharaHistoryTheme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 4)
    }

    private func detailStateCard(_ detail: MeetingSessionHistoryDetail) -> some View {
        SpeecharaHistoryDetailPanel(title: "Assets") {
            VStack(alignment: .leading, spacing: 10) {
                SpeecharaHistoryStatusPill(
                    title: detail.hasSummary ? "Summary available" : "Summary missing",
                    tint: detail.hasSummary ? Color(red: 0.26, green: 0.84, blue: 0.60) : SpeecharaHistoryTheme.neutralTint
                )

                SpeecharaHistoryStatusPill(
                    title: detail.hasProtocol ? "Protocol available" : "Protocol missing",
                    tint: detail.hasProtocol ? Color(red: 0.28, green: 0.76, blue: 0.95) : SpeecharaHistoryTheme.neutralTint
                )

                SpeecharaHistoryStatusPill(
                    title: detail.hasSuggestedAnswer ? "Suggested reply available" : "Suggested reply missing",
                    tint: detail.hasSuggestedAnswer ? Color(red: 0.94, green: 0.60, blue: 0.22) : SpeecharaHistoryTheme.neutralTint
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SpeecharaHistoryDetailTabBar: View {
    @Binding var selection: SpeecharaHistoryDetailTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SpeecharaHistoryDetailTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Label(SL(tab.title), systemImage: tab.systemImage)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(selection == tab ? SpeecharaHistoryTheme.primaryText : SpeecharaHistoryTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(selection == tab ? SpeecharaHistoryTheme.cardFill : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selection == tab ? SpeecharaHistoryTheme.border : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(SL(tab.title))
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(SpeecharaHistoryTheme.elevatedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(SpeecharaHistoryTheme.border, lineWidth: 1)
        )
    }
}

private struct SpeecharaHistoryDetailPanel<Accessory: View, Content: View>: View {
    let title: String
    private let accessory: Accessory
    private let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) where Accessory == EmptyView {
        self.title = title
        accessory = EmptyView()
        self.content = content()
    }

    init(
        title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text(SL(title))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(SpeecharaHistoryTheme.primaryText)

                Spacer(minLength: 0)

                accessory
            }

            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(SpeecharaHistoryTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(SpeecharaHistoryTheme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 18, x: 0, y: 10)
    }
}

private struct SpeecharaHistoryPanelActionButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(SpeecharaHistoryTheme.accent)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(SL(title))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isEnabled ? SpeecharaHistoryTheme.primaryText : SpeecharaHistoryTheme.tertiaryText)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                Capsule()
                    .fill(SpeecharaHistoryTheme.elevatedFill)
            )
            .overlay(
                Capsule()
                    .stroke(SpeecharaHistoryTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(SL(title))
    }
}

private struct SpeecharaTranscriptBlockList: View {
    let blocks: [MeetingSessionTranscriptBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { _, block in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        SpeecharaHistoryMetaPill(
                            title: block.timestamp,
                            systemImage: "clock"
                        )

                        if let speakerLabel = block.speakerLabel?.nilIfEmpty {
                            SpeecharaHistoryMetaPill(
                                title: speakerLabel,
                                systemImage: "person"
                            )
                        }
                    }

                    Text(block.text)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(SpeecharaHistoryTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(SpeecharaHistoryTheme.elevatedFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(SpeecharaHistoryTheme.border, lineWidth: 1)
                )
            }
        }
    }
}

private struct SpeecharaTranslationBlockList: View {
    let blocks: [MeetingSessionTranslationBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        SpeecharaHistoryMetaPill(
                            title: block.language.uppercased(),
                            systemImage: "globe"
                        )

                        SpeecharaHistoryMetaPill(
                            title: "#\(block.seq)",
                            systemImage: "number"
                        )
                    }

                    Text(block.text)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(SpeecharaHistoryTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(SpeecharaHistoryTheme.elevatedFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(SpeecharaHistoryTheme.border, lineWidth: 1)
                )
            }
        }
    }
}

private struct SpeecharaDetailTextContent: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .medium, design: .monospaced))
            .foregroundStyle(SpeecharaHistoryTheme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

private struct SpeecharaHistorySummaryContent: View {
    let text: String?
    let errorMessage: String?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(SpeecharaHistoryTheme.accent)

                    Text(SL("Summarizing transcript..."))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeecharaHistoryTheme.secondaryText)
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.84, green: 0.33, blue: 0.30))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if let text, !text.isEmpty {
                SpeecharaDetailTextContent(text: text)
            } else if !isLoading {
                Text(SL("No summary yet."))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeecharaHistoryTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SpeecharaHistoryMetaPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(SL(title), systemImage: systemImage)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(SpeecharaHistoryTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                Capsule()
                    .fill(SpeecharaHistoryTheme.elevatedFill)
            )
            .overlay(
                Capsule()
                    .stroke(SpeecharaHistoryTheme.border, lineWidth: 1)
            )
    }
}

private struct SpeecharaHistoryStatusPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(SL(title))
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                Capsule()
                    .fill(tint.opacity(0.10))
            )
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            )
    }
}

private struct SpeecharaHistoryCountBadge: View {
    let count: Int

    var body: some View {
        Label(SLF("%@ sessions", String(count)), systemImage: "clock")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(SpeecharaHistoryTheme.accent)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                Capsule()
                    .fill(SpeecharaHistoryTheme.accentFill)
            )
            .overlay(
                Capsule()
                    .stroke(SpeecharaHistoryTheme.border, lineWidth: 1)
            )
    }
}

private struct SpeecharaHistoryLoadingCard: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .tint(SpeecharaHistoryTheme.accent)

            Text(SL(text))
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(SpeecharaHistoryTheme.primaryText)

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(SpeecharaHistoryTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(SpeecharaHistoryTheme.border, lineWidth: 1)
        )
    }
}

private struct SpeecharaHistoryErrorCard: View {
    let text: String
    let retryTitle: String
    let retryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(SpeecharaHistoryTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(SL(retryTitle), action: retryAction)
                .buttonStyle(.bordered)
                .tint(Color(red: 0.84, green: 0.33, blue: 0.30))
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.red.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct SpeecharaHistoryEmptyCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(SL(title))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(SpeecharaHistoryTheme.primaryText)

            Text(SL(subtitle))
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(SpeecharaHistoryTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(SpeecharaHistoryTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(SpeecharaHistoryTheme.border, lineWidth: 1)
        )
    }
}

private extension MeetingSessionHistoryListItem {
    var resolvedTitle: String {
        title?.nilIfEmpty ?? previewText?.nilIfEmpty ?? SL("Untitled")
    }

    var languagePairLabel: String? {
        let source = inputLanguage?.uppercased()
        let target = translationLanguage?.uppercased()

        if translationEnabled, let source, let target {
            return "\(source) -> \(target)"
        }

        if let source {
            return "\(source) • \(SL("No translation"))"
        }

        return nil
    }

    var durationLabel: String {
        durationSeconds.formattedDuration
    }
}

private extension MeetingSessionHistoryDetail {
    var resolvedTitle: String {
        title?.nilIfEmpty ?? previewText?.nilIfEmpty ?? SL("Untitled")
    }

    var summaryLanguageName: String {
        Self.deepSeekLanguageName(for: inputLanguage)
    }

    var copyableTranscriptText: String? {
        if let transcriptJson, !transcriptJson.isEmpty {
            let lines = transcriptJson
                .sorted { first, second in
                    if first.seq == second.seq {
                        return first.timestamp < second.timestamp
                    }

                    return first.seq < second.seq
                }
                .compactMap { block -> String? in
                    let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else {
                        return nil
                    }

                    let timestamp = block.timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
                    let speakerLabel = block.speakerLabel?.nilIfEmpty

                    if let speakerLabel, !timestamp.isEmpty {
                        return "[\(timestamp)] \(speakerLabel): \(text)"
                    }

                    if let speakerLabel {
                        return "\(speakerLabel): \(text)"
                    }

                    if !timestamp.isEmpty {
                        return "[\(timestamp)] \(text)"
                    }

                    return text
                }

            return lines.joined(separator: "\n").nilIfEmpty
        }

        return transcriptText?.nilIfEmpty
    }

    func snapshot(replacingSummaryText summaryText: String) -> MeetingSessionHistorySnapshot {
        MeetingSessionHistorySnapshot(
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            status: snapshotStatus,
            inputLanguage: inputLanguage?.nilIfEmpty?.lowercased() ?? "en",
            translationLanguage: translationEnabled ? translationLanguage?.nilIfEmpty?.lowercased() : nil,
            translationEnabled: translationEnabled,
            recordingEnabled: recordingEnabled,
            microphoneLabel: microphoneLabel?.nilIfEmpty,
            transcriptBlocks: persistedTranscriptBlocks,
            translationBlocks: persistedTranslationBlocks,
            summaryText: summaryText.nilIfEmpty,
            protocolText: protocolText?.nilIfEmpty,
            suggestedAnswerText: suggestedAnswerText?.nilIfEmpty,
            sessionParams: persistedSessionParams
        )
    }

    var durationLabel: String {
        durationSeconds.formattedDuration
    }

    var statusLabel: String {
        switch status.lowercased() {
        case "completed":
            return SL("Completed")
        case "active":
            return SL("Active")
        default:
            return status
        }
    }

    private var snapshotStatus: MeetingSessionHistoryStatus {
        if status.lowercased() == MeetingSessionHistoryStatus.active.rawValue {
            return .active
        }

        return .completed
    }

    private var persistedTranscriptBlocks: [MeetingSessionTranscriptBlock] {
        if let transcriptJson, !transcriptJson.isEmpty {
            return transcriptJson
        }

        let lines = transcriptText?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        return lines.enumerated().compactMap { index, line in
            let components = line.historyTimestampedComponents
            guard !components.text.isEmpty else {
                return nil
            }

            return MeetingSessionTranscriptBlock(
                id: "history-\(id)-transcript-\(index + 1)",
                seq: index + 1,
                timestamp: components.timestamp,
                speakerLabel: nil,
                text: components.text
            )
        }
    }

    private var persistedTranslationBlocks: [MeetingSessionTranslationBlock] {
        if let translationJson, !translationJson.isEmpty {
            return translationJson
        }

        guard let translationText = translationText?.nilIfEmpty else {
            return []
        }

        let transcriptBlocks = persistedTranscriptBlocks
        let translationLanguage = translationLanguage?.nilIfEmpty?.lowercased() ?? "translation"
        let lines = translationText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.enumerated().map { index, line in
            let transcriptBlock = index < transcriptBlocks.count ? transcriptBlocks[index] : nil
            let seq = transcriptBlock?.seq ?? index + 1

            return MeetingSessionTranslationBlock(
                transcriptBlockId: transcriptBlock?.id ?? "history-\(id)-transcript-\(seq)",
                seq: seq,
                language: translationLanguage,
                text: line.removingLeadingTimestamp
            )
        }
    }

    private var persistedSessionParams: MeetingSessionHistorySessionParams {
        sessionParams ?? MeetingSessionHistorySessionParams(
            client: processedByApp?.nilIfEmpty ?? "macos",
            source: "history",
            appVersion: nil,
            focusMode: nil
        )
    }

    private static func deepSeekLanguageName(for languageCode: String?) -> String {
        let normalizedCode = languageCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: "-")
            .first
            .map(String.init)

        switch normalizedCode {
        case "ru", "russian":
            return "Russian"
        case "de", "german":
            return "German"
        case "es", "spanish":
            return "Spanish"
        case "fr", "french":
            return "French"
        default:
            return "English"
        }
    }
}

private extension Optional where Wrapped == Int {
    var formattedDuration: String {
        guard let seconds = self, seconds > 0 else {
            return "00:00"
        }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private extension Date {
    var formattedForHistory: String {
        let formatter = DateFormatter()
        formatter.locale = SpeecharaLocalizationStore.shared.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var removingLeadingTimestamp: String {
        historyTimestampedComponents.text
    }

    var historyTimestampedComponents: (timestamp: String, text: String) {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              let closingBracket = trimmed.firstIndex(of: "]") else {
            return ("00:00:00", trimmed)
        }

        let timestampStart = trimmed.index(after: trimmed.startIndex)
        let timestamp = String(trimmed[timestampStart ..< closingBracket])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let textStart = trimmed.index(after: closingBracket)
        let text = String(trimmed[textStart...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard timestamp.count >= 5 else {
            return ("00:00:00", trimmed)
        }

        return (timestamp, text)
    }
}
