//
//  AppNavigation.swift
//  coderpad
//

// swiftlint:disable file_length

import Foundation

/// The account context in which a process-wide list request was created. A pane
/// consumes the request only while it still represents this exact context, so a
/// delayed search/create action cannot cross an account-mode switch (#1104).
enum NavigationAccountScope: Equatable {
    case account(UUID)
    case allAccounts

    @MainActor
    static var current: Self? {
        let accounts = AccountsStore.shared
        if accounts.showAllAccounts {
            return .allAccounts
        }
        return accounts.currentAccountID.map(Self.account)
    }

    @MainActor
    var isCurrent: Bool {
        self == Self.current
    }
}

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
    /// The direct-create failure that caused this fallback sheet to open.
    var createError: String?
    /// A search to apply wholesale when the pane appears. Carries the full filter
    /// set so picking a Suggested search from the sidebar reproduces exactly what it
    /// captured — the same as tapping its in-pane chip.
    var applySearch: NamedSearch?
    /// A favorite pad to select when the pane appears, addressed by id since the
    /// sidebar that routes it holds favorite ids, not the loaded `Pad`s (mirrors
    /// `QuestionsRequest.selectQuestionID`).
    var selectPadID: String?
    /// The account that owns `selectPadID`, when the requester knows it. Pad slugs
    /// collide across custom servers, and a queued request can outlive further
    /// account or view switches before the Pads pane consumes it, so a bare id
    /// must not be resolved under a different account (#1255). Nil for legacy
    /// id-only requesters, which keep the old id-only matching.
    var selectPadAccountID: UUID?
    /// Credential generation captured by global cached-result actions. When set,
    /// consumers discard the selection if the account was removed or re-keyed.
    var selectPadClientIdentity: ClientTaskIdentity?
    /// Captured by `showPads` when the request enters the global mailbox.
    var accountScope: NavigationAccountScope?
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
    var selectQuestionAccountID: UUID?
    var selectQuestionClientIdentity: ClientTaskIdentity?
    /// Captured by `showQuestions` when the request enters the global mailbox.
    var accountScope: NavigationAccountScope?
}

struct OpenPadNavigationRequest: Equatable {
    let id: String
    let accountID: UUID?
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

    /// A pending section switch, consumed (and cleared) by the focused window,
    /// which applies it to its own `WindowNavigation.section`. A request rather
    /// than live state: the visible section itself is per window (#907), so a
    /// process-wide value here would retarget every open window at once.
    var sectionRequest: AppSection?

    /// A pending Go > Next/Previous Section step, resolved by the focused window
    /// against its *own* current section. Carries a token so repeated identical
    /// steps still read as changes.
    var sectionCycleRequest: SectionCycleRequest?

    struct SectionCycleRequest: Equatable {
        let delta: Int
        let token: UUID
    }

    /// Moves the focused window's section forward (`+1`) or back (`-1`) through
    /// the navigable section order, wrapping at the ends. Backs the Go menu's
    /// Next/Previous items on both platforms.
    func cycleSection(by delta: Int) {
        sectionCycleRequest = SectionCycleRequest(delta: delta, token: UUID())
    }

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
        var clientIdentity: ClientTaskIdentity?
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
        var clientIdentity: ClientTaskIdentity?
    }

    func selectMergedFavoriteQuestion(
        account: UUID, id: Int, clientIdentity: ClientTaskIdentity? = nil
    ) {
        pendingMergedFavoriteQuestion = MergedFavorite(
            account: account, id: id, clientIdentity: clientIdentity
        )
    }

    func selectMergedFavoritePad(account: UUID, id: String, clientIdentity: ClientTaskIdentity? = nil) {
        pendingMergedFavoritePad = MergedFavoritePad(
            account: account, id: id, clientIdentity: clientIdentity
        )
    }

    /// A pad-detail command target: the slug plus its owning account when the
    /// requester knows it. Slugs collide across custom servers and every iPad
    /// scene attempts consumption, so a bare slug could hand a command to another
    /// account's same-slug detail (#1820, #1821, #1822, #1823, #1824). A nil
    /// account keeps the old id-only matching for legacy requesters.
    struct PadCommandTarget: Equatable {
        let id: String
        var account: UUID?
        /// The backend this command was queued against, captured at creation.
        ///
        /// `PadsRequest` and `QuestionsRequest` already carry one, documented as "consumers
        /// discard the selection if the account was removed or re-keyed". The command
        /// targets did not — and they back the destructive commands, so a queued Delete Pad
        /// or End Interview survived the account being re-keyed or pointed at a different
        /// server and was applied against the new backend under the same slug (#4774).
        var clientIdentity: ClientTaskIdentity?

        @MainActor
        init(id: String, account: UUID?) {
            self.id = id
            self.account = account
            clientIdentity = AppNavigation.currentIdentity(of: account)
        }
    }

    /// The question counterpart: per-org ids collide across accounts
    /// (#1816, #1817, #1818, #1819).
    struct QuestionCommandTarget: Equatable {
        let id: Int
        var account: UUID?
        /// As for ``PadCommandTarget`` (#4774).
        var clientIdentity: ClientTaskIdentity?

        @MainActor
        init(id: Int, account: UUID?) {
            self.id = id
            self.account = account
            clientIdentity = AppNavigation.currentIdentity(of: account)
        }
    }

    /// The client identity an account currently resolves to, or nil when it names no
    /// account (a command queued without one applies to whatever the pane is showing).
    @MainActor
    static func currentIdentity(of account: UUID?) -> ClientTaskIdentity? {
        guard let account else { return nil }

        return AccountsStore.shared.accounts.first { $0.id == account }?.makeClient().taskIdentity
    }

    /// A question whose detail pane should immediately create a pad and open it
    /// inline (the in-pane browser), matching the detail view's "New Pad" button.
    /// Set by the Questions list's context menu (after selecting that question) and
    /// consumed/cleared by QuestionDetailView when it appears or this value changes.
    var createPadForQuestionID: QuestionCommandTarget?

    /// A question whose detail pane should immediately open title editing,
    /// matching the detail view's inline rename affordance and the Pad menu's
    /// command-driven edit path.
    var editQuestionID: QuestionCommandTarget?

    /// A question id whose detail pane should immediately present its delete
    /// confirmation. Routed (rather than deleting inline) so the context menu and
    /// the detail view share the same confirmation step before the irreversible delete.
    var deleteQuestionID: QuestionCommandTarget?

    /// A pad whose detail pane should immediately present its edit sheet. The
    /// pad counterpart to `editQuestionID`, set by the Pad menu command and
    /// consumed/cleared by `PadDetailView` when it appears or this value changes.
    var editPadID: PadCommandTarget?

    /// A pad id whose detail pane should immediately present its "End Interview"
    /// confirmation. Routed (rather than ending inline) so the menu command and the
    /// detail view share the same confirmation step before the live session is ended.
    var endPadID: PadCommandTarget?

    /// A pad id whose detail pane should immediately present its delete
    /// confirmation — the pad counterpart to `deleteQuestionID`, never deleting
    /// without that confirmation step.
    var deletePadID: PadCommandTarget?

    /// A pad id whose detail pane should open its session playback, routed from
    /// external browser preference as the detail view's Watch button.
    var watchPlaybackPadID: PadCommandTarget?

    /// A pad id whose detail pane should run its "Save All Code" panel, routed from
    /// the Pad menu so the menu command and the toolbar button share the same
    /// save logic (and the same knowledge of which files have loaded).
    var saveCodePadID: PadCommandTarget?

    /// A pad id whose detail pane should toggle its favorite state, routed from the
    /// Pad menu's Favorite command — the counterpart to the detail toolbar star.
    var toggleFavoritePadID: PadCommandTarget?

    /// A question id whose detail pane should toggle its favorite state, routed
    /// from the Question menu's Favorite command — the counterpart to the
    /// detail view's toolbar star.
    var toggleFavoriteQuestionID: QuestionCommandTarget?

    /// A pad id requested by the "Open Pad by ID" App Intent. Durable state (rather
    /// than a transient notification) so the request survives a cold launch where the
    /// intent fires before any view is listening. Consumed/cleared by ContentView.
    var openPadRequest: OpenPadNavigationRequest?
    var unsupportedDeepLink: URL?
    /// A localized explanation when an external browser handoff fails, claimed by the
    /// focused window like other mailbox requests (#4664).
    var browserOpenFailure: String?

    /// Switch to a section with no pending request. Any list request still
    /// awaiting consumption is dropped: a plain section switch supersedes it, and
    /// a request left queued would otherwise ambush the *next* visit to that pane
    /// — mounting Pads days later and finding an old search applied or the create
    /// sheet opening on its own (#2050). Only requests reach panes, so a plain
    /// switch must leave the mailbox empty.
    func show(_ section: AppSection) {
        clearPendingRequests()
        sectionRequest = section
    }

    /// Empties the whole mailbox.
    ///
    /// Only two of its fields used to be cleared, for the reason that applies to all of
    /// them: "a request left queued would otherwise ambush the *next* visit to that pane —
    /// mounting Pads days later and finding an old search applied or the create sheet
    /// opening on its own (#2050)". The command targets are worse than a stale search:
    /// choosing Delete Pad and then switching section left `deletePadID` queued, and the
    /// next time that pad's detail view appeared it presented a delete confirmation the
    /// user had not asked for (#4773).
    func clearPendingRequests() {
        padsRequest = nil
        questionsRequest = nil
        mergedPadsMineRequest = nil
        mergedQuestionsMineRequest = nil
        mergedPadsActiveRequest = nil
        pendingMergedFavoritePad = nil
        pendingMergedFavoriteQuestion = nil
        editPadID = nil
        endPadID = nil
        deletePadID = nil
        watchPlaybackPadID = nil
        saveCodePadID = nil
        toggleFavoritePadID = nil
        createPadForQuestionID = nil
        editQuestionID = nil
        deleteQuestionID = nil
        toggleFavoriteQuestionID = nil
    }

    /// Switch to Pads and queue a request for the list to apply on appear. An
    /// incoming request merges over one still awaiting consumption — each field
    /// the newcomer sets wins, fields it leaves default keep the pending value —
    /// so two rapid navigation actions arriving before the pane mounts no longer
    /// silently discard the first (#1814).
    func showPads(_ request: PadsRequest = PadsRequest()) {
        sectionRequest = .pads
        var scoped = request
        scoped.accountScope = .current
        padsRequest = Self.merged(pending: padsRequest, incoming: scoped)
    }

    /// Switch to Questions and queue a request for the list to apply on appear;
    /// merges like ``showPads(_:)`` (#1815).
    func showQuestions(_ request: QuestionsRequest = QuestionsRequest()) {
        sectionRequest = .questions
        var scoped = request
        scoped.accountScope = .current
        questionsRequest = Self.merged(pending: questionsRequest, incoming: scoped)
    }

    static func merged(pending: PadsRequest?, incoming: PadsRequest) -> PadsRequest {
        guard let pending else { return incoming }
        guard pending.accountScope == incoming.accountScope else { return incoming }

        var merged = pending
        if incoming.ownerEmail != nil {
            merged.ownerEmail = incoming.ownerEmail
        }
        if incoming.search != nil {
            merged.search = incoming.search
        }
        if incoming.applySearch != nil {
            merged.applySearch = incoming.applySearch
        }
        if incoming.startCreating {
            merged.startCreating = true
            merged.seedQuestionID = incoming.seedQuestionID
            merged.createError = incoming.createError
        }
        if incoming.selectPadID != nil {
            merged.selectPadID = incoming.selectPadID
            merged.selectPadAccountID = incoming.selectPadAccountID
            merged.selectPadClientIdentity = incoming.selectPadClientIdentity
        }
        return merged
    }

    static func merged(pending: QuestionsRequest?, incoming: QuestionsRequest) -> QuestionsRequest {
        guard let pending else { return incoming }
        guard pending.accountScope == incoming.accountScope else { return incoming }

        var merged = pending
        if incoming.search != nil {
            merged.search = incoming.search
        }
        if incoming.applySearch != nil {
            merged.applySearch = incoming.applySearch
        }
        if incoming.startCreating {
            merged.startCreating = true
        }
        if incoming.selectQuestionID != nil {
            merged.selectQuestionID = incoming.selectQuestionID
            merged.selectQuestionAccountID = incoming.selectQuestionAccountID
            merged.selectQuestionClientIdentity = incoming.selectQuestionClientIdentity
        }
        return merged
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
        // Cleared first, as `show(_:)` does: this is a section switch too, and a queued
        // command target left behind here ambushes the pane it lands on (#4773).
        clearPendingRequests()
        switch kind {
        case .pads: sectionRequest = .pads; mergedPadsMineRequest = !currentlyOn
        case .questions: sectionRequest = .questions; mergedQuestionsMineRequest = !currentlyOn
        }
    }

    /// Toggle the combined pads list's "Active" preset from the sidebar, switching to
    /// Pads first. The pad counterpart to `toggleMergedMine(kind:currentlyOn:)` -
    /// independent of "Mine", so both presets can apply together, matching the
    /// removed in-list chips.
    func toggleMergedPadsActive(currentlyOn: Bool) {
        clearPendingRequests()
        sectionRequest = .pads
        mergedPadsActiveRequest = !currentlyOn
    }

    /// Switch to a combined list's plain, unfiltered root — the merged counterpart
    /// to tapping the "Pads"/"Questions" row. Clears the "Mine"/"Active" presets and
    /// queues an empty wholesale search so the merged view also resets its search
    /// text and every filter, exactly as the single-account root row does; the
    /// presets alone left a lingering search/language/owner filter applied (#1001).
    /// Clears the merged list back to an unfiltered root before applying `preset`.
    ///
    /// `preset` is applied *after* the reset, so a shortcut that wants "active pads"
    /// gets exactly that rather than active-pads-intersected-with-whatever-was-left
    /// on screen (#2358).
    func showMergedRoot(kind: SavedSearchKind, activeOnly: Bool = false) {
        switch kind {
        case .pads:
            sectionRequest = .pads
            pendingMergedFavoritePad = nil
            mergedPadsMineRequest = false
            mergedPadsActiveRequest = activeOnly
            padsRequest = PadsRequest(
                applySearch: NamedSearch(name: ""), accountScope: .allAccounts
            )

        case .questions:
            sectionRequest = .questions
            pendingMergedFavoriteQuestion = nil
            mergedQuestionsMineRequest = false
            questionsRequest = QuestionsRequest(
                applySearch: NamedSearch(name: ""), accountScope: .allAccounts
            )
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
    func showQuestion(
        id: Int, account: UUID, clientIdentity: ClientTaskIdentity? = nil
    ) -> Bool {
        guard let target = AccountsStore.shared.accounts.first(where: { $0.id == account }),
              clientIdentity == nil || clientIdentity == target.makeClient().taskIdentity else { return false }

        if AccountsStore.shared.isMergedView {
            sectionRequest = .questions
            selectMergedFavoriteQuestion(account: account, id: id, clientIdentity: clientIdentity)
        } else {
            AccountsStore.shared.currentAccountID = account
            showQuestions(QuestionsRequest(
                selectQuestionID: id,
                selectQuestionAccountID: account,
                selectQuestionClientIdentity: clientIdentity
            ))
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
    /// `account` names the owning account when the requester knows it (#759).
    func openPad(id: String, account: UUID? = nil) {
        openPadRequest = OpenPadNavigationRequest(id: id, accountID: account)
    }

    /// Atomically takes the pending request and clears every part of its scope.
    func takeOpenPadRequest() -> OpenPadNavigationRequest? {
        defer { openPadRequest = nil }
        return openPadRequest
    }
}

/// Whether a queued command still refers to the backend it was created against.
///
/// An account that has been removed, re-keyed, or pointed at a different server no longer
/// resolves to the captured identity, and applying a destructive command under the same
/// slug against a different backend is the hazard the request types' `clientIdentity`
/// fields exist for (#4774).
@MainActor
func commandTargetIsCurrent(account: UUID?, clientIdentity: ClientTaskIdentity?) -> Bool {
    guard let clientIdentity else { return true }

    return AppNavigation.currentIdentity(of: account) == clientIdentity
}
