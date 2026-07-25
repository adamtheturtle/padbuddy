//
//  PadsView.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#endif
import AsyncAlgorithms
import SwiftUI
import UniformTypeIdentifiers

struct PadsView: View {
    let client: CoderPadClient
    @Environment(\.orgDirectory) var directory
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) var openWindow
    @Environment(\.undoManager) var undoManager
    /// While offline the app is read-only, so create/delete controls disable (#321).
    @Environment(\.isReadOnly) var isReadOnly
    /// Which window this list is in, so a favourite drag reveals the drop zone
    /// only in this window's sidebar (#2514).
    @Environment(\.windowScope) var windowScope
    #if os(iOS)
        @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    @State var accounts = AccountsStore.shared
    @State var nav = AppNavigation.shared
    @State var cache = PadsCacheStore.shared
    @State var favoritePads = FavoritePadsStore.shared
    @State var pads: [Pad] = []
    @State var isLoading = false
    /// Monotonic reload token: each reload claims a new generation and applies
    /// results only while still the newest, so an older overlapping reload
    /// (pull-to-refresh racing the timer) that finishes last can't roll the list
    /// back to stale data (#1201).
    @State var reloadGeneration = 0
    @State var error: (any Error)?
    @Binding var selection: Pad?
    /// The list selects by pad *id*, not by the whole `Pad`. `List(selection:)` with
    /// a `.tag(pad)` forces SwiftUI to hash and compare every tag to maintain its
    /// selection model, and `Pad`'s synthesized `Hashable` walks every field
    /// (participants, environment ids, dates, team…). On a large org that hashing,
    /// run across thousands of rows each time the filtered set expands, beach-balled
    /// the main thread. A `String` id tag is a cheap hash; `selection` (the `Pad`)
    /// stays the source of truth for the detail pane and is kept in sync below.
    @State var selectedID: String?
    /// The List's selection. A set so several rows can be selected for a bulk action
    /// (Copy links, Delete); `selectedID`/`selection` track the primary within it,
    /// keeping the detail pane, restore, and persistence working off a single id.
    @State var selectedIDs: Set<String> = []
    /// Pads queued for a multi-row delete, awaiting the confirmation dialog. Separate
    /// from `padPendingDelete` (the single swipe/context delete) so the two don't clash.
    @State var padsPendingBulkDelete: [Pad]?
    @State var pendingBulkDeleteUndo: PendingBulkDelete<Pad>?
    @State var bulkDeleteUndoTask: Task<Void, Never>?
    /// Progress through a committed batch, shown in place of the undo banner once the
    /// grace period is over. Before this a long batch looked like nothing was
    /// happening and could not be stopped partway (#2347).
    @State var bulkDeleteProgress: BulkDeleteProgress?
    /// Owned by `MainSplit` so the `.searchable` field can live on the split view
    /// (trailing window toolbar) rather than this content column. All the filter,
    /// saved-search, and persistence logic here still reads and writes it.
    @Binding var search: String
    @State private var clearFiltersPublisherID = UUID()
    @State var discardedFilterNotice: String?
    @State var stateFilter: PadState?
    @State var languageFilter: String?
    @State var ownerFilter: String?
    @State var teamFilter: String?
    @State var typeFilter: String?
    @State var showCreate = false
    /// A favourite question to pre-select in the create sheet, queued by a New Pad
    /// request that carried one (e.g. the widget button). Cleared when the sheet
    /// closes so a later plain "New Pad" starts blank.
    @State var seedQuestionID: Int?
    @State var createFallbackError: String?
    /// A favorite pad picked from the sidebar before the list had loaded it. Held so
    /// the selection can be made once the matching pad arrives (mirrors
    /// `QuestionsView.pendingSelectQuestionID`).
    @State var pendingSelectPadID: String?
    /// A deep-linked or widget-selected pad that was not present after the full
    /// list loaded, surfaced with a recovery action instead of failing silently.
    @State var unavailablePadID: String?
    @State var previousActivity: [String: PadActivitySnapshot] = [:]
    @State var hasLoadedOnce = false
    /// Independent date filters: one constrains the updated date, one the created
    /// date. Both apply at once, so a pad must satisfy each active window.
    @State var updatedWindow = DateWindow()
    @State var createdWindow = DateWindow()
    /// Ticks while a date filter is active so rolling windows such as Today and Last
    /// 24 hours re-filter even if the underlying pad data is unchanged.
    @State var dateFilterClockTick = 0
    /// Guards the once-per-account restore of persisted live filters so the
    /// `onChange` that saves them doesn't fire before the restore has run.
    @State var didRestoreFilters = false
    /// The pad-selection counterpart to `didRestoreFilters`: gates the once-per-load
    /// restore of the previously-open pad, so the `onChange` that persists the
    /// selection doesn't clobber the saved id before the list has loaded.
    @State var didRestoreSelection = false
    /// True only while a restored selection is being applied, so the `selection`
    /// observer can consume the restoration separately from user-driven selection.
    @State var isRestoringSelection = false
    /// The id the list should scroll into view once, set when a previously-open
    /// pad is restored on launch. `List(selection:)` doesn't scroll to a
    /// programmatic selection, so without this the restored pad stays selected
    /// off-screen with the list pinned to the top. Cleared after the scroll.
    @State var pendingScrollToID: String?
    /// Debounces free-scroll-position persistence. `FastList` reports each new top
    /// row during scroll; writing every one to `UserDefaults` makes scrolling hitch
    /// on large pad/question lists (#633).
    @State var topRowPersistTask: Task<Void, Never>?
    /// Per-render memo for `filtered` (see `refreshFiltered()`). A reference type so
    /// `body` can refresh it without mutating SwiftUI state mid-evaluation.
    @State var filteredCache = FilteredPadsCache()
    /// Per-render memo for the filter-chip option lists (see `refreshChipOptions()`),
    /// rebuilt only when `pads` changes rather than on every selection-driven pass (#416).
    @State var chipOptionsCache = PadChipOptionsCache()
    /// Bumped on every mutation of `pads`, so `refreshFiltered()` can tell a real
    /// list change from a body pass driven only by the selection. A click re-runs
    /// `body` several times (the `selectedIDs → selectedID → selection` cascade);
    /// without this token each pass re-ran the O(n) filter + O(n log n) sort over
    /// the whole org, which is what made clicking a row slow on a 2000-pad list
    /// while a filtered (small) list stayed instant (#395). Any new assignment to
    /// `pads` must bump this.
    @State var padsRevision = 0
    /// Id index for selection resolution, rebuilt when `padsRevision` moves on.
    /// Internal, not private: the selection helpers live in PadsView+Actions.
    @State var padIDIndex: (revision: Int, ids: Set<String>) = (-1, [])
    @State var padPendingDelete: Pad?
    @State var deleteError: String?
    /// The active sort, shared with the merged Pads list and the Pad menu's "Sort
    /// By" command via `@AppStorage` (#361). Defaults to newest-updated first, the
    /// order the API already returns.
    @State var sort: PadSort = .updatedDesc

    init(client: CoderPadClient, selection: Binding<Pad?>, search: Binding<String>) {
        self.client = client
        _selection = selection
        _search = search
        // Seed the list from the shared cache at construction, so re-entering the
        // Pads section — which tears this view down and rebuilds it fresh — shows
        // the cached rows on the very first frame instead of flashing empty until
        // the `.task` seeds it a frame later (#329). Read the in-memory snapshot
        // only (never the disk fallback), so init stays a pure read with no store
        // mutation during the view update; the `.task` still refreshes and, on a
        // cold cache, performs the disk/network load as before.
        if let id = AccountsStore.shared.currentAccountID,
           let warm = PadsCacheStore.shared.padsByAccount[id] {
            _pads = State(initialValue: warm)
        }
    }

    /// Big orgs return thousands of pads per sweep, and re-fetching every page on the base
    /// cadence is mostly wasted work for data well below the fold. The auto-refresh cadence
    /// backs off as the list grows, so large orgs poll far less often while small orgs keep
    /// the snappy refresh. It also backs off further when no pad is *started*, biasing
    /// refresh effort toward when live interviews are actually in progress. The base cadence
    /// is the app's fixed auto-refresh interval; manual reload and the focused detail refresh
    /// are unaffected.
    private var nextRefreshInterval: Duration {
        PadListLogic.refreshInterval(
            base: GeneralSettings.refreshInterval,
            padCount: pads.count,
            hasStartedPads: pads.contains { $0.status == .active }
        )
    }

    var body: some View {
        // Recompute the filtered list and chip options exactly once per render; all
        // reads below hit the memos (see `refreshFiltered()` / `refreshChipOptions()`).
        refreshFiltered()
        refreshChipOptions()
        return decoratedSheets
            .focusedSceneValue(\.padSortSelection, $sort)
            .focusedSceneValue(\.clearFiltersAction, ClearFiltersAction(
                id: "pads", publisherID: clearFiltersPublisherID
            ) {
                search = ""
                clearAllFilters()
            })
    }

    // `body` is split across these intermediate `some View` properties rather than one
    // long modifier chain: a ~17-modifier chain makes the Swift type-checker infer a
    // single deeply-nested generic type and blows the Release build's 250ms
    // type-check-timing budget (warnings-as-errors). Each sub-chain type-checks
    // independently here, so none exceeds the budget. Order is preserved. (#427)

    /// `sidebar` plus the per-session load task and the core selection bridge.
    private var decoratedLifecycle: some View {
        sidebar
            .task(id: PadsTaskKey(apiKey: client.apiKey, baseURL: client.baseURL, phase: scenePhase)) {
                guard scenePhase == .active else { return }

                if pads.isEmpty, let id = accounts.currentAccountID {
                    pads = cache.get(id)
                    padsRevision += 1
                }
                // Reopen the pad that was selected last session, once a list exists
                // to resolve it against (the cache above, or the reload below).
                restoreSelectedPadIfNeeded()
                // Initial load, then refresh on a timer rebuilt each cycle so the adaptive
                // pad-count cadence takes effect on the next tick without restarting the task.
                await reload()
                var consecutiveFailures = error == nil ? 0 : 1
                while !Task.isCancelled {
                    let interval = max(
                        AutoRefreshPolicy.interval(
                            base: nextRefreshInterval, consecutiveFailures: consecutiveFailures
                        ),
                        .milliseconds(1)
                    )
                    for await _ in AsyncTimerSequence.repeating(every: interval) {
                        await reload()
                        consecutiveFailures = error == nil ? 0 : consecutiveFailures + 1
                        break
                    }
                }
            }
            .onAppear {
                // Restore first so a deep-link request can still override it (the
                // pending request itself is consumed by the focus-gated observer
                // below, which also runs on appear).
                restoreFilters()
                selectedIDs = selection.map { [$0.id] } ?? []
            }
            // The List edits `selectedIDs`; derive the primary row from it so the
            // detail pane, restore, and persistence keep working off the single
            // `selectedID`. One-way (set → primary), so there's no two-way loop.
            .onChange(of: selectedIDs) { previous, current in
                let primary = MultiSelectLogic.primaryID(previous: previous, current: current)
                if selectedID != primary { selectedID = primary }
                // Resolve the detail-pane `Pad` in the same pass rather than via a second
                // `onChange(selectedID)`. A click re-runs `body` once per state write, and
                // each pass rebuilds the list's prepared rows — so collapsing the
                // selectedIDs → selectedID → selection chain into one update cycle removes
                // a full list rebuild per click on a large list. `selectedID` is only ever
                // derived from `selectedIDs` (here) or from an external `selection` change
                // (below), so there's no separate writer that still needs the bridge.
                if selection?.id != primary {
                    selection = primary.flatMap { id in pads.first { $0.id == id } }
                }
                // Remember the open pad per account so the list reopens to it next launch.
                // Deferred off the click's synchronous path: this writes UserDefaults, and a
                // UserDefaults change re-reads the @AppStorage-backed `sort` mid-update,
                // which invalidated the whole list (an extra full rebuild) on every click.
                // The id and account are captured now so the deferred write can't land
                // under a different account after a fast switch (#757).
                let persistAccount = accounts.currentAccountID
                Task { @MainActor in persistSelectedPad(primary, account: persistAccount) }
            }
    }

    /// The request / account-change / filter / selection observers. Internal (not
    /// private): the `decoratedStreams` link of this modifier chain continues in
    /// PadsView+Streams.swift.
    var decoratedObservers: some View {
        decoratedLifecycle
            // Focus-gated: with several windows on Pads, whichever view observed
            // the process-wide request first used to consume it, so a filter or
            // favorite aimed at the focused window could apply elsewhere (#910).
            .consumesWindowRequest(nav.padsRequest) { applyPendingRequest() }
            // Keyed on this account's write generation rather than the cache
            // dictionary: SwiftUI Equatable-compares an `onChange` key on every body
            // pass, and comparing `[UUID: [Pad]]` walks every pad of every account —
            // for a handler that early-returns as soon as `pads` is populated (#2459).
            .onChange(of: cache.writeGeneration[accounts.currentAccountID ?? UUID()]) { _, _ in
                guard pads.isEmpty, let id = accounts.currentAccountID else { return }

                let warm = cache.cached(id)
                guard !warm.isEmpty else { return }

                pads = warm
                padsRevision += 1
            }
            // The account id is often nil on first appear; restore once it lands, and
            // swap to the new account's saved filters whenever the account changes.
            .onChange(of: accounts.currentAccountID) { _, _ in restoreFiltersForAccountChange() }
            // Persist the live filter snapshot whenever any filter control changes;
            // `filterSignature` shifts for every one, so one observer covers them all.
            .onChange(of: filterSignature) { _, _ in
                persistFilters()
            }
            .task(id: dateFilterClockActive) { await runDateFilterClock() }
            // Mirror the detail selection back to the list's id selection.
            .onChange(of: selection) { _, newValue in
                if isRestoringSelection { isRestoringSelection = false }
                if selectedID != newValue?.id { selectedID = newValue?.id }
            }
    }

    // `decoratedStreams` (the AppRouter stream consumers) and `owningAccountID`
    // live in PadsView+Streams.swift to keep this file within the length lint.

    /// The new-pad sheet, delete confirmations, and delete-error alert.
    private var decoratedSheets: some View {
        decoratedStreams
            .sheet(isPresented: $showCreate) {
                NewPadSheet(client: client, initialQuestionID: seedQuestionID,
                            initialError: createFallbackError) { created in
                    pads.insert(created, at: 0)
                    padsRevision += 1
                    selectedIDs = [created.id]
                    showCreate = false
                    seedQuestionID = nil
                    createFallbackError = nil
                } onCancel: {
                    showCreate = false
                    seedQuestionID = nil
                    createFallbackError = nil
                }
            }
            // Swipe-to-delete reaches a pad without selecting it first, so the
            // confirmation lives here at the list level rather than in the detail
            // pane. It mirrors the detail view's "Delete this pad?" alert.
            .alert(
                "Delete this pad?",
                isPresented: .init(get: { padPendingDelete != nil },
                                   set: { if !$0 { padPendingDelete = nil } }),
                presenting: padPendingDelete
            ) { pad in
                Button("Cancel", role: .cancel) {}
                Button("Delete Pad", role: .destructive) { Task { await deletePad(pad) } }
            } message: { pad in
                Text("“\(pad.title)” will be permanently deleted. This cannot be undone.")
            }
            .alert(
                "Delete \(padsPendingBulkDelete?.count ?? 0) pads?",
                isPresented: .init(get: { padsPendingBulkDelete != nil },
                                   set: { if !$0 { padsPendingBulkDelete = nil } }),
                presenting: padsPendingBulkDelete
            ) { pads in
                Button("Cancel", role: .cancel) {}
                Button("Delete \(pads.count) Pads", role: .destructive) {
                    scheduleBulkDelete(pads)
                }
            } message: { pads in
                Text("You will have a few seconds to undo before these \(pads.count) pads are permanently deleted.")
            }
            .alert("Could not delete pad",
                   isPresented: .init(get: { deleteError != nil },
                                      set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
            .alert("Pad unavailable",
                   isPresented: .init(get: { unavailablePadID != nil },
                                      set: { if !$0 { unavailablePadID = nil } })) {
                if !isReadOnly {
                    Button("Create New Pad") { showCreate = true }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Pad \(unavailablePadID ?? "") is no longer available in this account. "
                    + "The Pads list is open instead.")
            }
            .overlay(alignment: .bottom) { bulkDeleteUndoBanner }
            // A pending bulk delete must die with the list: once the view (and its
            // Undo banner) is gone, letting the grace-period task fire would delete
            // with no remaining way to undo (#1018, mirroring #870).
            .onDisappear { cancelBulkDelete() }
    }
}
