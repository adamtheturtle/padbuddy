//
//  AppNavigation.swift
//  coderpad
//

import Foundation

/// A one-shot request for the Pads pane to apply when it next appears. Unlike a
/// transient notification, it survives until the destination view actually mounts
/// and consumes it — so "switch to Pads, then filter/search/create" works even
/// when PadsView isn't on screen at the moment the request is made.
struct PadsRequest: Equatable {
    var ownerEmail: String?
    var search: String?
    var startCreating = false
    /// A question to pre-select in the create sheet when `startCreating` is set —
    /// e.g. the New Pad widget button configured to seed from a favourite question.
    var seedQuestionID: Int?
    /// A search to apply wholesale when the pane appears. Carries the full filter
    /// set so picking a Suggested search from the sidebar reproduces exactly what it
    /// captured — the same as tapping its in-pane chip.
    var applySearch: NamedSearch?
    /// A favorite pad to select when the pane appears, addressed by id since the
    /// sidebar that routes it holds favorite ids, not the loaded `Pad`s (mirrors
    /// `QuestionsRequest.selectQuestionID`).
    var selectPadID: String?
}

/// The Questions-pane equivalent of `PadsRequest`.
struct QuestionsRequest: Equatable {
    var search: String?
    var startCreating = false
    /// A search to apply wholesale when the pane appears (see `PadsRequest`).
    var applySearch: NamedSearch?
    /// A favorite question to select when the pane appears, addressed by id since
    /// the sidebar that routes it holds favorite ids, not the loaded `Question`s.
    var selectQuestionID: Int?
}

/// Single source of truth for the visible section and any pending request queued
/// for a section's pane. Centralizing this removes the ordering hazard of posting
/// "switch section" and "apply filter" as two separate notifications: the target
/// pane may not be mounted yet when the second one fires, so it would be dropped.
/// Here the request is durable state the pane reads on appear.
@Observable
final class AppNavigation {
    static let shared = AppNavigation()
    private init() {}

    var section: AppSection = .pads

    /// Consumed and cleared by PadsView when it appears or this value changes.
    var padsRequest: PadsRequest?
    /// Consumed and cleared by QuestionsView when it appears or this value changes.
    var questionsRequest: QuestionsRequest?

    // The per-window published state that used to live here (the Screen campaign
    // selection and candidate-count subtitle, the section result-count subtitle,
    // and the merged lists' live "Mine"/"Active" preset flags) moved to
    // `WindowNavigation`, one instance per scene: a single process-wide value made
    // every window display or act on whichever window published last (#887, #888,
    // #908, #909). This type keeps only the process-wide request mailbox.

    /// One-shot toggle requests for the combined lists' "Mine"/"Active" presets,
    /// set by the sidebar (or an App Intent); the merged view consumes and clears
    /// the request, applies it, and republishes the result to its window's
    /// `WindowNavigation`. A request rather than a binding because the combined
    /// views own their filters locally (their "Mine" is per-account ownership, not
    /// a single owner email) and may not be mounted when the request is made.
    var mergedPadsMineRequest: Bool?
    var mergedQuestionsMineRequest: Bool?
    var mergedPadsActiveRequest: Bool?

    /// A favourite question chosen from the sidebar (or Spotlight / the command
    /// palette) while in the combined "All Accounts" view, carrying its account so
    /// the combined questions list selects the right row - per-org ids collide, so
    /// the id alone is ambiguous. Consumed and cleared by `MergedQuestionsView`.
    var pendingMergedFavoriteQuestion: MergedFavorite?

    /// Switch-to-merged-questions request for a favourite: the question id and the
    /// account it belongs to.
    struct MergedFavorite: Equatable {
        let account: UUID
        let id: Int
    }

    /// A favourite pad chosen from the sidebar (or the command palette) while in
    /// the combined "All Accounts" view, carrying its account so the combined pads
    /// list selects the right row - pad slugs are only unique per server, so two
    /// custom CoderPad servers can issue the same slug and the id alone is
    /// ambiguous (#758). Consumed and cleared by `MergedPadsView`.
    var pendingMergedFavoritePad: MergedFavoritePad?

    /// Switch-to-merged-pads request for a favourite: the pad slug and the
    /// account it belongs to.
    struct MergedFavoritePad: Equatable {
        let account: UUID
        let id: String
    }

    func selectMergedFavoriteQuestion(account: UUID, id: Int) {
        pendingMergedFavoriteQuestion = MergedFavorite(account: account, id: id)
    }

    func selectMergedFavoritePad(account: UUID, id: String) {
        pendingMergedFavoritePad = MergedFavoritePad(account: account, id: id)
    }

    /// A question id whose detail pane should immediately create a pad and open it
    /// inline (the in-pane browser), matching the detail view's "New Pad" button.
    /// Set by the Questions list's context menu (after selecting that question) and
    /// consumed/cleared by QuestionDetailView when it appears or this value changes.
    var createPadForQuestionID: Int?

    /// A question id whose detail pane should immediately open title editing,
    /// matching the detail view's inline rename affordance and the Pad menu's
    /// command-driven edit path.
    var editQuestionID: Int?

    /// A question id whose detail pane should immediately present its delete
    /// confirmation. Routed (rather than deleting inline) so the context menu and
    /// the detail view share the same confirmation step before the irreversible delete.
    var deleteQuestionID: Int?

    /// A pad id whose detail pane should immediately present its edit sheet. The
    /// pad counterpart to `editQuestionID`, set by the Pad menu command and
    /// consumed/cleared by `PadDetailView` when it appears or this value changes.
    var editPadID: String?

    /// A pad id whose detail pane should immediately present its "End Interview"
    /// confirmation. Routed (rather than ending inline) so the menu command and the
    /// detail view share the same confirmation step before the live session is ended.
    var endPadID: String?

    /// A pad id whose detail pane should immediately present its delete
    /// confirmation — the pad counterpart to `deleteQuestionID`, never deleting
    /// without that confirmation step.
    var deletePadID: String?

    /// A pad id whose detail pane should open its session playback, routed from
    /// the Pad menu's "Watch Playback" command so it honors the same in-app vs.
    /// external browser preference as the detail view's Watch button.
    var watchPlaybackPadID: String?

    /// A pad id whose detail pane should run its "Save All Code" panel, routed from
    /// the Pad menu so the menu command and the toolbar button share the same
    /// save logic (and the same knowledge of which files have loaded).
    var saveCodePadID: String?

    /// A pad id whose detail pane should toggle its favorite state, routed from the
    /// Pad menu's Favorite command — the counterpart to the detail toolbar star.
    var toggleFavoritePadID: String?

    /// A question id whose detail pane should toggle its favorite state, routed
    /// from the Question menu's Favorite command — the counterpart to the
    /// detail view's toolbar star.
    var toggleFavoriteQuestionID: Int?

    /// A pad id requested by the "Open Pad by ID" App Intent. Durable state (rather
    /// than a transient notification) so the request survives a cold launch where the
    /// intent fires before any view is listening. Consumed/cleared by ContentView.
    var openPadID: String?

    /// Switch to a section with no pending request.
    func show(_ section: AppSection) {
        self.section = section
    }

    /// Switch to Pads and queue a request for the list to apply on appear.
    func showPads(_ request: PadsRequest = PadsRequest()) {
        section = .pads
        padsRequest = request
    }

    /// Switch to Questions and queue a request for the list to apply on appear.
    func showQuestions(_ request: QuestionsRequest = QuestionsRequest()) {
        section = .questions
        questionsRequest = request
    }

    /// Switch to the list that owns `search` and apply it, routing a sidebar
    /// Suggested-search tap through the same per-pane `apply` the in-list chips use.
    func applySuggestedSearch(_ search: NamedSearch, kind: SavedSearchKind) {
        switch kind {
        case .pads: showPads(PadsRequest(applySearch: search))
        case .questions: showQuestions(QuestionsRequest(applySearch: search))
        }
    }

    /// Toggle a combined list's "Mine" preset from the sidebar, switching to that
    /// list first. Targets the opposite of `currentlyOn` - the state the caller's
    /// window last published to its `WindowNavigation` - so repeated taps flip it;
    /// the merged view consumes the request, applies it, and republishes.
    func toggleMergedMine(kind: SavedSearchKind, currentlyOn: Bool) {
        switch kind {
        case .pads: section = .pads; mergedPadsMineRequest = !currentlyOn
        case .questions: section = .questions; mergedQuestionsMineRequest = !currentlyOn
        }
    }

    /// Toggle the combined pads list's "Active" preset from the sidebar, switching to
    /// Pads first. The pad counterpart to `toggleMergedMine(kind:currentlyOn:)` -
    /// independent of "Mine", so both presets can apply together, matching the
    /// removed in-list chips.
    func toggleMergedPadsActive(currentlyOn: Bool) {
        section = .pads
        mergedPadsActiveRequest = !currentlyOn
    }

    /// Switch to a combined list's plain, unfiltered root, clearing its "Mine"
    /// preset — the merged counterpart to tapping the "Pads"/"Questions" row.
    func showMergedRoot(kind: SavedSearchKind) {
        switch kind {
        case .pads: section = .pads; mergedPadsMineRequest = false; mergedPadsActiveRequest = false
        case .questions: section = .questions; mergedQuestionsMineRequest = false
        }
    }

    /// Switch to Questions and select the favorite question with `id` once the
    /// list has it, so a sidebar favorite opens straight into its detail pane.
    func showFavoriteQuestion(id: Int) {
        showQuestions(QuestionsRequest(selectQuestionID: id))
    }

    /// Opens an account-scoped question from global entry points like Spotlight and
    /// the command palette. Question ids collide across accounts, so merged mode must
    /// carry the account with the pending favourite instead of selecting by bare id.
    @discardableResult
    @MainActor
    func showQuestion(id: Int, account: UUID) -> Bool {
        guard AccountsStore.shared.accounts.contains(where: { $0.id == account }) else { return false }

        if AccountsStore.shared.isMergedView {
            section = .questions
            selectMergedFavoriteQuestion(account: account, id: id)
        } else {
            AccountsStore.shared.currentAccountID = account
            showFavoriteQuestion(id: id)
        }
        return true
    }

    /// Switch to Pads and select the favorite pad with `id` once the list has it,
    /// so a sidebar pad favorite opens straight into its detail pane — the pad
    /// counterpart to ``showFavoriteQuestion(id:)``.
    func showFavoritePad(id: String) {
        showPads(PadsRequest(selectPadID: id))
    }

    /// Queue a pad id to open in the user's browser, consumed by ContentView.
    func openPad(id: String) {
        openPadID = id
    }

    /// Switches to the requested account (if any) and opens the Pads create sheet —
    /// the shared destination of the `coderpad://new-pad` deep link, the macOS
    /// widget/Control Center/Dock New Pad paths, and the iPad deep-link handler. An
    /// account is honoured only when it still exists; the seeded question id is only
    /// unique within its owning org, so the account switch must happen first. Lives
    /// here (pure navigation, no AppKit) so it is callable on every platform.
    @MainActor
    func routeNewPad(account: String?, seedQuestionID: Int?) {
        let route = Self.resolveNewPadRoute(
            account: account,
            seedQuestionID: seedQuestionID,
            availableAccountIDs: AccountsStore.shared.accounts.map(\.id)
        )
        if let uuid = route.accountID {
            AccountsStore.shared.showAllAccounts = false
            AccountsStore.shared.currentAccountID = uuid
        }
        showPads(PadsRequest(startCreating: true, seedQuestionID: route.seedQuestionID))
    }

    static func resolveNewPadRoute(
        account: String?,
        seedQuestionID: Int?,
        availableAccountIDs: some Collection<UUID>
    ) -> (accountID: UUID?, seedQuestionID: Int?) {
        guard let account, !account.isEmpty else {
            return (nil, seedQuestionID)
        }
        guard let uuid = UUID(uuidString: account),
              availableAccountIDs.contains(uuid) else {
            return (nil, nil)
        }

        return (uuid, seedQuestionID)
    }
}
