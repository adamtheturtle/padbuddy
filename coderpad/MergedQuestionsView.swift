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
    @Environment(\.orgDirectory) var directory
    @Environment(\.scenePhase) var scenePhase
    /// Fade list loading/content swaps only when Reduce Motion allows it (#628).
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// While offline the app is read-only, so create/edit/delete controls disable (#321).
    @Environment(\.isReadOnly) var isReadOnly
    @Environment(\.openWindow) var openWindow
    @Environment(\.undoManager) var undoManager
    /// Cross-platform Settings opener (macOS window / iPad sheet), so an auth-failure
    /// in the error bar can jump to the account editor (#622).
    @Environment(\.openAppSettings) var openSettings
    @State var accounts = AccountsStore.shared
    @State var router = MergedRouting.shared
    @State var cache = QuestionsCacheStore.shared
    @State var favorites = FavoriteQuestionsStore.shared
    @State var nav = AppNavigation.shared
    /// Per-account auth health, so the error bar can tell a rejected key from a
    /// transient network blip (#622).
    @State var healthMonitor = AccountHealthMonitor.shared
    /// When the fan-out refresh last finished, surfaced as "Updated X ago" so the
    /// cached-then-refreshed data reads as trustworthy rather than possibly stale (#619).
    @State var lastRefreshed: Date?
    @State var questionsByAccount: [UUID: [Question]] = [:]
    @State var accountErrors: [UUID: String] = [:]
    @State var isLoading = false

    @Binding var selection: Question?
    /// The primary row, keyed by the account-namespaced row id (`AccountScoped.id`)
    /// rather than the bare per-org question id, which two accounts routinely share.
    /// Derived from `selectedRowIDs` and bridged to the `Question` `selection` below.
    @State var selectedRowID: String?
    /// The List's selection. A set so several rows can be selected to copy their
    /// links at once; `selectedRowID`/`selection` track the primary within it.
    @State var selectedRowIDs: Set<String> = []
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
    @State var bulkDeleteError: String?
    @Binding var search: String

    @State var languageFilter: String?
    @State var ownerFilter: String?
    @State var typeFilter: String?
    @State var draftFilter: String?
    @State var accountFilter: UUID?
    @State var mineOnly = false
    @State var favoritesOnly = false
    @AppStorage(QuestionSort.storageKey) var sort: QuestionSort = .lastUsedDesc
    @State var creatingForAccount: Account?

    /// Per-render memo for the combined cross-account rows (`scoped`), refreshed
    /// once at the top of `body` so its many readers (filter pass, chip options,
    /// counts, empty-state checks) share a single build, matching `MergedPadsView`.
    @State var scopedCache = ScopedQuestionsCache()
    /// Per-render memo for the filtered + sorted rows (`sorted`), so the list,
    /// overlay, and count bar share one filter+sort pass instead of redoing it on
    /// every read — the hitch the pads view was already rewritten to avoid.
    @State var sortedCache = SortedQuestionsCache()

    var body: some View {
        // Recompute the combined rows and the filtered+sorted rows once per render;
        // every read below hits the memos.
        refreshScoped()
        refreshSorted()
        return decorated
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
    let id: String

    init(account: Account, item: Question) {
        self.account = account
        rowAccount = RowAccount(account)
        self.item = item
        id = MergedQuestionsView.rowID(account: account.id, question: item.id)
    }
}

/// Memo holding the merged questions list's combined rows and chip-option lists,
/// rebuilt only when the merged questions change (keyed by `signature`), so the
/// tagged-array build and the option Sets no longer rerun on every render (#366).
final class ScopedQuestionsCache {
    var rows: [MergedQuestionRow] = []
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
        let filterSignature: String
        let favoritesOnly: Bool
        /// Favorites drive both the favorites filter and each row's star, so a toggle
        /// must re-run; comparing the small id sets is cheap and exact.
        let favoritesByAccount: [UUID: Set<Int>]
    }
}
