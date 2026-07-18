//
//  PadDetailView.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#else
    import UIKit
    import UniformTypeIdentifiers
#endif
import SwiftUI

struct PadDetailView: View {
    let client: CoderPadClient
    let pad: Pad
    @State var events: [PadEvent] = []
    @State var environments: [PadEnvironment] = []
    /// Environment ids whose fetch failed on the last load: the code cards show
    /// only the surviving environments, so these drive an explicit incomplete-code
    /// warning and block caching the partial result as complete (#713).
    @State var failedEnvironmentIDs: [Int] = []
    @State var histories: [PadFileHistory] = []
    @State var loadError: (any Error)?
    /// Starts true so the Events section shows its spinner on the first frame
    /// rather than flashing "No events yet." before `load()` begins.
    @State var isLoading = true
    /// True for the whole of `load()`, including silent refreshes over cached
    /// content where `isLoading` stays false, so Retry can't stack concurrent
    /// requests (#787).
    @State var isRefreshing = false
    /// The pane the chip bar shows (#980). Notes first: it's the pad's only
    /// long-form editable field and the one pane every pad has. The view is
    /// recreated per pad (`.id(pad.id)`), so each pad starts here.
    @State var selectedSection: PadDetailSection = .notes
    @State var isLoadingHistory = false
    // Inline-editable field drafts, seeded from the pad and committed one field at
    // a time. Each control binds to its draft for an immediate, optimistic update;
    // a failed save reverts the draft to the pad's value (see PadDetailView+Edit).
    @State var draftLanguage = "python3"
    @State var draftOwner = ""
    @State var draftIsPrivate = false
    @State var draftExecution = true
    @State var orgUsers: [OrganizationUser] = []
    // Module-internal (not private) so the Pad-menu handlers and loading split into
    // PadDetailView+MenuActions.swift can drive them across the file boundary.
    @State var showEndConfirm = false
    @State var showDeleteConfirm = false
    @State var isMutating = false
    @State var mutateError: String?
    @State var titleEditRequest = 0
    @State var deletionTask: Task<Void, Never>?
    #if !os(macOS)
        /// The document staged for the iPad's `.fileExporter` (Save All Code / Export Markdown).
        /// `nil` dismisses the export sheet.
        @State var pendingExport: PadExportDocument?
    #endif
    @State var nav = AppNavigation.shared
    @State private var accounts = AccountsStore.shared
    @State private var favorites = FavoritePadsStore.shared
    @Environment(\.orgDirectory) var directory
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.undoManager) private var undoManager
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
        _draftLanguage = State(initialValue: pad.language ?? "python3")
        _draftOwner = State(initialValue: pad.ownerEmail)
        _draftIsPrivate = State(initialValue: pad.isPrivate ?? false)
        _draftExecution = State(initialValue: pad.executionEnabled ?? true)
        // Seed events and environments from the session cache when this pad has been
        // opened before, so re-selecting it shows its detail on the first frame with
        // no spinner — `load()` then refreshes silently in the background (#323).
        if let cached = PadDetailCacheStore.shared.get(pad.id, client: client) {
            _events = State(initialValue: cached.events)
            _environments = State(initialValue: cached.environments)
            _histories = State(initialValue: cached.histories)
            _isLoading = State(initialValue: false)
        }
    }

    /// Detail-column actions live in the unified window toolbar rather than in
    /// the content header: there they float on the system Liquid Glass layer
    /// automatically, and the header stays free for identity and metadata. A
    /// leading spacer separates them from the Pads list's own toolbar items
    /// (Reload, New Pad). Destructive actions stay out of the default toolbar:
    /// Delete Pad remains available from the Pad menu and as an opt-in customizable
    /// toolbar item, while End Interview is also hidden by default. Save Code stays
    /// out of the toolbar (menu-only) to keep it uncrowded.
    @ToolbarContentBuilder
    private var detailToolbar: some CustomizableToolbarContent {
        ToolbarSpacer(.fixed)
        ToolbarItem(id: "favorite", placement: detailToolbarLeadingPlacement) {
            Button { toggleFavorite() } label: {
                Label(isFavorite ? String(localized: "Favorited") : String(localized: "Favorite"),
                      systemImage: isFavorite ? "star.fill" : "star")
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"))
            .accessibilityLabel(isFavorite
                ? String(localized: "Remove from Favorites")
                : String(localized: "Add to Favorites"))
        }
        if let url = pad.webURL {
            ToolbarItem(id: "share", placement: detailToolbarLeadingPlacement) {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share pad")
                .accessibilityLabel("Share pad")
            }
            ToolbarItem(id: "open", placement: detailToolbarLeadingPlacement) {
                Button {
                    BrowserSettings.openExternally(url)
                } label: {
                    // Short title ("Open", not "Open Pad") so it doesn't truncate
                    // to "O…" when the detail column is narrow and the toolbar is
                    // crowded; the accessibility label stays descriptive.
                    Label("Open", systemImage: "doc.text.image")
                }
                .help("Open the pad")
                .accessibilityLabel("Open pad")
            }
        }
        if let playbackURL = pad.playbackURL {
            ToolbarItem(id: "watch", placement: detailToolbarLeadingPlacement) {
                Button {
                    BrowserSettings.openExternally(playbackURL)
                } label: {
                    Label("Watch", systemImage: "play.rectangle")
                }
                .help("Watch the session playback")
                .accessibilityLabel("Watch playback")
            }
            .defaultCustomization(.hidden)
        }
        ToolbarSpacer(.fixed)
        ToolbarItem(id: "delete", placement: detailToolbarTrailingPlacement) {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Pad", systemImage: "trash")
            }
            .disabled(isMutating || isReadOnly || deletionTask != nil)
            .help("Delete this pad")
        }
        .defaultCustomization(.hidden)
        #if !os(macOS)
            // iPad has no menu bar, so the File-menu document actions (Print, Export as
            // Markdown, Save All Code) live in a detail-pane overflow menu instead.
            ToolbarItem(id: "documents", placement: detailToolbarTrailingPlacement) {
                Menu {
                    Button { printPadDocument() } label: {
                        Label("Print", systemImage: "printer")
                    }
                    Button { exportMarkdown() } label: {
                        Label("Export as Markdown", systemImage: "doc.richtext")
                    }
                    Button { saveCodeLocally() } label: {
                        Label("Save All Code", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!hasSavableCode)
                } label: {
                    Label("Document Actions", systemImage: "ellipsis.circle")
                }
            }
        #endif
        // Opt-in only: hidden by default in the customizable toolbar so it
        // doesn't crowd the common case, but available to add for users who end
        // interviews often. Routes through the same confirmation as the Pad menu.
        ToolbarItem(id: "end-interview", placement: detailToolbarTrailingPlacement) {
            Button(role: .destructive) {
                showEndConfirm = true
            } label: {
                Label("End Interview", systemImage: "stop.circle")
            }
            .disabled(isMutating || pad.status != .active || isReadOnly)
            .help("End the live interview session")
        }
        .defaultCustomization(.hidden)
    }

    var body: some View {
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
            .focusedSceneValue(\.focusedPadIsFavorite, isFavorite)
            // Publish a print rendering so File ▸ Print (⌘P) can produce a hard copy
            // or PDF of the pad's summary and code (whatever has loaded so far).
            .focusedSceneValue(\.printAction, PrintAction(id: "pad-\(pad.id)") {
                printPadDocument()
            })
            // Publish a Markdown export action so File ▸ Export as Markdown… can write the
            // pad's summary and code to a .md file (#524).
            .focusedSceneValue(\.exportMarkdownAction, PrintAction(id: "pad-\(pad.id)") {
                exportMarkdown()
            })
            // Publish whether there's anything to save so File ▸ Save All Code… can disable
            // until the pad's code (environments or legacy inline contents) has loaded.
            .focusedSceneValue(\.padHasSavableCode, hasSavableCode)
            .task(id: pad.id) { await load() }
    }

    /// The end/delete confirmations, the failure alert, its error haptic, and the Markdown
    /// file exporter.
    private func presentationDialogs(_ content: some View) -> some View {
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
                Text("You'll have a few seconds to undo before it's permanently deleted.")
            }
            .alert("Action failed",
                   isPresented: .init(get: { mutateError != nil },
                                      set: { if !$0 { mutateError = nil } })) {
                Button("OK", role: .cancel) { mutateError = nil }
            } message: {
                Text(mutateError ?? "")
            }
            // Error haptic when a mutation (end/delete/save) fails; fires only on the
            // transition into an error, not on dismissal. No-op on macOS (#611).
            .sensoryFeedback(trigger: mutateError) { _, new in new != nil ? .error : nil }
        #if !os(macOS)
            .fileExporter(
                isPresented: .init(get: { pendingExport != nil },
                                   set: { if !$0 { pendingExport = nil } }),
                document: pendingExport,
                contentType: pendingExport?.contentType ?? .plainText,
                defaultFilename: pendingExport?.defaultName
            ) { result in
                if case let .failure(error) = result {
                    mutateError = error.localizedDescription
                }
                pendingExport = nil
            }
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
        DispatchQueue.main.async { seedDrafts() }
    }

    /// Seeds the editable drafts on appear and whenever a different pad is shown,
    /// then keeps each in sync with server-side changes (another field's save, or a
    /// push update). The title is no longer among these: `InlineEditableTitle` is now
    /// self-owning (it holds its own draft and focus and commits on Return / focus-loss),
    /// so it reads `pad.title` directly and needs no external draft or focus gating.
    private func draftSync(_ content: some View) -> some View {
        content
            .onChange(of: pad.id, initial: true) { _, _ in scheduleSeedDrafts() }
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

    /// Whether the displayed pad is a favorite of its owning account, so the
    /// toolbar star can reflect and toggle its state.
    private var isFavorite: Bool {
        favorites.isFavorite(pad.id, account: owningAccountID)
    }

    func toggleFavorite() {
        guard let account = owningAccountID else { return }

        favorites.toggle(pad.id, title: pad.title, account: account, undoManager: undoManager)
    }
}

private extension PadDetailView {
    var detailToolbarLeadingPlacement: ToolbarItemPlacement {
        #if os(macOS)
            .primaryAction
        #else
            .topBarLeading
        #endif
    }

    var detailToolbarTrailingPlacement: ToolbarItemPlacement {
        #if os(macOS)
            .primaryAction
        #else
            .topBarTrailing
        #endif
    }
}

// The Pad-menu command handlers and the pad/event/environment loading live in
// PadDetailView+MenuActions.swift (split out for file length).
