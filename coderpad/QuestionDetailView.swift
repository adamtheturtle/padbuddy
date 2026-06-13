//
//  QuestionDetailView.swift
//  coderpad
//

import SwiftUI

struct QuestionDetailView: View {
    let client: CoderPadClient
    let question: Question
    @Environment(\.openWindow) var openWindow
    @Environment(\.orgDirectory) var directory
    @State private var nav = AppNavigation.shared
    @State private var accounts = AccountsStore.shared
    @State private var favorites = FavoriteQuestionsStore.shared
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var deleteError: String?
    /// The in-flight delayed deletion, shown as an undoable banner during the grace
    /// period. Cancelling it (Undo) aborts before the API call fires.
    @State private var deletionTask: Task<Void, Never>?
    @State private var isCreatingPad = false
    @State private var createPadError: String?
    @State var showBrowser = false
    @State var createdPadURL: URL?

    // Detail-column actions live in the unified window toolbar rather than in
    // the content header: there they float on the system Liquid Glass layer
    // automatically, and the header stays free for identity and metadata. A
    // leading spacer separates them from the Questions list's own toolbar
    // items (Sort, Reload, New Question) so "New Pad" doesn't read as a
    // sibling of "New Question".
    @ToolbarContentBuilder
    private var detailToolbar: some CustomizableToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        }
        ToolbarItem(id: "favoriteQuestion", placement: .primaryAction) {
            Button { toggleFavorite() } label: {
                Label(isFavorite ? "Favorited" : "Favorite",
                      systemImage: isFavorite ? "star.fill" : "star")
            }
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
        ToolbarItem(id: "newPad", placement: .primaryAction) {
            Button { Task { await createPadInline() } } label: {
                if isCreatingPad {
                    ProgressView().controlSize(.small)
                } else {
                    Label("New Pad", systemImage: "doc.badge.plus")
                }
            }
            .disabled(isCreatingPad)
            .help("Create a new interview pad from this question")
            .accessibilityLabel("New Pad")
        }
        ToolbarItem(id: "editQuestion", placement: .primaryAction) {
            Button { showEdit = true } label: {
                Label("Edit", systemImage: "pencil")
            }
            .help("Edit question")
        }
        ToolbarItem(id: "deleteQuestion", placement: .primaryAction) {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete question")
            .accessibilityLabel("Delete question")
        }
    }

    var body: some View {
        Group {
            if showBrowser, let url = createdPadURL {
                padBrowser(url: url)
            } else {
                detailScroll
            }
        }
        .overlay(alignment: .bottom) { undoDeletionBanner }
        .animation(.spring(duration: 0.3), value: deletionTask == nil)
        .navigationTitle(question.title.isEmpty ? "#\(question.id)" : question.title)
        // Publish the favorite state so the Question menu's Favorite command can
        // show the matching "Add to"/"Remove from Favorites" title and toggle it.
        .focusedSceneValue(\.focusedQuestionIsFavorite, isFavorite)
        .toolbar(id: "question.detail.toolbar") { detailToolbar }
        .sheet(isPresented: $showEdit) {
            EditQuestionSheet(client: client, original: question) { updated in
                NotificationCenter.default.post(name: .questionUpdated, object: updated)
                showEdit = false
            } onCancel: { showEdit = false }
        }
        .confirmationDialog("Delete \(question.title.isEmpty ? "this question" : question.title)?",
                            isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { startDeletion() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll have a few seconds to undo before it's permanently deleted.")
        }
        .alert("Couldn’t create pad",
               isPresented: Binding(get: { createPadError != nil },
                                    set: { if !$0 { createPadError = nil } })) {
            Button("OK", role: .cancel) { createPadError = nil }
        } message: {
            if let createPadError { Text(createPadError) }
        }
        .onAppear {
            consumePendingPadCreation()
            consumePendingEdit()
            consumePendingDelete()
            consumePendingFavoriteToggle()
        }
        .onChange(of: nav.createPadForQuestionID) { _, _ in consumePendingPadCreation() }
        .onChange(of: nav.editQuestionID) { _, _ in consumePendingEdit() }
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
            NotificationCenter.default.post(name: .questionDeleted, object: question.id)
        } catch {
            deleteError = error.localizedDescription
        }
    }

    @ViewBuilder
    var undoDeletionBanner: some View {
        if deletionTask != nil {
            HStack(spacing: 12) {
                Image(systemName: "trash")
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
        favorites.toggle(question.id, account: account)
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

    /// Honors an "Edit Question" request routed via `AppNavigation` from the list's
    /// context menu by presenting the same edit sheet as the in-pane Edit button.
    private func consumePendingEdit() {
        guard nav.editQuestionID == question.id else { return }
        nav.editQuestionID = nil
        showEdit = true
    }

    /// Honors a "Delete Question" request from the list's context menu by showing
    /// the same delete confirmation as the in-pane Delete button — never deleting
    /// without that confirmation step.
    private func consumePendingDelete() {
        guard nav.deleteQuestionID == question.id else { return }
        nav.deleteQuestionID = nil
        showDeleteConfirm = true
    }

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
