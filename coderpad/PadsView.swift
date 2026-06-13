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
    @State var accounts = AccountsStore.shared
    @State var nav = AppNavigation.shared
    @State var cache = PadsCacheStore.shared
    @State var openedStore = PadOpenedStore.shared
    @State var pads: [Pad] = []
    @State var isLoading = false
    @State var error: Error?
    @Binding var selection: Pad?
    /// The list selects by pad *id*, not by the whole `Pad`. `List(selection:)` with
    /// a `.tag(pad)` forces SwiftUI to hash and compare every tag to maintain its
    /// selection model, and `Pad`'s synthesized `Hashable` walks every field
    /// (participants, environment ids, dates, team…). On a large org that hashing,
    /// run across thousands of rows each time the filtered set expands, beach-balled
    /// the main thread. A `String` id tag is a cheap hash; `selection` (the `Pad`)
    /// stays the source of truth for the detail pane and is kept in sync below.
    @State var selectedID: String?
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
    @State var previousUpdatedAt: [String: Date] = [:]
    @State var hasLoadedOnce = false
    /// Independent date filters: one constrains the updated date, one the created
    /// date. Both apply at once, so a pad must satisfy each active window.
    @State var updatedWindow = PadDateWindow()
    @State var createdWindow = PadDateWindow()
    /// Guards the once-per-account restore of persisted live filters so the
    /// `onChange` that saves them doesn't fire before the restore has run.
    @State var didRestoreFilters = false
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
    @State var bulkAction: BulkPadAction?
    @State var bulkError: String?
    @State var isBulkRunning = false

    /// A bulk operation over the pads currently shown by the list (after filtering).
    enum BulkPadAction: String, Identifiable {
        case endStarted, makePrivate
        var id: String {
            rawValue
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
                await periodicReload(interval: { nextRefreshInterval }, work: {
                    await reload()
                })
            }
            .onAppear {
                // Restore first so a deep-link request can still override it below.
                restoreFilters()
                applyPendingRequest()
                publishLiveFilter()
                selectedID = selection?.id
            }
            // Bridge the lightweight list selection (`selectedID`) to the `Pad`
            // binding the detail pane reads. Each side writes only when the id truly
            // differs, so the two `onChange`s can't ping-pong.
            .onChange(of: selectedID) { _, newID in
                if selection?.id != newID {
                    selection = newID.flatMap { id in pads.first { $0.id == id } }
                }
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
                if let newValue, let account = accounts.currentAccountID {
                    openedStore.markOpened(newValue.id, account: account)
                }
                if selectedID != newValue?.id { selectedID = newValue?.id }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: .reloadRequested) {
                    await reload()
                }
            }
            .task {
                for await updated in NotificationCenter.default.notifications(named: .padUpdated)
                    .compactMap({ $0.object as? Pad }) {
                    if let index = pads.firstIndex(where: { $0.id == updated.id }) {
                        pads[index] = updated
                        if selection?.id == updated.id { selection = updated }
                    }
                }
            }
            .task {
                for await id in NotificationCenter.default.notifications(named: .padDeleted)
                    .compactMap({ $0.object as? String }) {
                    // Move the selection to a neighbor before dropping the row, so
                    // deleting the open pad keeps the detail pane populated instead
                    // of snapping to the empty placeholder. Computed while `pads`
                    // still holds the deleted pad so the index lookup is valid.
                    if selection?.id == id { selection = neighborSelection(forDeleted: id) }
                    pads.removeAll { $0.id == id }
                }
            }
            // Mirror the toolbar's Bulk menu: the Pad menu's bulk commands post
            // these, and this pane runs them through the same confirmation it
            // already shows for the toolbar buttons.
            .task {
                for await _ in NotificationCenter.default.notifications(named: .bulkEndStartedRequested) {
                    bulkAction = .endStarted
                }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: .bulkMakePrivateRequested) {
                    bulkAction = .makePrivate
                }
            }
            .sheet(isPresented: $showSaveSearch) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Save Search").font(.title3.bold())
                    HStack(spacing: 8) {
                        TextField("Name", text: $saveSearchName, prompt: Text("e.g. Live pads, my team"))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { commitSavedSearch() }
                            .onChange(of: saveSearchName) { _, newValue in
                                if newValue.count > NamedSearch.maxNameLength {
                                    saveSearchName = String(newValue.prefix(NamedSearch.maxNameLength))
                                }
                            }
                        if SavedSearchNamer.isAvailable {
                            suggestNameButton
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Cancel", role: .cancel) { showSaveSearch = false }
                        Button("Save") { commitSavedSearch() }
                            .keyboardShortcut(.defaultAction)
                            .buttonStyle(.borderedProminent)
                            .disabled(saveSearchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
                .frame(minWidth: 360)
            }
            .sheet(isPresented: $showCreate) {
                NewPadSheet(client: client) { created in
                    pads.insert(created, at: 0)
                    selection = created
                    showCreate = false
                } onCancel: {
                    showCreate = false
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
            .alert("Couldn't delete pad",
                   isPresented: .init(get: { deleteError != nil },
                                      set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
            // Bulk actions operate on the pads currently visible in the list (after the
            // active filters/search), so the user controls the scope by narrowing first.
            .confirmationDialog(
                bulkConfirmTitle,
                isPresented: .init(get: { bulkAction != nil },
                                   set: { if !$0 { bulkAction = nil } }),
                titleVisibility: .visible,
                presenting: bulkAction
            ) { action in
                Button(bulkConfirmButton(action), role: .destructive) {
                    Task { await performBulk(action) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { action in
                Text(bulkConfirmMessage(action))
            }
            .alert("Some pads couldn't be updated",
                   isPresented: .init(get: { bulkError != nil },
                                      set: { if !$0 { bulkError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(bulkError ?? "")
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
