//
//  PadsView.swift
//  coderpad
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PadsView: View {
    let client: CoderPadClient
    @Environment(\.orgDirectory) var directory
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) var openWindow
    /// While offline the app is read-only, so create/delete controls disable (#321).
    @Environment(\.isReadOnly) var isReadOnly
    /// Long-lived target for the list's native double-click-to-open (see
    /// `TableDoubleClickProxy`); opens the selected pad's web URL in a window.
    @State var doubleClickProxy = TableDoubleClickProxy()
    @State var accounts = AccountsStore.shared
    @State var nav = AppNavigation.shared
    @State var cache = PadsCacheStore.shared
    @State var openedStore = PadOpenedStore.shared
    @State var favoritePads = FavoritePadsStore.shared
    @State var pads: [Pad] = []
    @State var isLoading = false
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
    /// Owned by `MainSplit` so the `.searchable` field can live on the split view
    /// (trailing window toolbar) rather than this content column. All the filter,
    /// saved-search, and persistence logic here still reads and writes it.
    @Binding var search: String
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
    /// A favorite pad picked from the sidebar before the list had loaded it. Held so
    /// the selection can be made once the matching pad arrives (mirrors
    /// `QuestionsView.pendingSelectQuestionID`).
    @State var pendingSelectPadID: String?
    @State var previousActivity: [String: PadActivitySnapshot] = [:]
    @State var hasLoadedOnce = false
    /// Independent date filters: one constrains the updated date, one the created
    /// date. Both apply at once, so a pad must satisfy each active window.
    @State var updatedWindow = PadDateWindow()
    @State var createdWindow = PadDateWindow()
    /// Guards the once-per-account restore of persisted live filters so the
    /// `onChange` that saves them doesn't fire before the restore has run.
    @State var didRestoreFilters = false
    /// The pad-selection counterpart to `didRestoreFilters`: gates the once-per-load
    /// restore of the previously-open pad, so the `onChange` that persists the
    /// selection doesn't clobber the saved id before the list has loaded.
    @State var didRestoreSelection = false
    /// True only while a restored selection is being applied, so the `selection`
    /// observer skips marking that pad freshly opened (which would clear its
    /// "new activity" dot before the user has actually looked).
    @State var isRestoringSelection = false
    /// The id the list should scroll into view once, set when a previously-open
    /// pad is restored on launch. `List(selection:)` doesn't scroll to a
    /// programmatic selection, so without this the restored pad stays selected
    /// off-screen with the list pinned to the top. Cleared after the scroll.
    @State var pendingScrollToID: String?
    /// Per-render memo for `filtered` (see `refreshFiltered()`). A reference type so
    /// `body` can refresh it without mutating SwiftUI state mid-evaluation.
    @State var filteredCache = FilteredPadsCache()
    @State var savedSearches = SavedSearchStore.shared
    @State var showSaveSearch = false
    @State var saveSearchName = ""
    @State var isSuggestingName = false
    /// Natural-language filter entry: the sheet's visibility, the typed query, and
    /// whether the on-device interpreter is running. See `SearchInterpreter`.
    @State var showSmartFilter = false
    @State var smartFilterText = ""
    @State var isInterpreting = false
    @State var smartFilterFailed = false
    @State var padPendingDelete: Pad?
    @State var deleteError: String?

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
    /// is the user's configured auto-refresh interval; manual reload and the focused detail
    /// refresh are unaffected.
    private var nextRefreshInterval: Duration {
        PadListLogic.refreshInterval(
            base: GeneralSettings.refreshInterval,
            padCount: pads.count,
            hasStartedPads: pads.contains { $0.status == .active }
        )
    }

    var body: some View {
        // Recompute the filtered list exactly once per render; all reads below hit
        // the memo (see `refreshFiltered()`).
        refreshFiltered()
        return sidebar
            .task(id: TaskKey(apiKey: client.apiKey, phase: scenePhase)) {
                guard scenePhase == .active else { return }
                if pads.isEmpty, let id = accounts.currentAccountID {
                    pads = cache.get(id)
                }
                // Reopen the pad that was selected last session, once a list exists
                // to resolve it against (the cache above, or the reload below).
                restoreSelectedPadIfNeeded()
                await periodicReload(interval: { nextRefreshInterval }, work: {
                    await reload()
                })
            }
            .onAppear {
                // Restore first so a deep-link request can still override it below.
                restoreFilters()
                applyPendingRequest()
                publishLiveFilter()
                selectedIDs = selection.map { [$0.id] } ?? []
                // Double-clicking a row opens the selected pad (the first click
                // selects it). Reads `selection` live, so it stays correct.
                doubleClickProxy.onDoubleClick = { if let pad = selection { openPad(pad) } }
            }
            // The List edits `selectedIDs`; derive the primary row from it so the
            // detail pane, restore, and persistence keep working off the single
            // `selectedID`. One-way (set → primary), so there's no two-way loop.
            .onChange(of: selectedIDs) { previous, current in
                let primary = MultiSelectLogic.primaryID(previous: previous, current: current)
                if selectedID != primary { selectedID = primary }
            }
            // Bridge the lightweight list selection (`selectedID`) to the `Pad`
            // binding the detail pane reads. Each side writes only when the id truly
            // differs, so the two `onChange`s can't ping-pong.
            .onChange(of: selectedID) { _, newID in
                if selection?.id != newID {
                    selection = newID.flatMap { id in pads.first { $0.id == id } }
                }
                // Remember the open pad per account so the list reopens to it next launch.
                persistSelectedPad()
            }
            .onChange(of: nav.padsRequest) { _, _ in applyPendingRequest() }
            // The account id is often nil on first appear; restore once it lands, and
            // swap to the new account's saved filters whenever the account changes.
            .onChange(of: accounts.currentAccountID) { _, _ in restoreFiltersForAccountChange() }
            // One signature drives both persistence and the sidebar highlight: persist
            // the snapshot, and republish it so the sidebar tracks the applied search and
            // falls back to the plain "Pads" row the instant any filter is edited.
            .onChange(of: filterSignature) { _, _ in
                persistFilters()
                publishLiveFilter()
            }
            // Opening (selecting) a pad clears its "new activity" dot until it next
            // changes, and mirrors the change back to the list's id selection.
            .onChange(of: selection) { _, newValue in
                // A selection restored from the last session must not be re-marked
                // opened, or a pad that changed while the app was closed would lose
                // its "new activity" dot before being seen. The flag is consumed once.
                if isRestoringSelection {
                    isRestoringSelection = false
                } else if let newValue, let account = accounts.currentAccountID {
                    openedStore.markOpened(newValue.id, account: account)
                }
                if selectedID != newValue?.id { selectedID = newValue?.id }
            }
            .task {
                for await _ in AppRouter.reloads {
                    await reload()
                }
            }
            .task {
                for await updated in AppRouter.padUpdates {
                    if let index = pads.firstIndex(where: { $0.id == updated.id }) {
                        pads[index] = updated
                        if selection?.id == updated.id { selection = updated }
                    }
                }
            }
            .task {
                for await id in AppRouter.padDeletions {
                    // Drop the deleted id from the selection. If it was the primary,
                    // move to a neighbor (computed while `pads` still holds the row)
                    // only when no other rows stay selected; otherwise the primary
                    // falls to a still-selected row via the `selectedIDs` observer.
                    let wasPrimary = selection?.id == id
                    let neighbor = wasPrimary ? neighborSelection(forDeleted: id) : nil
                    selectedIDs.remove(id)
                    pads.removeAll { $0.id == id }
                    // Keep the disk cache, Spotlight index, and widget in step;
                    // otherwise the deleted pad lingers there until a full reload.
                    cache.removePad(id: id)
                    if wasPrimary, selectedIDs.isEmpty {
                        selectedIDs = neighbor.map { [$0.id] } ?? []
                    }
                }
            }
            .sheet(isPresented: $showSaveSearch) {
                SaveSearchSheet(
                    name: $saveSearchName,
                    prompt: Text("e.g. Live pads, my team"),
                    showsSuggest: SavedSearchNamer.isAvailable,
                    isSuggesting: isSuggestingName,
                    onSuggest: suggestName,
                    onCommit: commitSavedSearch,
                    onCancel: { showSaveSearch = false }
                )
            }
            .sheet(isPresented: $showCreate) {
                NewPadSheet(client: client, initialQuestionID: seedQuestionID) { created in
                    pads.insert(created, at: 0)
                    selectedIDs = [created.id]
                    showCreate = false
                    seedQuestionID = nil
                } onCancel: {
                    showCreate = false
                    seedQuestionID = nil
                }
            }
            .sheet(isPresented: $showSmartFilter) {
                SmartFilterSheet(
                    text: $smartFilterText,
                    isInterpreting: isInterpreting,
                    failed: smartFilterFailed,
                    placeholder: "e.g. active Python pads from my team",
                    onSubmit: { Task { await applySmartFilter() } },
                    onCancel: { showSmartFilter = false }
                )
            }
            // Swipe-to-delete reaches a pad without selecting it first, so the
            // confirmation lives here at the list level rather than in the detail
            // pane. It mirrors the detail view's "Delete this pad?" dialog.
            .confirmationDialog(
                "Delete this pad?",
                isPresented: .init(get: { padPendingDelete != nil },
                                   set: { if !$0 { padPendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: padPendingDelete
            ) { pad in
                Button("Delete Pad", role: .destructive) { Task { await deletePad(pad) } }
                Button("Cancel", role: .cancel) {}
            } message: { pad in
                Text("“\(pad.title)” will be permanently deleted. This can't be undone.")
            }
            .confirmationDialog(
                "Delete \(padsPendingBulkDelete?.count ?? 0) pads?",
                isPresented: .init(get: { padsPendingBulkDelete != nil },
                                   set: { if !$0 { padsPendingBulkDelete = nil } }),
                titleVisibility: .visible,
                presenting: padsPendingBulkDelete
            ) { pads in
                Button("Delete \(pads.count) Pads", role: .destructive) {
                    Task { for pad in pads {
                        await deletePad(pad)
                    } }
                }
                Button("Cancel", role: .cancel) {}
            } message: { pads in
                Text("These \(pads.count) pads will be permanently deleted. This can't be undone.")
            }
            .alert("Couldn't delete pad",
                   isPresented: .init(get: { deleteError != nil },
                                      set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
    }
}

private struct TaskKey: Hashable {
    let apiKey: String
    let phase: ScenePhase
}

/// Holds the filtered pad list across one render so the several reads of `filtered`
/// in `PadsView.body` share a single filter pass. A class (not a `@State` value) so
/// `body` can refresh it without triggering a SwiftUI state mutation.
final class FilteredPadsCache {
    var pads: [Pad] = []
}
