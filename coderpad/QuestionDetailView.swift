//
//  QuestionDetailView.swift
//  coderpad
//

import SwiftUI

struct QuestionDetailView: View {
    let client: CoderPadClient
    let question: Question
    /// The account this question belongs to, so edit/delete notifications can be
    /// scoped to it — per-org question ids collide across accounts in the combined
    /// view. `nil` when unknown (consumers then fall back to id-only matching).
    var accountID: UUID?
    @Environment(\.openWindow) var openWindow
    @Environment(\.orgDirectory) var directory
    @Environment(\.colorScheme) var colorScheme
    /// While offline the app is read-only, so create/edit/delete actions disable (#321).
    @Environment(\.isReadOnly) var isReadOnly
    /// Snap the undo-deletion banner instead of springing it when Reduce Motion is on (#614).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nav = AppNavigation.shared
    @State private var accounts = AccountsStore.shared
    @State private var favorites = FavoriteQuestionsStore.shared
    @State private var showDeleteConfirm = false
    @State private var deleteError: String?
    /// The in-flight delayed deletion, shown as an undoable banner during the grace
    /// period. Cancelling it (Undo) aborts before the API call fires.
    @State private var deletionTask: Task<Void, Never>?
    @State private var isCreatingPad = false
    @State private var createPadError: String?
    @State var showBrowser = false
    @State var createdPadURL: URL?
    // Inline metadata drafts (title, language, type), seeded from the question and
    // committed one field at a time, mirroring the pad detail editor. The long-form
    // content (description, instructions, solution) is edited in place too (#335).
    @State var titleDraft = ""
    @State var draftLanguage = "python3"
    @State var draftPadType = "live"
    @State var editError: String?
    @FocusState var titleFocused: Bool

    /// Detail-column actions live in the unified window toolbar rather than in
    /// the content header: there they float on the system Liquid Glass layer
    /// automatically, and the header stays free for identity and metadata. A
    /// leading spacer separates them from the Questions list's own toolbar
    /// items (Sort, Reload, New Question) so "New Pad" doesn't read as a
    /// sibling of "New Question".
    @ToolbarContentBuilder
    private var detailToolbar: some CustomizableToolbarContent {
        if #available(macOS 26, iOS 26, *) {
            ToolbarSpacer(.fixed)
        }
        ToolbarItem(id: "favorite", placement: .primaryAction) {
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
        ToolbarItem(id: "new-pad", placement: .primaryAction) {
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
        ToolbarItem(id: "share", placement: .primaryAction) {
            ShareLink(item: question.webURL(baseURL: client.baseURL)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Share a link to this question")
        }
        ToolbarItem(id: "delete", placement: .primaryAction) {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(isReadOnly)
            .help("Delete question")
            .accessibilityLabel("Delete question")
        }
    }

    var body: some View {
        draftSync(core)
    }

    private var core: some View {
        Group {
            if showBrowser, let url = createdPadURL {
                padBrowser(url: url)
            } else {
                detailScroll
            }
        }
        .overlay(alignment: .bottom) { undoDeletionBanner }
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: deletionTask == nil)
        // Publish the favorite state so the Question menu's Favorite command can
        // show the matching "Add to"/"Remove from Favorites" title and toggle it.
        .focusedSceneValue(\.focusedQuestionIsFavorite, isFavorite)
        // Publish the question's web URL so the Question menu's Share/Copy URL
        // commands act on the same link, built from this account's server URL.
        .focusedSceneValue(\.focusedQuestionURL, question.webURL(baseURL: client.baseURL))
        // Publish a print rendering so File ▸ Print (⌘P) can produce a hard copy
        // or PDF of the prompt, instructions, and solution.
        .focusedSceneValue(\.printAction, PrintAction(id: "question-\(question.id)") {
            printDocument(QuestionPrintDocument(question: question),
                          jobTitle: question.displayTitle)
        })
        .toolbar(id: "question-detail") { detailToolbar }
        .confirmationDialog("Delete \(question.title.isEmpty ? "this question" : question.title)?",
                            isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { startDeletion() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll have a few seconds to undo before it's permanently deleted.")
        }
        .modifier(QuestionDetailErrorAlerts(createPadError: $createPadError,
                                            editError: $editError,
                                            deleteError: $deleteError))
        .onAppear {
            consumePendingPadCreation()
            consumePendingDelete()
            consumePendingFavoriteToggle()
        }
        .onChange(of: nav.createPadForQuestionID) { _, _ in consumePendingPadCreation() }
        .onChange(of: nav.deleteQuestionID) { _, _ in consumePendingDelete() }
        .onChange(of: nav.toggleFavoriteQuestionID) { _, _ in consumePendingFavoriteToggle() }
    }

    /// Honors a "Favorite" request from the Question menu by toggling the same
    /// per-account favorite state as the in-pane toolbar star.
    private func consumePendingFavoriteToggle() {
        guard nav.toggleFavoriteQuestionID == question.id else { return }

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
            await performDelete()
            deletionTask = nil
        }
    }

    private func cancelDeletion() {
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

    @ViewBuilder
    var undoDeletionBanner: some View {
        if deletionTask != nil {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .accessibilityHidden(true)
                Text("Deleting “\(question.title.isEmpty ? "this question" : question.title)”…")
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") { cancelDeletion() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.subtleStroke, lineWidth: 1))
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Whether the displayed question is a favorite of the current account, so the
    /// toolbar star can reflect and toggle its state.
    private var isFavorite: Bool {
        favorites.isFavorite(question.id, account: accounts.currentAccountID)
    }

    private func toggleFavorite() {
        guard let account = accounts.currentAccountID else { return }

        favorites.toggle(question.id, title: question.displayTitle, account: account)
    }

    /// Honors a "New Pad from Question" request routed via `AppNavigation` (e.g.
    /// from the Questions list's context menu): create the pad and open it inline,
    /// exactly as the in-pane "New Pad" button does.
    private func consumePendingPadCreation() {
        guard nav.createPadForQuestionID == question.id else { return }

        nav.createPadForQuestionID = nil
        // A routed request can outlive this detail pane — the user may select
        // another question before creation finishes, recreating the view (`.id`)
        // and discarding its inline-browser state. Open the result in the standard
        // pad-browser window instead (captured `openWindow` survives the teardown),
        // matching how pads open elsewhere.
        let openWindow = openWindow
        Task {
            guard let url = await makePadFromQuestion() else { return }

            if BrowserSettings.openLinksIn == .external {
                BrowserSettings.openExternally(url)
            } else {
                openWindow(id: "pad-browser", value: url)
            }
        }
    }

    /// Honors a "Delete Question" request from the list's context menu by showing
    /// the same delete confirmation as the in-pane Delete button — never deleting
    /// without that confirmation step.
    private func consumePendingDelete() {
        guard nav.deleteQuestionID == question.id else { return }

        nav.deleteQuestionID = nil
        showDeleteConfirm = true
    }

    /// The `userInfo` attached to edit/delete notifications, carrying the owning
    /// account so combined-view consumers scope the change correctly. Empty when
    /// the account is unknown.
    /// Creates a pad from this question and browses it inline in this pane. Used by
    /// the in-pane "New Pad" button, where the user is looking at this detail.
    private func createPadInline() async {
        if let url = await makePadFromQuestion() {
            createdPadURL = url
            showBrowser = true
        }
    }

    /// Creates a pad from this question, returning its web URL (or nil on failure,
    /// after recording the error). Presentation is left to the caller so a routed
    /// request can open a durable window while the in-pane button browses inline.
    private func makePadFromQuestion() async -> URL? {
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

/// The detail view's three failure alerts (pad creation, edit, delete), pulled
/// into a `ViewModifier` so they don't inflate the `core` view body's type-check
/// time past the warnings-as-errors limit.
private struct QuestionDetailErrorAlerts: ViewModifier {
    @Binding var createPadError: String?
    @Binding var editError: String?
    @Binding var deleteError: String?

    func body(content: Content) -> some View {
        content
            .alert("Couldn’t create pad",
                   isPresented: Binding(get: { createPadError != nil },
                                        set: { if !$0 { createPadError = nil } })) {
                Button("OK", role: .cancel) { createPadError = nil }
            } message: {
                if let createPadError { Text(createPadError) }
            }
            .alert("Couldn’t save question",
                   isPresented: Binding(get: { editError != nil },
                                        set: { if !$0 { editError = nil } })) {
                Button("OK", role: .cancel) { editError = nil }
            } message: {
                if let editError { Text(editError) }
            }
            .alert("Couldn’t delete question",
                   isPresented: Binding(get: { deleteError != nil },
                                        set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                if let deleteError { Text(deleteError) }
            }
    }
}
