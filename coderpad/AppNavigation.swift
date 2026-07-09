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
    /// A saved search to apply wholesale when the pane appears. Carries the full
    /// filter set so picking a saved search from the sidebar reproduces exactly
    /// what saving it captured — the same as tapping its in-pane chip.
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
    /// A saved search to apply wholesale when the pane appears (see `PadsRequest`).
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

    /// The campaign selected in the Screen section's middle column. Selecting one drives
    /// the detail column's test-sessions list (#448). Kept here rather than as a
    /// `MainSplit` binding so it needs no threading through the shared split columns;
    /// the campaigns list owns it and the detail column observes it.
    var screenCampaignSelection: ScreenCampaign?

    /// The selected campaign's candidate-count subtitle (e.g. "12 candidates"), published
    /// by the tests list (which lives in the detail column, #448). The campaigns column
    /// reports it as the window subtitle while a campaign is selected, since the detail
    /// column's own count preference doesn't propagate out to the toolbar (#475).
    var screenTestsSubtitle = ""

    /// The visible list section's result-count summary (e.g. "12 pads"), published by
    /// the active list pane via ``publishSectionCount(_:)`` and shown by `MainSplit` as
    /// the window's toolbar subtitle beneath the section title. Replaces the former
    /// `SectionCountKey` SwiftUI preference, which SwiftUICore faulted on ("tried to
    /// update multiple times per frame"): a list's count can change across the several
    /// `body` passes that settle one frame, and the preference wrote each intermediate
    /// value straight into the tree. Routing it through the guarded ``publishSectionCount(_:)``
    /// (an `onChange` side effect, which fires once per settled value) keeps that safety
    /// without a preference.
    var sectionCountSubtitle = ""

    /// The section ``sectionCountSubtitle`` was published for, so `MainSplit` can ignore a
    /// count left over from the section just navigated away from — otherwise that stale
    /// count would linger under the new title until the new pane republishes its own,
    /// which lands a frame later and reads as a flash (the old title's count, then the
    /// new one). Set alongside the subtitle by ``publishSectionCount(_:)``.
    var sectionCountSection: AppSection?

    /// The live filter signature of each list, republished by its pane whenever its
    /// filters change (and on appear). The sidebar compares these against the
    /// suggested and saved rows to highlight whichever search is currently applied,
    /// falling back to the plain "Pads"/"Questions" row when nothing matches. Kept
    /// here rather than inferred from `padsRequest`/`questionsRequest` because those
    /// are transient one-shot requests, while this must track every in-pane filter
    /// edit (a chip toggle, a menu change) so the sidebar highlight never lies about
    /// what's on screen. Compared by filter fields only; `name`/`id` are ignored.
    var padsFilter = NamedSearch(name: "")
    var questionsFilter = NamedSearch(name: "")

    /// The live "Mine" preset state of each combined ("All Accounts") list,
    /// republished by `MergedPadsView`/`MergedQuestionsView` so the sidebar can
    /// honestly highlight its "My Pads"/"My Questions" rows in merged mode. The
    /// combined views own their filters locally rather than through
    /// `padsFilter`/`padsRequest` (their "Mine" is per-account ownership, not a
    /// single owner email), so a one-shot `…Request` lets the sidebar set the
    /// preset; the view consumes and clears it, then republishes the result here.
    /// Mirrors the padsFilter/padsRequest split the single-account panes use.
    var mergedPadsMineOnly = false
    var mergedPadsMineRequest: Bool?
    var mergedQuestionsMineOnly = false
    var mergedQuestionsMineRequest: Bool?

    /// A question id whose detail pane should immediately create a pad and open it
    /// inline (the in-pane browser), matching the detail view's "New Pad" button.
    /// Set by the Questions list's context menu (after selecting that question) and
    /// consumed/cleared by QuestionDetailView when it appears or this value changes.
    var createPadForQuestionID: Int?

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

    /// A pad id whose detail pane should run its "Save Code" panel, routed from
    /// the Pad menu so the menu command and the toolbar button share the same
    /// save logic (and the same knowledge of which files have loaded).
    var saveCodePadID: String?

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

    /// Publish the active list section's result-count subtitle, tagged with the current
    /// section so `MainSplit` can tell it apart from a stale count. Called as an
    /// `onChange` side effect (see `reportsSectionCount`), which already fires once per
    /// settled value, so the set is synchronous: deferring it to the next runloop is
    /// what left the toolbar blank for a frame when switching sections (the new pane's
    /// count arrived after the section change had already cleared the old one).
    func publishSectionCount(_ subtitle: String) {
        guard sectionCountSubtitle != subtitle || sectionCountSection != section else { return }

        sectionCountSubtitle = subtitle
        sectionCountSection = section
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
    /// saved-search tap through the same per-pane `apply` the in-list chips use.
    func applySavedSearch(_ search: NamedSearch, kind: SavedSearchKind) {
        switch kind {
        case .pads: showPads(PadsRequest(applySearch: search))
        case .questions: showQuestions(QuestionsRequest(applySearch: search))
        }
    }

    /// Toggle a combined list's "Mine" preset from the sidebar, switching to that
    /// list first. Targets the opposite of the last-published state so repeated taps
    /// flip it; the merged view consumes the request, applies it, and republishes.
    func toggleMergedMine(kind: SavedSearchKind) {
        switch kind {
        case .pads: section = .pads; mergedPadsMineRequest = !mergedPadsMineOnly
        case .questions: section = .questions; mergedQuestionsMineRequest = !mergedQuestionsMineOnly
        }
    }

    /// Switch to a combined list's plain, unfiltered root, clearing its "Mine"
    /// preset — the merged counterpart to tapping the "Pads"/"Questions" row.
    func showMergedRoot(kind: SavedSearchKind) {
        switch kind {
        case .pads: section = .pads; mergedPadsMineRequest = false
        case .questions: section = .questions; mergedQuestionsMineRequest = false
        }
    }

    /// Switch to Questions and select the favorite question with `id` once the
    /// list has it, so a sidebar favorite opens straight into its detail pane.
    func showFavoriteQuestion(id: Int) {
        showQuestions(QuestionsRequest(selectQuestionID: id))
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
        if let account, let uuid = UUID(uuidString: account),
           AccountsStore.shared.accounts.contains(where: { $0.id == uuid }) {
            AccountsStore.shared.showAllAccounts = false
            AccountsStore.shared.currentAccountID = uuid
        }
        showPads(PadsRequest(startCreating: true, seedQuestionID: seedQuestionID))
    }
}
