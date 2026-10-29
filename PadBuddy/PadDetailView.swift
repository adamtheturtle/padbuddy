//
//  PadDetailView.swift
//  coderpad
//

// swiftlint:disable file_length

#if os(macOS)
    import AppKit
#else
    import UIKit
    import UniformTypeIdentifiers
#endif
import SwiftUI

struct PadDetailView: View { // swiftlint:disable:this type_body_length
    let client: CoderPadClient
    let pad: Pad
    @State private var printActionPublisherID = UUID()
    @State var events: [PadEvent] = []
    @State var eventsRevision = 0
    let eventPresentationCache = PadEventPresentationCache()
    @State var participantsLastRefreshed: Date?
    @State var environments: [PadEnvironment] = []
    /// Each environment's normalized display files, keyed by environment id.
    ///
    /// `displayFiles(for:)` re-walks and re-canonicalizes every file's contents,
    /// and a single render asked for it from the code cards, the section list,
    /// the header chip, and the save-availability check — five to ten times over
    /// for a multi-file pad (#2089). It depends only on `environments`, so it is
    /// computed wherever those are set and read from here.
    @State var displayFilesByEnvironment: [Int: [CodeFile]] = [:]
    /// Environment ids whose fetch failed on the last load: the code cards show
    /// only the surviving environments, so these drive an explicit incomplete-code
    /// warning and block caching the partial result as complete (#713).
    @State var failedEnvironmentIDs: [Int] = []
    /// True when remote data named more environments than one detail load may
    /// safely fetch, so the UI identifies the displayed code as incomplete.
    @State var environmentListWasTruncated = false
    @State var histories: [PadFileHistory] = []
    @State var loadError: (any Error)?
    /// Starts true so the Events section shows its spinner on the first frame
    /// rather than flashing "No events yet." before `load()` begins.
    @State var isLoading = true
    /// True for the whole of `load()`, including silent refreshes over cached
    /// content where `isLoading` stays false, so Retry can't stack concurrent
    /// requests (#787).
    @State var isRefreshing = false
    /// True only for user-visible refresh requests. Selection-driven background
    /// reloads keep this false so the toolbar button does not flash disabled.
    @State var showsRefreshControls = false
    @State var loadGeneration = 0
    @State var refreshingIdentity: PadDetailLoadIdentity?
    /// long-form editable field and the one pane every pad has. The view is
    /// stable metadata, while the title stays visible above every pane. The view is
    /// recreated per pad (`.id(pad.id)`), so each pad starts here.
    @State var selectedSection: PadDetailSection = .overview
    @State var isLoadingHistory = false
    /// How many files' history fetches failed on the last load, so the History
    /// card can say playback is incomplete instead of silently omitting files
    /// (#1762). Refresh retries them.
    @State var historyLoadFailures = 0
    @State var historyLoadWasTruncated = false
    // Inline-editable field drafts, seeded from the pad and committed one field at
    // a time. Each control binds to its draft for an immediate, optimistic update;
    // a failed save reverts the draft to the pad's value (see PadDetailView+Edit).
    @State var draftLanguage = "python3"
    @State var draftOwner = ""
    @State var draftIsPrivate = false
    @State var draftExecution = true
    @State var orgUsers: [OrganizationUser] = []
    @State var orgUsersLoadError: String?
    @State var orgUsersReloadID = 0
    /// The client identity `orgUsers` was fetched through, so a re-keyed account
    /// drops the previous org's member list instead of offering it (#1191).
    @State var orgUsersSource: String?
    // Module-internal (not private) so the Pad-menu handlers and loading split into
    // PadDetailView+MenuActions.swift can drive them across the file boundary.
    @State var showEndConfirm = false
    @State var endInterviewTarget: PadMutationTarget?
    @State var showDeleteConfirm = false
    @State var destructiveMutation = PadDestructiveMutationGate()
    @State var mutateError: String?
    @State var notesConflict: PadNotesConflict?
    @State var titleEditRequest: CommandTitleEditRequest?
    @State var deletionTask: Task<Void, Never>?
    /// Generation counter for the deferred draft seeding (see `scheduleSeedDrafts`),
    /// so a stale queued seed can't overwrite a newer pad's drafts (#1192).
    @State private var draftSeedGeneration = 0
    /// Latest known pad — this view's own optimistic publishes plus whatever the
    /// parent last passed in — used as the merge base for optimistic updates so a
    /// save never republishes stale copies of fields it didn't send (#1186).
    @State var latestPad: Pad?
    #if !os(macOS)
        /// The document staged for the iPad's `.fileExporter` (Save All Code / Export Markdown).
        /// `nil` dismisses the export sheet.
        @State var pendingExport: PadExportDocument?
    #endif
    @State var nav = AppNavigation.shared
    @State var showingAccessEditor = false
    @State var accounts = AccountsStore.shared
    @State var favorites = FavoritePadsStore.shared
    @Environment(\.orgDirectory) var directory
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.undoManager) var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
        @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    /// While offline the app is read-only, so the destructive/edit actions disable (#321).
    @Environment(\.isReadOnly) var isReadOnly

    /// Seed the editable drafts from the pad up front so the title and properties
    /// render with their real values on the very first frame. The view is recreated
    /// per pad (`.id(pad.id)`), so this runs on every pad switch; without it the
    /// fields briefly showed their placeholder defaults before `seedDrafts()` ran in
    /// an `.onChange(initial: true)` a frame later, flashing the title blank-to-filled.
    init(client: CoderPadClient, pad: Pad) {
        self.client = client
        self.pad = pad
        // Environment discovery precedes the history requests, but the pad payload
        // already tells us whether there can be session playback. Seed this state so
        // opening History shows progress on the first frame instead of a blank pane.
        _isLoadingHistory = State(
            initialValue: pad.padEnvironmentIDs.contains(where: { $0 > 0 })
        )
        _draftLanguage = State(initialValue: pad.language ?? "python3")
        _draftOwner = State(initialValue: pad.ownerEmail)
        _draftIsPrivate = State(initialValue: pad.isPrivate ?? false)
        _draftExecution = State(initialValue: pad.executionEnabled ?? true)
        // Seed events and environments from the session cache when this pad has been
        // opened before, so re-selecting it shows its detail on the first frame with
        // no spinner — `load()` then refreshes silently in the background (#323).
        if let cached = PadDetailCacheStore.shared.get(pad.id, client: client) {
            _events = State(initialValue: cached.events)
            _eventsRevision = State(initialValue: 1)
            _environments = State(initialValue: cached.environments)
            _displayFilesByEnvironment = State(
                initialValue: Self.normalizedDisplayFiles(for: cached.environments)
            )
            _histories = State(initialValue: cached.histories)
            _isLoading = State(initialValue: false)
            _isLoadingHistory = State(initialValue: false)
        }
    }

    /// Detail-column actions live in the unified window toolbar rather than in
    /// the content header: there they float on the system Liquid Glass layer
    /// automatically, and the header stays free for identity and metadata. A
    /// leading spacer separates them from the Pads list's own toolbar items
    /// (Reload, New Pad). Destructive actions stay out of the default toolbar:
    /// Delete Pad remains available from the Pad menu and as an opt-in customizable
    /// out of the toolbar (menu-only) to keep it uncrowded.
    /// and Save Code stay out of the toolbar (menu-only) to keep it uncrowded.
    @ToolbarContentBuilder
    private var detailToolbar: some CustomizableToolbarContent {
        #if !os(visionOS)
            ToolbarSpacer(.fixed)
        #endif
        detailReloadToolbarItem
        ToolbarItem(id: "favorite", placement: detailToolbarLeadingPlacement) {
            Button { toggleFavorite() } label: {
                Label(isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"),
                      systemImage: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"))
            .accessibilityLabel(isFavorite
                ? String(localized: "Remove from Favorites")
                : String(localized: "Add to Favorites"))
        }
        if let url = pad.webURL(fallbackBase: client.baseURL) {
            ToolbarItem(id: "share-pad", placement: detailToolbarLeadingPlacement) {
                ShareLink(item: url) {
                    Label("Share pad", systemImage: "square.and.arrow.up")
                }
                .help("Share pad")
                .accessibilityLabel("Share pad")
            }
            ToolbarItem(id: "open-pad", placement: detailToolbarLeadingPlacement) {
                Button {
                    if let owningAccountID {
                        PadOpenedStore.shared.record(pad.id, account: owningAccountID)
                    }
                    BrowserSettings.openExternally(url)
                } label: {
                    Label("Open pad", systemImage: "doc.text.image")
                }
                .help("Open pad")
                .accessibilityLabel("Open pad")
            }
        }
        #if !os(visionOS)
            ToolbarSpacer(.fixed)
        #endif
        #if !os(visionOS)
            ToolbarItem(id: "delete", placement: detailToolbarTrailingPlacement) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Pad", systemImage: "trash")
                }
                .tint(.red)
                .disabled(destructiveMutation.isActive || isReadOnly)
                .help("Delete this pad")
            }
            .defaultCustomization(.hidden)
        #endif
        #if !os(macOS) && !os(visionOS)
            ToolbarItem(id: "print", placement: detailToolbarTrailingPlacement) {
                Button { printPadDocument() } label: {
                    Label("Print", systemImage: "printer")
                }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "export-markdown", placement: detailToolbarTrailingPlacement) {
                Button { exportMarkdown() } label: {
                    Label("Export as Markdown", systemImage: "doc.richtext")
                }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "save-code", placement: detailToolbarTrailingPlacement) {
                Button { saveCodeLocally() } label: {
                    Label("Save All Code", systemImage: "square.and.arrow.down")
                }
                .disabled(!hasSavableCode)
            }
            .defaultCustomization(.hidden)
        #endif
        // Opt-in only: hidden by default in the customizable toolbar so it
        // doesn't crowd the common case, but available to add for users who end
        // interviews often. Routes through the same confirmation as the Pad menu.
        #if !os(visionOS)
            ToolbarItem(id: "end-interview", placement: detailToolbarTrailingPlacement) {
                Button(role: .destructive) {
                    armEndInterview()
                } label: {
                    Label("End Interview", systemImage: "stop.circle")
                }
                .tint(.red)
                .disabled(destructiveMutation.isActive || pad.status != .active || isReadOnly)
                .help("End the live interview session")
            }
            .defaultCustomization(.hidden)
        #endif
    }

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = refreshEventPresentation()
        menuRouting(draftSync(core))
    }

    private var core: some View {
        presentationState(coreContent.toolbar(id: "pad-detail") { detailToolbar })
    }

    private var coreContent: some View {
        detailScroll
            .overlay(alignment: .bottom) { undoDeletionBanner }
            .animation(reduceMotion ? nil : .spring(duration: 0.3), value: deletionTask == nil)
    }

    /// Split into two sub-chains (publishers, then dialogs) rather than one long chain:
    /// the combined chain tips the Swift type-checker over its 250ms per-expression budget
    /// on the iOS SDK, which warnings-as-errors turns into a hard build failure. Each half
    /// type-checks comfortably under the limit.
    private func presentationState(_ content: some View) -> some View {
        presentationDialogs(presentationPublishers(content))
    }

    /// Publishes the focused-scene values (Print / Export / Save availability) and kicks
    /// off the pad load.
    private func presentationPublishers(_ content: some View) -> some View {
        content
            // Publish the favorite state so the Pad menu's Favorite command can
            // show the matching "Add to"/"Remove from Favorites" title and toggle it.
            .focusedSceneValue(\.focusedPadFavoriteState, focusedFavoriteState)
            // Publish a print rendering so File ▸ Print (⌘P) can produce a hard copy
            // or PDF of the pad's summary and code (whatever has loaded so far).
            .focusedSceneValue(\.printAction, PrintAction(id: "pad-\(pad.id)",
                                                          publisherID: printActionPublisherID,
                                                          contentFingerprint: pad.hashValue) {
                    printPadDocument()
                })
            // Publish a Markdown export action so File ▸ Export as Markdown… can write the
            // pad's summary and code to a .md file (#524).
            .focusedSceneValue(\.exportMarkdownAction, PrintAction(id: "pad-\(pad.id)",
                                                                   publisherID: printActionPublisherID,
                                                                   contentFingerprint: pad.hashValue) {
                    exportMarkdown()
                })
            // Publish whether there's anything to save so File ▸ Save All Code… can disable
            // until the pad's code (environments or legacy inline contents) has loaded.
            .focusedSceneValue(\.padHasSavableCode, hasSavableCode)
            .task(id: detailLoadIdentity) {
                if let owningAccountID {
                    PadOpenedStore.shared.record(pad.id, account: owningAccountID)
                }
                await load(visibleRefreshControls: false)
            }
            // A confirmed-but-not-yet-fired deletion is held in `deletionTask`, not
            // run from `.task`, so leaving the detail would otherwise let it fire
            // after the grace period with the Undo banner long gone from screen
            // (#2368). Cancelling means navigating away abandons it, which matches
            // what the banner disappearing implies.
            .onDisappear {
                deletionTask?.cancel()
                deletionTask = nil
                destructiveMutation.finish(.deleting)
            }
    }

    /// The end/delete confirmations, the failure alert, its error haptic, and the Markdown
    /// file exporter.
    private func presentationDialogs(_ content: some View) -> some View {
        exportDialog(errorFeedback(basePresentationDialogs(content)))
    }

    private func basePresentationDialogs(_ content: some View) -> some View {
        content
            .alert("End this interview?", isPresented: $showEndConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("End Interview", role: .destructive) { Task { await endInterview() } }
            } message: {
                Text("Ending the interview stops the live session for all participants.")
            }
            .alert("Delete this pad?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Pad", role: .destructive) { startDeletion() }
            } message: {
                Text("You will have a few seconds to undo before it is permanently deleted.")
            }
            .alert("Action failed",
                   isPresented: .init(get: { mutateError != nil },
                                      set: {
                                          if !$0 {
                                              mutateError = nil
                                          }
                                      })) {
                Button("OK", role: .cancel) { mutateError = nil }
            } message: {
                Text(mutateError ?? "")
            }
            .sheet(item: $notesConflict) { conflict in
                PadNotesConflictView(conflict: conflict) { notesConflict = nil }
            }
    }

    @ViewBuilder
    private func errorFeedback(_ content: some View) -> some View {
        // Error haptic when a mutation (end/delete/save) fails; unavailable before visionOS 26 (#611).
        #if os(visionOS)
            if #available(visionOS 26.0, *) {
                content.sensoryFeedback(trigger: mutateError) { _, new in new != nil ? .error : nil }
            } else {
                content
            }
        #else
            content.sensoryFeedback(trigger: mutateError) { _, new in new != nil ? .error : nil }
        #endif
    }

    @ViewBuilder
    private func exportDialog(_ content: some View) -> some View {
        #if !os(macOS)
            content.fileExporter(
                isPresented: .init(get: { pendingExport != nil },
                                   set: {
                                       if !$0 {
                                           clearPendingPadExport(&pendingExport)
                                       }
                                   }),
                document: pendingExport,
                contentType: pendingExport?.contentType ?? .plainText,
                defaultFilename: pendingExport?.defaultName
            ) { result in
                if case let .failure(error) = result {
                    mutateError = error.localizedDescription
                }
                clearPendingPadExport(&pendingExport)
            }
        #else
            content
        #endif
    }

    /// Wires the Pad menu commands (Edit, End, Delete, Watch, Save All Code), which
    /// arrive via `AppNavigation`, to their in-pane equivalents. Split out of `body`
    /// so the modifier chain stays within the type-checker's reach. Consumption is
    /// focus-gated: the same pad can be open in the main split and a standalone
    /// window at once, and whichever copy's observer fired first used to consume
    /// the command - so a Delete/End confirmation could appear behind the focused
    /// window, and Edit/Playback/Save could seem to do nothing (#871).
    private func menuRouting(_ content: some View) -> some View {
        content
            .consumesWindowRequest(nav.editPadID) { consumePendingEdit() }
            .consumesWindowRequest(nav.endPadID) { consumePendingEnd() }
            .consumesWindowRequest(nav.deletePadID) { consumePendingDelete() }
            .consumesWindowRequest(nav.watchPlaybackPadID) { consumePendingWatch() }
            .consumesWindowRequest(nav.saveCodePadID) { consumePendingSaveCode() }
            .consumesWindowRequest(nav.toggleFavoritePadID) { consumePendingFavoriteToggle() }
    }

    private func scheduleSeedDrafts() {
        // Claim the newest generation: the displayed pad can change again before
        // the queued block runs, and a stale callback would seed the drafts from
        // the wrong pad (#1192, mirroring the question detail's guard).
        draftSeedGeneration &+= 1
        let generation = draftSeedGeneration
        DispatchQueue.main.async {
            guard generation == draftSeedGeneration else { return }

            seedDrafts()
        }
    }

    /// Seeds the editable drafts on appear and whenever a different pad is shown,
    /// then keeps each in sync with server-side changes (another field's save, or a
    /// push update). The title is no longer among these: `InlineEditableTitle` is now
    /// self-owning (it holds its own draft and focus and commits on Return / focus-loss),
    /// so it reads `pad.title` directly and needs no external draft or focus gating.
    private func draftSync(_ content: some View) -> some View {
        content
            .onChange(of: pad.id, initial: true) { _, _ in scheduleSeedDrafts() }
            // Track every pad change (a refresh, another window's edit bounced back
            // through the router) so optimistic saves merge into the freshest base (#1186).
            .onChange(of: pad, initial: true) { _, newValue in latestPad = newValue }
            .onChange(of: pad.language) { _, newValue in draftLanguage = newValue ?? "python3" }
            .onChange(of: pad.ownerEmail) { _, newValue in draftOwner = newValue }
            .onChange(of: pad.isPrivate) { _, newValue in draftIsPrivate = newValue ?? false }
            .onChange(of: pad.executionEnabled) { _, newValue in draftExecution = newValue ?? true }
    }

    /// The account the displayed pad belongs to, resolved from the view's own
    /// client: a standalone pad window or a merged row can belong to a non-current
    /// account, and keying favorites by the current account starred the pad under
    /// whichever account happened to be selected elsewhere (#986). Falls back to
    /// the current account for clients that don't match a stored account (mocks).
    /// Internal (not private): the edit/menu-action extensions stamp it onto pad
    /// mutation broadcasts so consumers can scope them by account (#761).
    var owningAccountID: UUID? {
        (accounts.account(matching: client) ?? accounts.currentAccount)?.id
    }
}

// The Pad-menu command handlers and the pad/event/environment loading live in
// PadDetailView+MenuActions.swift (split out for file length).
