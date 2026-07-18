//
//  MergedPadsView.swift
//  coderpad
//
//  The combined "All Accounts" pads list. Fans out across every real account,
//  tags each pad with its source account, and presents one merged, sorted list.
//  Per-row actions and the detail pane route back to the originating account's
//  client via `MergedRouting`. The heavily-engineered single-account `PadsView` is
//  left untouched; this is a parallel, merge-aware list that reuses the same filter
//  predicate (`PadListLogic.matches`), row (`PadRow`), and chip components.
//
//  The view-building members live in `MergedPadsView+List`/`+Bars`/`+Logic`
//  extensions so this primary declaration stays small (the project lints
//  `type_body_length` under `--strict`).
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

struct MergedPadsView: View {
    @Environment(\.orgDirectory) var directory
    @Environment(\.scenePhase) var scenePhase
    /// Fade list loading/content swaps only when Reduce Motion allows it (#628).
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// While offline the app is read-only, so create/delete controls disable (#321).
    @Environment(\.isReadOnly) var isReadOnly
    @Environment(\.openWindow) var openWindow
    @Environment(\.undoManager) var undoManager
    /// Cross-platform Settings opener (macOS window / iPad sheet), so an auth-failure
    /// in the error bar can jump to the account editor (#622).
    @Environment(\.openAppSettings) var openSettings
    @State var accounts = AccountsStore.shared
    /// This window's merged routing and published navigation state (injected by
    /// `ContentView`), so selections and preset flags are per window (#888, #909).
    @Environment(MergedRouting.self) var router
    @Environment(WindowNavigation.self) var windowNav
    @State var nav = AppNavigation.shared
    @State var cache = PadsCacheStore.shared
    @State var openedStore = PadOpenedStore.shared
    @State var favoritePads = FavoritePadsStore.shared
    /// Per-account auth health, so the error bar can tell a rejected key from a
    /// transient network blip (#622).
    @State var healthMonitor = AccountHealthMonitor.shared
    /// When the fan-out refresh last finished, surfaced as "Updated X ago" so the
    /// cached-then-refreshed data reads as trustworthy rather than possibly stale (#619).
    @State var lastRefreshed: Date?
    /// The latest pads per account. Seeded from each account's disk cache on appear
    /// for an instant list, then replaced as the live fan-out fetch lands.
    @State var padsByAccount: [UUID: [Pad]] = [:]
    /// The most recent fetch error per account, so one account failing surfaces a
    /// quiet note without blanking the pads the other accounts returned.
    @State var accountErrors: [UUID: String] = [:]
    @State var isLoading = false
    /// Monotonic reload token: results apply only while their reload is still the
    /// newest, so an older overlapping fan-out that finishes last can't roll the
    /// merged list back to stale per-account data (#1226).
    @State var reloadGeneration = 0

    @Binding var selection: Pad?
    /// The row whose detail is shown: the "primary" of the multi-selection, derived
    /// from `selectedIDs` (see `MultiSelectLogic.primaryID`). Stays the single source
    /// for the detail pane, command target, and per-row bridging. Holds the
    /// account-namespaced row id (`rowID(account:pad:)`), not the bare slug: pad
    /// slugs are only unique per server, so two custom servers can collide (#758).
    @State var selectedID: String?
    /// The List's selection, keyed by namespaced row id like `selectedID`. A set so
    /// several rows can be selected for a bulk action (Copy links, Delete);
    /// `selectedID`/`selection` track the primary within it.
    @State var selectedIDs: Set<String> = []
    /// Whether the saved selection has been restored this session. Gates persistence
    /// so the empty startup state never clobbers the stored id, and keeps the restore
    /// to once, mirroring `PadsView`.
    @State var didRestoreSelection = false
    /// Set while the launch restore reselects the saved row, so that reselection
    /// isn't marked "opened" - which would clear the pad's "new activity" dot
    /// before the user ever saw it (#1043). Consumed once, mirroring `PadsView`.
    @State var isRestoringSelection = false
    /// A one-shot request to scroll the restored row into view on launch; a `List`
    /// won't scroll to a programmatic selection on its own. Consumed and cleared by
    /// the `ScrollViewReader` in the list.
    @State var pendingScrollToID: String?
    /// Debounces free-scroll-position persistence. `FastList` reports each new top
    /// row during scroll; writing every one to `UserDefaults` makes scrolling hitch
    /// on large pad/question lists (#633).
    @State var topRowPersistence = TopRowPersistenceDebouncer()
    /// Whether the saved filters have been restored this session. Gates persistence
    /// so the empty startup state never clobbers a saved snapshot, mirroring `PadsView`.
    @State var didRestoreFilters = false
    /// The rows queued for a multi-row delete, awaiting the confirmation dialog.
    /// Account-scoped rows rather than bare `Pad`s so each delete routes to its own
    /// account's client (#758). Separate from `padPendingDelete` (the single
    /// swipe/context delete) so the two confirmations don't interfere.
    @State var padsPendingBulkDelete: [AccountScoped<Account, Pad>]?
    @State var pendingBulkDeleteUndo: PendingBulkDelete<AccountScoped<Account, Pad>>?
    @State var bulkDeleteUndoTask: Task<Void, Never>?
    @Binding var search: String

    @State var stateFilter: PadState?
    @State var languageFilter: String?
    @State var ownerFilter: String?
    @State var typeFilter: String?
    /// Restrict to a single source account. `nil` shows every account.
    @State var accountFilter: UUID?
    /// Restrict to pads owned by each account's own user. Cross-account "mine",
    /// resolved per source account (ownership is account scoped).
    @State var mineOnly = false
    @State var updatedWindow = DateWindow()
    @State var createdWindow = DateWindow()
    /// Ticks while a date filter is active so rolling windows such as Today and Last
    /// 24 hours re-filter even if no account's pad cache changes.
    @State var dateFilterClockTick = 0

    /// The row awaiting the single-delete confirmation. Account-scoped so the
    /// delete routes to the row's own account, never a slug-matched guess (#758).
    @State var padPendingDelete: AccountScoped<Account, Pad>?
    @State var deleteError: String?
    /// A bare pad slug from a process-wide request (e.g. the command palette in
    /// merged mode) whose row hadn't loaded when the request was consumed. Selection
    /// is keyed by account-namespaced row id (#758), so the slug is parked here and
    /// resolved by `resolvePendingSlugSelection()` once a matching row appears.
    @State var pendingSelectPadSlug: String?
    /// Debounces marking a pad "opened" until the selection settles, so arrowing
    /// through the merged list doesn't rebuild it on every transient row (see the
    /// single-account `PadsView` for the rationale).
    @State var markOpenedTask: Task<Void, Never>?
    /// The account a New Pad is being created for, chosen from the toolbar menu
    /// since creation is inherently single-account.
    @State var creatingForAccount: Account?
    /// A favourite question to seed the create sheet with, carried by a New Pad
    /// request (e.g. the widget/Dock/Control Center deep link) consumed in merged
    /// mode. Cleared alongside `creatingForAccount` when the sheet closes.
    @State var creatingSeedQuestionID: Int?
    /// The active sort, shared with the single-account Pads list via `@AppStorage`
    /// so the order is consistent across both (#361).
    @AppStorage(PadSort.storageKey) var sort: PadSort = .updatedDesc

    /// Per-render memo so the several reads of `filtered` in one `body` share a
    /// single filter pass, matching `PadsView`'s approach for large lists.
    @State var filteredCache = FilteredScopedPadsCache()
    /// Per-render memo for the sorted cross-account rows (`scoped`), refreshed
    /// once at the top of `body` so its many readers share a single sort.
    @State var scopedCache = ScopedPadsCache()

    init(selection: Binding<Pad?>, search: Binding<String>) {
        _selection = selection
        _search = search

        let cache = PadsCacheStore.shared
        var seeded: [UUID: [Pad]] = [:]
        for account in AccountsStore.shared.mergeableAccounts {
            let pads = cache.get(account.id)
            if !pads.isEmpty { seeded[account.id] = pads }
        }
        _padsByAccount = State(initialValue: seeded)
    }

    var body: some View {
        // Recompute the sorted rows and the filtered rows once per render; every
        // read below (filter pass, chip options, counts) hits the memos.
        refreshScoped()
        refreshFiltered()
        return decorated
    }
}

/// Memo holding the merged list's filtered rows, mirroring `FilteredPadsCache` in
/// `PadsView`. Keyed so a selection-only body pass — a row click re-runs `body`
/// several times via the `selectedIDs → selectedID → selection` cascade — reuses the
/// cached rows instead of re-running the O(n) cross-account filter each time, which is
/// what made clicking a row slow on a large merged list (the merged counterpart of
/// the single-account fix in #395).
final class FilteredScopedPadsCache {
    var rows: [AccountScoped<Account, Pad>] = []
    var key: Key?

    struct Key: Equatable {
        /// The signature of the memoized `scoped` rows this filter ran over, so a real
        /// data change (handled by `refreshScoped()`) invalidates the filter too.
        let scopedSignature: Int
        let filterSignature: String
        /// Rolling date filters depend on the current clock, not just the selected
        /// range, so active date windows add a time bucket to the cache key.
        let dateFilterTimeToken: String?
        /// Owner display names feed the search predicate, so a directory that finishes
        /// loading after the list must re-filter. Its revision tracks content, not
        /// just count: a same-size reload with renamed members must re-filter too (#1214).
        let directoryRevision: Int
    }
}

/// Memo holding the merged list's sorted cross-account rows and chip-option lists,
/// rebuilt only when the merged pads or sort change (keyed by `signature`), so the
/// O(n log n) sort and the option Sets no longer rerun on every render (#366).
final class ScopedPadsCache {
    var rows: [AccountScoped<Account, Pad>] = []
    var availableStates: [PadState] = []
    var availableLanguages: [String] = []
    var availableOwners: [String] = []
    /// The hash of the inputs the cached values were built from; `nil` until the
    /// first build. `refreshScoped()` skips the rebuild while this is unchanged.
    var signature: Int?
}

struct MergedPadsTaskKey: Hashable {
    let accountKey: String
    let phase: ScenePhase
}
