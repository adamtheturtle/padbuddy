//
//  QuestionDetailView.swift
//  coderpad
//

import SwiftUI
import UniformTypeIdentifiers

nonisolated enum QuestionDetailPane: String, CaseIterable, DetailChipItem {
    case prompt
    case materials
    case solution

    var id: Self {
        self
    }

    var label: LocalizedStringKey {
        switch self {
        case .prompt: "Prompt"
        case .materials: "Materials"
        case .solution: "Solution"
        }
    }

    var systemImage: String {
        switch self {
        case .prompt: "text.alignleft"
        case .materials: "shippingbox"
        case .solution: "checkmark.seal"
        }
    }
}

struct QuestionDetailView: View {
    let client: CoderPadClient
    let question: Question
    /// The account this question belongs to, so edit/delete notifications can be
    /// scoped to it — per-org question ids collide across accounts in the combined
    /// view. `nil` when unknown (consumers then fall back to id-only matching).
    var accountID: UUID?
    @Environment(\.orgDirectory) var directory
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.undoManager) var undoManager
    #if os(iOS)
        @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    /// While offline the app is read-only, so create/edit/delete actions disable (#321).
    @Environment(\.isReadOnly) var isReadOnly
    /// Snap the undo-deletion banner instead of springing it when Reduce Motion is on (#614).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nav = AppNavigation.shared
    // Internal, not private: the favorites helpers live in
    // QuestionDetailView+Favorites.swift (split for file length).
    @State var accounts = AccountsStore.shared
    @State var favorites = FavoriteQuestionsStore.shared
    @State private var showDeleteConfirm = false
    @State private var deleteError: String?
    /// The in-flight delayed deletion, shown as an undoable banner during the grace
    /// period. Cancelling it (Undo) aborts before the API call fires.
    @State var deletionTask: Task<Void, Never>?
    @State var isCreatingPad = false
    @State var createPadError: String?
    #if !os(macOS)
        /// The Markdown export staged for iPad's `.fileExporter`.
        /// `nil` dismisses the export sheet.
        @State var pendingExport: PadExportDocument?
    #endif
    // Inline metadata drafts (language, type), seeded from the question and
    // committed one field at a time, mirroring the pad detail editor. The long-form
    // content (description, instructions, solution) is edited in place too (#335).
    @State var draftLanguage = "python3"
    @State var draftPadType = "live"
    @State var editError: String?
    /// Latest locally-published question, used as the merge base for concurrent field saves.
    @State var latestQuestion: Question?
    /// Claim ticket for the newest publish into `latestQuestion`. The background
    /// reconciliation read must not install a server copy that predates an edit
    /// the user made while that read was in flight (#2654).
    @State var questionPublishGeneration = 0
    @State var selectedPane: QuestionDetailPane = .prompt
    @State var titleEditRequest = 0
    /// Generation counter for the deferred draft seeding (see `scheduleSeedDrafts`),
    /// so a stale queued seed can't overwrite a newer question's drafts (#1192).
    @State var draftSeedGeneration = 0

    private var detailToolbarLeadingPlacement: ToolbarItemPlacement {
        #if os(macOS)
            .primaryAction
        #else
            .topBarLeading
        #endif
    }

    private var detailToolbarTrailingPlacement: ToolbarItemPlacement {
        #if os(macOS)
            .primaryAction
        #else
            .topBarTrailing
        #endif
    }

    /// Detail-column actions live in the unified window toolbar rather than in
    /// the content header: there they float on the system Liquid Glass layer
    /// automatically, and the header stays free for identity and metadata. A
    /// leading spacer separates them from the Questions list's own toolbar
    /// items (Sort, Reload, New Question) so "New Pad" doesn't read as a
    /// sibling of "New Question". Delete stays out of the default toolbar, but
    /// remains available through the Question menu and as an opt-in customizable
    /// toolbar item.
    ///
    /// Split into leading and trailing halves so each stays inside the
    /// function-body length limit.
    @ToolbarContentBuilder
    private func detailToolbar(questionURL: URL) -> some CustomizableToolbarContent {
        ToolbarSpacer(.fixed)
        leadingToolbarItems
        trailingToolbarItems(questionURL: questionURL)
    }

    /// Question-authoring actions: favoriting, and creating a pad from this question.
    @ToolbarContentBuilder
    private var leadingToolbarItems: some CustomizableToolbarContent {
        ToolbarItem(id: "favorite", placement: detailToolbarLeadingPlacement) {
            Button { toggleFavorite() } label: {
                Label(isFavorite ? String(localized: "Favorited") : String(localized: "Favorite"),
                      systemImage: isFavorite ? "star.fill" : "star")
                    // Match the row stars' swap animation so favoriting feels the same
                    // wherever you do it (#627).
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"))
            .accessibilityLabel(isFavorite
                ? String(localized: "Remove from Favorites")
                : String(localized: "Add to Favorites"))
        }
        ToolbarItem(id: "new-pad", placement: detailToolbarLeadingPlacement) {
            Button { Task { await createPadInline() } } label: {
                if isCreatingPad {
                    ProgressView().controlSize(.small)
                } else {
                    Label("New Pad", systemImage: "doc.badge.plus")
                }
            }
            .disabled(isCreatingPad || isReadOnly)
            .help("Create a new interview pad from this question")
            .accessibilityLabel("New Pad")
        }
    }

    /// Sharing, document export, and the opt-in Delete item.
    @ToolbarContentBuilder
    private func trailingToolbarItems(questionURL: URL) -> some CustomizableToolbarContent {
        ToolbarItem(id: "share", placement: detailToolbarTrailingPlacement) {
            ShareLink(item: questionURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Share a link to this question")
        }
        #if !os(macOS)
            // iPad has no menu bar, so File-menu document actions live in a
            // detail-pane overflow just like pad detail's document actions.
            ToolbarItem(id: "documents", placement: detailToolbarTrailingPlacement) {
                Menu {
                    Button { printQuestionDocument() } label: {
                        Label("Print", systemImage: "printer")
                    }
                    Button { exportMarkdown() } label: {
                        Label("Export as Markdown", systemImage: "doc.richtext")
                    }
                } label: {
                    Label("Document Actions", systemImage: "ellipsis.circle")
                }
            }
        #endif
        ToolbarItem(id: "delete", placement: detailToolbarTrailingPlacement) {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(isReadOnly)
            .help("Delete question")
            .accessibilityLabel("Delete question")
        }
        .defaultCustomization(.hidden)
    }

    var body: some View {
        draftSync(core)
            // Error haptic when a delete fails; fires only on the transition into an
            // error, not on dismissal. No-op on macOS (#611).
            .sensoryFeedback(trigger: deleteError) { _, new in new != nil ? .error : nil }
    }

    /// `core` is staged through helper functions so each getter stays under the
    /// 250ms type-check budget (warnings-as-errors): the single full modifier chain
    /// blew it on the iOS build once the draft/export modifiers landed.
    private var core: some View {
        let questionURL = question.webURL(baseURL: client.baseURL)
        let questionFingerprint = question.hashValue
        return withNavigationConsumption(
            withCommandsAndAlerts(
                withBanners(detailScroll, questionURL: questionURL, questionFingerprint: questionFingerprint),
                questionURL: questionURL
            )
        )
    }

    private func withBanners(_ content: some View, questionURL: URL, questionFingerprint: Int) -> some View {
        content
            .overlay(alignment: .bottom) { bottomBanners }
            .animation(reduceMotion ? nil : .spring(duration: 0.3), value: deletionTask == nil)
            .animation(reduceMotion ? nil : .spring(duration: 0.3), value: createPadError == nil)
            // Publish the favorite state so the Question menu's Favorite command can
            // show the matching "Add to"/"Remove from Favorites" title and toggle it.
            .focusedSceneValue(\.focusedQuestionIsFavorite, isFavorite)
            // Publish the question's web URL so the Question menu's Share/Copy URL
            // commands act on the same link, built from this account's server URL.
            .focusedSceneValue(\.focusedQuestionURL, questionURL)
            // Publish a print rendering so File ▸ Print (⌘P) can produce a hard copy
            // or PDF of the prompt, instructions, and solution.
            .focusedSceneValue(\.printAction, PrintAction(id: "question-\(question.id)",
                                                          contentFingerprint: questionFingerprint) {
                    printQuestionDocument()
                })
            .focusedSceneValue(\.exportMarkdownAction, PrintAction(id: "question-\(question.id)",
                                                                   contentFingerprint: questionFingerprint) {
                    exportMarkdown()
                })
    }

    private func withCommandsAndAlerts(_ content: some View, questionURL: URL) -> some View {
        content
            .toolbar(id: "question-detail") { detailToolbar(questionURL: questionURL) }
            .alert(
                "Delete \(question.title.isEmpty ? "this question" : question.title)?",
                isPresented: $showDeleteConfirm
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { startDeletion() }
            } message: {
                Text("You'll have a few seconds to undo before it's permanently deleted.")
            }
            .modifier(QuestionDetailErrorAlerts(editError: $editError,
                                                deleteError: $deleteError))
        #if !os(macOS)
            .fileExporter(
                isPresented: .init(get: { pendingExport != nil },
                                   set: { if !$0 { pendingExport = nil } }),
                document: pendingExport,
                contentType: pendingExport?.contentType ?? .plainText,
                defaultFilename: pendingExport?.defaultName
            ) { result in
                if case let .failure(error) = result {
                    editError = error.localizedDescription
                }
                pendingExport = nil
            }
        #endif
    }

    /// Consumption is focus-gated: question ids collide across accounts, so with
    /// A/42 and B/42 open in separate windows either detail could consume a
    /// command aimed at the other - creating from, favoriting, or presenting
    /// deletion in the wrong organization (#869). Only the focused window's
    /// detail consumes now.
    private func withNavigationConsumption(_ content: some View) -> some View {
        content
            // Navigating away hides the undo banner - the only remaining way to stop
            // a pending deletion - so the armed task must not outlive it. Cancel the
            // grace period instead of letting the delete finish invisibly (#870).
            .onDisappear { cancelDeletion() }
            .consumesWindowRequest(nav.createPadForQuestionID) { consumePendingPadCreation() }
            .consumesWindowRequest(nav.editQuestionID) { consumePendingEdit() }
            .consumesWindowRequest(nav.deleteQuestionID) { consumePendingDelete() }
            .consumesWindowRequest(nav.toggleFavoriteQuestionID) { consumePendingFavoriteToggle() }
    }

    /// Consumes an "Edit Question" request routed via `AppNavigation` from the
    /// Question menu, opening the inline title editor.
    private func consumePendingEdit() {
        guard let request = nav.editQuestionID, request.id == question.id,
              request.account == nil || request.account == accountID else { return }

        nav.editQuestionID = nil
        titleEditRequest += 1
    }

    /// Honors a "Favorite" request from the Question menu by toggling the same
    /// per-account favorite state as the in-pane toolbar star.
    private func consumePendingFavoriteToggle() {
        guard let request = nav.toggleFavoriteQuestionID, request.id == question.id,
              request.account == nil || request.account == accountID else { return }

        nav.toggleFavoriteQuestionID = nil
        toggleFavorite()
    }

    /// Grace period during which a confirmed deletion can still be undone.
    private static let deletionGracePeriod: Duration = .seconds(5)

    /// Begins a delayed deletion: an undo banner appears for the grace period, and
    /// the API delete only fires if it isn't cancelled. A no-op if one is already
    /// pending (the confirm dialog can't reopen while the banner is up).
    private func startDeletion() {
        guard deletionTask == nil else { return }

        deletionTask = Task {
            try? await Task.sleep(for: Self.deletionGracePeriod)
            if Task.isCancelled { return }
            // The grace period is over: drop the banner (and its Undo) BEFORE the
            // irreversible API request starts. An Undo pressed mid-request would
            // pretend to cancel a deletion the server may still complete (#725).
            deletionTask = nil
            await performDelete()
        }
    }

    func cancelDeletion() {
        deletionTask?.cancel()
        deletionTask = nil
    }

    private func performDelete() async {
        do {
            try await client.deleteQuestion(id: question.id)
            AppRouter.questionDeleted(id: question.id, account: accountID)
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func consumePendingPadCreation() {
        guard let request = nav.createPadForQuestionID, request.id == question.id,
              request.account == nil || request.account == accountID else { return }

        nav.createPadForQuestionID = nil
        Task {
            guard let url = await makePadFromQuestion() else { return }

            BrowserSettings.openExternally(url)
        }
    }

    /// Honors a "Delete Question" request from the list's context menu by showing
    /// the same delete confirmation as the in-pane Delete button — never deleting
    /// without that confirmation step.
    private func consumePendingDelete() {
        guard let request = nav.deleteQuestionID, request.id == question.id,
              request.account == nil || request.account == accountID else { return }

        nav.deleteQuestionID = nil
        showDeleteConfirm = true
    }

    /// Creates a pad from this question and opens it in the user's browser.
    func createPadInline() async {
        if let url = await makePadFromQuestion() {
            BrowserSettings.openExternally(url)
        }
    }

    /// Creates a pad from this question, returning its web URL (or nil on failure,
    /// after recording the error).
    private func makePadFromQuestion() async -> URL? {
        createPadError = nil
        isCreatingPad = true
        defer { isCreatingPad = false }
        do {
            let pad = try await client.createPad(.fromQuestion(question))
            return pad.webURL
        } catch {
            createPadError = error.localizedDescription
            return nil
        }
    }
}
