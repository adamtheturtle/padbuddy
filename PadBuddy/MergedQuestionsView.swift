//
//  MergedQuestionsView.swift
//  coderpad
//
//  The combined "All Accounts" questions list: every real account's questions in
//  one merged, sorted list with per-account badges. Mirrors `MergedPadsView`;
//  per-row actions and the detail pane route to the originating account through
//  `MergedRouting`. View-building members live in `+List`/`+Bars`/`+Logic`
//  extensions to keep this declaration within the `type_body_length` budget.
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

struct MergedQuestionsView: View {
    @State private var clearFiltersPublisherID = UUID()
    @State var discardedFilterNotice: String?
    @Environment(\.orgDirectory) var directory
    @Environment(\.scenePhase) var scenePhase
    /// Fade list loading/content swaps only when Reduce Motion allows it (#628).
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// While offline the app is read-only, so create/edit/delete controls disable (#321).
    @Environment(\.isReadOnly) var isReadOnly
    @Environment(\.openWindow) var openWindow
    @Environment(\.undoManager) var undoManager
    @Environment(\.windowScope) var windowScope
    /// Cross-platform Settings opener (macOS window / iPad sheet), so an auth-failure
    /// in the error bar can jump to the account editor (#622).
    @Environment(\.openAppSettings) var openSettings
    @State var accounts = AccountsStore.shared
    /// This window's merged routing and published navigation state (injected by
    /// `ContentView`), so selections and preset flags are per window (#909, #911).
    @Environment(MergedRouting.self) var router
    @Environment(WindowNavigation.self) var windowNav
    @State var cache = QuestionsCacheStore.shared
    @State var favorites = FavoriteQuestionsStore.shared
    @State var nav = AppNavigation.shared
    /// Per-account auth health, so the error bar can tell a rejected key from a
    /// transient network blip (#622).
    @State var healthMonitor = AccountHealthMonitor.shared
    /// When the fan-out refresh last finished. Kept as internal state for refresh
    /// bookkeeping, without surfacing a timestamp in the UI.
    @State var lastRefreshed: Date?
    @State var questionsByAccount: [UUID: [Question]] = [:]
    @State var limitedQuestionAccounts: Set<UUID> = []
    @State var retainedQuestionClients: [UUID: ClientTaskIdentity] = [:]
    @State var pendingRetainedQuestion: AppNavigation.MergedFavorite?
    /// Bumped on any in-place content change so the NSTableView-backed list redraws
    /// visible rows: its reload identity can't see content-only edits (#1003).
    @State var questionsRevision = 0
    @State var accountErrors: [UUID: String] = [:]
    @State var isLoading = false
    /// Monotonic reload token: results apply only while their reload is still the
    /// newest, so an older overlapping fan-out that finishes last can't roll the
    /// merged list back to stale per-account data (#1227).
    @State var reloadGeneration = 0

    @Binding var selection: Question?
    /// The primary row, keyed by the account-namespaced row id (`AccountScoped.id`)
    /// rather than the bare per-org question id, which two accounts routinely share.
    /// Derived from `selectedRowIDs` and bridged to the `Question` `selection` below.
    @State var selectedRowID: String?
    /// The List's selection. A set so several rows can be selected to copy their
    /// links at once; `selectedRowID`/`selection` track the primary within it.
    @State var selectedRowIDs: Set<String> = []
    // Per-window persisted view state. These were single global `UserDefaults`
    // keys, so two windows on All Accounts fought over one slot: selecting a
    // question, scrolling, or changing filters in one window changed what the
    // other reopened to (#2559, #2561, #2563). `@SceneStorage` is the system's
    // per-scene store, so each window keeps and restores its own — and SwiftUI
    // discards a closed window's entry rather than leaving keys behind.
    /// This window's open question, as an account-namespaced row id, with the
    /// endpoint stamp that lets a restore reject it if the account was re-pointed.
    @SceneStorage("questions.merged.selectedRow") var persistedSelectedRow = ""
    @SceneStorage("questions.merged.selectedRow.endpoint") var persistedSelectedRowEndpoint = ""
    /// This window's free-scroll position (top visible row), stamped like the above.
    @SceneStorage("questions.merged.topRow") var persistedTopRow = ""
    @SceneStorage("questions.merged.topRow.endpoint") var persistedTopRowEndpoint = ""
    /// This window's live filters, as an encoded `MergedFilterSnapshot`. A window
    /// that has none yet is seeded from the shared, cloud-synced last-used filter.
    @SceneStorage("questions.merged.liveFilter") var persistedLiveFilter = ""
    /// Separates this window's pending write from other windows that share the
    /// last-used seed key.
    @State var liveFilterPersistenceScope = UUID()
    /// Whether the saved selection has been restored this session. Gates persistence
    /// so the empty startup state never clobbers the stored row id, and keeps the
    /// restore to once, mirroring `QuestionsView`.
    @State var didRestoreSelection = false
    /// A one-shot request to scroll the restored row into view on launch; a `List`
    /// won't scroll to a programmatic selection on its own. Consumed and cleared by
    /// the `ScrollViewReader` in the list.
    @State var pendingScrollToRowID: String?
    /// Debounces free-scroll-position persistence. `FastList` reports each new top
    /// row during scroll; writing every one to `UserDefaults` makes scrolling hitch
    /// on large pad/question lists (#633).
    @State var topRowPersistence = TopRowPersistenceDebouncer()
    /// Whether the saved filters have been restored this session. Gates persistence
    /// so the empty startup state never clobbers a saved snapshot, mirroring `QuestionsView`.
    @State var didRestoreFilters = false
    /// Rows queued for a multi-row delete (carrying their source account, so each
    /// deletes against the right client), awaiting the confirmation dialog, plus the
    /// error from a failed delete. Single-row delete is delegated to the detail view.
    @State var rowsPendingBulkDelete: [MergedQuestionRow]?
    @State var pendingBulkDeleteUndo: PendingBulkDelete<MergedQuestionRow>?
    @State var bulkDeleteUndoTask: Task<Void, Never>?
    /// Progress through a committed batch, shown in place of the undo banner once the
    /// grace period is over. Before this a long batch looked like nothing was
    /// happening and could not be stopped partway (#2347).
    @State var bulkDeleteProgress: BulkDeleteProgress?
    @State var bulkDeleteError: String?
    @Binding var search: String

    @State var languageFilter: String?
    @State var ownerFilter: String?
    @State var typeFilter: String?
    @State var draftFilter: String?
    @State var updatedWindow = DateWindow()
    @State var createdWindow = DateWindow()
    @State var dateFilterClockTick = 0
    @State var accountFilter: UUID?
    @State var mineOnly = false
    @State var favoritesOnly = false
    @State var sort: QuestionSort = .lastUsedDesc
    @State var creatingForAccount: Account?

    /// Per-render memo for the combined cross-account rows (`scoped`), refreshed
    /// once at the top of `body` so its many readers (filter pass, chip options,
    /// counts, empty-state checks) share a single build, matching `MergedPadsView`.
    /// Per-render memo for the filter bar's account-derived options (#2467, #2468).
    @State var accountOptionsCache = MergedAccountOptionsCache()
    @State var scopedCache = ScopedQuestionsCache()
    /// Per-render memo for the filtered + sorted rows (`sorted`), so the list,
    /// overlay, and count bar share one filter+sort pass instead of redoing it on
    /// every read — the hitch the pads view was already rewritten to avoid.
    @State var sortedCache = SortedQuestionsCache()

    init(selection: Binding<Question?>, search: Binding<String>) {
        _selection = selection
        _search = search

        let cache = QuestionsCacheStore.shared
        MergedListWindows.prepareQuestions()
        let limit = MergedListWindows.questions.recordsPerAccount
        var seeded: [UUID: [Question]] = [:]
        var limited: Set<UUID> = []
        var clients: [UUID: ClientTaskIdentity] = [:]
        for account in AccountsStore.shared.mergeableAccounts {
            guard clients[account.id] == nil else { continue }

            let client = account.makeClient()
            clients[account.id] = client.taskIdentity
            if let window = MergedListWindows.questions.cached(account.id, via: client) {
                seeded[account.id] = window.values
                if !window.isComplete {
                    limited.insert(account.id)
                }
                continue
            }
            let questions = cache.get(account.id)
            if !questions.isEmpty {
                seeded[account.id] = questions.count <= limit ? questions : Array(questions.prefix(limit))
                if !RetainedListStream.isComplete(questions.count) || questions.count > limit {
                    limited.insert(account.id)
                }
            }
        }
        _questionsByAccount = State(initialValue: seeded)
        _limitedQuestionAccounts = State(initialValue: limited)
        _retainedQuestionClients = State(initialValue: clients)
    }

    var body: some View {
        // Recompute the combined rows and the filtered+sorted rows once per render;
        // every read below hits the memos.
        accountOptionsCache.refresh(accounts.accounts, mergeable: accounts.mergeableAccounts)
        refreshScoped()
        refreshSorted()
        return decorated
            .task(id: dateFilterClockActive) { await runDateFilterClock() }
            .focusedSceneValue(\.questionSortSelection, $sort)
            .focusedSceneValue(\.clearFiltersAction, ClearFiltersAction(
                id: "merged-questions", publisherID: clearFiltersPublisherID,
                perform: clearAllFilters
            ))
    }
}

/// A merged-list question row with both the full source account (for actions,
/// routing, and URLs) and the small account badge value the row renders. Building
/// `RowAccount` once when the scoped cache changes keeps scroll-time cell hosting
/// from reparsing avatar tint/color data for every visible row.
struct MergedQuestionRow: Identifiable, Hashable {
    let account: Account
    let rowAccount: RowAccount
    let item: Question
    let presentation: QuestionRowPresentation
    let id: String

    init(account: Account, item: Question) {
        self.account = account
        rowAccount = RowAccount(account)
        self.item = item
        presentation = QuestionRowPresentation(question: item, account: rowAccount)
        id = MergedQuestionsView.rowID(account: account.id, question: item.id)
    }
}

/// Memo holding the merged questions list's combined rows and chip-option lists,
/// rebuilt only when the merged questions change (keyed by `signature`), so the
/// tagged-array build and the option Sets no longer rerun on every render (#366).
final class ScopedQuestionsCache {
    var rows: [MergedQuestionRow] = [] {
        didSet {
            rowOffsets = [:]
            for (offset, row) in rows.enumerated() where rowOffsets[row.id] == nil {
                rowOffsets[row.id] = offset
            }
        }
    }

    /// Offsets reference the canonical sorted array without retaining model copies.
    private var rowOffsets: [String: Int] = [:]

    func row(forID id: String) -> MergedQuestionRow? {
        guard let offset = rowOffsets[id] else { return nil }

        return rows[offset]
    }

    var availableLanguages: [String] = []
    var availableOwners: [String] = []
    /// The hash of the inputs the cached values were built from; `nil` until the
    /// first build. `refreshScoped()` skips the rebuild while this is unchanged.
    var signature: Int?
}

/// Memo holding the merged questions list's filtered + sorted rows for one render,
/// plus each account's favorite question ids so per-row `isFavorite` checks are
/// O(1) and allocation-free (#367).
final class SortedQuestionsCache {
    var rows: [MergedQuestionRow] = []
    var favoritesByAccount: [UUID: Set<Int>] = [:]
    /// The inputs the cached rows were filtered+sorted for. A row click re-runs `body`
    /// several times via the selection cascade, and only the selection differs across
    /// those passes — so when this key is unchanged `refreshSorted()` reuses the cached
    /// rows instead of re-running the O(n) cross-account filter and sort each time, the
    /// merged-questions counterpart of the single-account fix in #395.
    var key: Key?

    struct Key: Equatable {
        /// Signature of the memoized `scoped` rows this ran over, so a real data change
        /// (handled by `refreshScoped()`) invalidates the filter+sort too.
        let scopedSignature: Int
        let filterSignature: FilterSignature
        let favoritesOnly: Bool
        /// Favorites drive both the favorites filter and each row's star, so a toggle
        /// must re-run. `FavoriteQuestionsStore.revision` moves on every change, so
        /// comparing it replaces rebuilding a Set per account each pass (#2084).
        let favoritesRevision: Int
    }
}
