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
    @State var loadError: (any Error)?
    // Starts true so the Events section shows its spinner on the first frame
    // rather than flashing "No events yet." before `load()` begins.
    @State var isLoading = true
    @State var browserURL: URL?
    // Inline-editable field drafts, seeded from the pad and committed one field at
    // a time. Each control binds to its draft for an immediate, optimistic update;
    // a failed save reverts the draft to the pad's value (see PadDetailView+Edit).
    @State var titleDraft = ""
    @State var draftLanguage = "python3"
    @State var draftOwner = ""
    @State var draftIsPrivate = false
    @State var draftExecution = true
    @State var orgUsers: [OrganizationUser] = []
    @FocusState var titleFocused: Bool
    // Module-internal (not private) so the Pad-menu handlers and loading split into
    // PadDetailView+MenuActions.swift can drive them across the file boundary.
    @State var showEndConfirm = false
    @State var showDeleteConfirm = false
    @State var isMutating = false
    @State var mutateError: String?
    #if !os(macOS)
        /// The document staged for the iPad's `.fileExporter` (Save Code / Export Markdown).
        /// `nil` dismisses the export sheet.
        @State var pendingExport: PadExportDocument?
    #endif
    @State var nav = AppNavigation.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.orgDirectory) var directory
    @Environment(\.colorScheme) var colorScheme
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
        _titleDraft = State(initialValue: pad.title)
        _draftLanguage = State(initialValue: pad.language ?? "python3")
        _draftOwner = State(initialValue: pad.ownerEmail)
        _draftIsPrivate = State(initialValue: pad.isPrivate ?? false)
        _draftExecution = State(initialValue: pad.executionEnabled ?? true)
        // Seed events and environments from the session cache when this pad has been
        // opened before, so re-selecting it shows its detail on the first frame with
        // no spinner — `load()` then refreshes silently in the background (#323).
        if let cached = PadDetailCacheStore.shared.get(pad.id) {
            _events = State(initialValue: cached.events)
            _environments = State(initialValue: cached.environments)
            _isLoading = State(initialValue: false)
        }
    }

    /// Detail-column actions live in the unified window toolbar rather than in
    /// the content header: there they float on the system Liquid Glass layer
    /// automatically, and the header stays free for identity and metadata. A
    /// leading spacer separates them from the Pads list's own toolbar items
    /// (Reload, New Pad). Delete Pad sits in its own trailing group behind a
    /// second spacer; it requires a confirmation dialog, so surfacing it
    /// directly can't trigger an irreversible action from a stray click. Save
    /// Code stays out of the toolbar (menu-only) to keep it uncrowded. End
    /// Interview is offered as an opt-in customizable item, hidden by default
    /// (see `.defaultCustomization(.hidden)`), so it never crowds the toolbar
    /// unless the user adds it via Customize Toolbar; it also stays on the Pad
    /// menu.
    @ToolbarContentBuilder
    private var detailToolbar: some CustomizableToolbarContent {
        if #available(macOS 26, iOS 26, *) {
            ToolbarSpacer(.fixed)
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
                    if BrowserSettings.openLinksIn == .external {
                        BrowserSettings.openExternally(url)
                    } else {
                        browserURL = url
                    }
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
                    if BrowserSettings.openLinksIn == .external {
                        BrowserSettings.openExternally(playbackURL)
                    } else {
                        browserURL = playbackURL
                    }
                } label: {
                    Label("Watch", systemImage: "play.rectangle")
                }
                .help("Watch the session playback")
                .accessibilityLabel("Watch playback")
            }
        }
        if #available(macOS 26, iOS 26, *) {
            ToolbarSpacer(.fixed)
        }
        ToolbarItem(id: "delete", placement: detailToolbarTrailingPlacement) {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Pad", systemImage: "trash")
            }
            .disabled(isMutating || isReadOnly)
            .help("Delete this pad")
        }
        #if !os(macOS)
            // iPad has no menu bar, so the File-menu document actions (Print, Export as
            // Markdown, Save Code) live in a detail-pane overflow menu instead.
            ToolbarItem(id: "documents", placement: detailToolbarTrailingPlacement) {
                Menu {
                    Button { printPadDocument() } label: {
                        Label("Print", systemImage: "printer")
                    }
                    Button { exportMarkdown() } label: {
                        Label("Export as Markdown", systemImage: "doc.richtext")
                    }
                    Button { saveCodeLocally() } label: {
                        Label("Save Code", systemImage: "square.and.arrow.down")
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

    @ViewBuilder
    private var coreContent: some View {
        if let url = browserURL {
            browserContent(url)
        } else {
            detailScroll
        }
    }

    private func browserContent(_ url: URL) -> some View {
        VStack(spacing: 0) {
            browserHeader(url)
            Divider()
            PadBrowserView(url: url)
        }
    }

    private func browserHeader(_ url: URL) -> some View {
        HStack(spacing: 8) {
            Button {
                browserURL = nil
            } label: {
                Label("Back to Details", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            Spacer()
            Button {
                openWindow(id: "pad-browser", value: url)
            } label: {
                #if os(macOS)
                    Image(systemName: "macwindow.badge.plus")
                #else
                    Image(systemName: "rectangle.badge.plus")
                #endif
            }
            .help("Open in separate window")
            .buttonStyle(.borderless)
            .accessibilityLabel("Open in separate window")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .floatingGlass(in: Rectangle(), fallback: .thinMaterial)
    }

    private func presentationState(_ content: some View) -> some View {
        content
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
            // Publish whether there's anything to save so File ▸ Save Code… can disable
            // until the pad's code (environments or legacy inline contents) has loaded.
            .focusedSceneValue(\.padHasSavableCode, hasSavableCode)
            .task(id: pad.id) { await load() }
            .confirmationDialog("End this interview?", isPresented: $showEndConfirm, titleVisibility: .visible) {
                Button("End Interview", role: .destructive) { Task { await endInterview() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Ending the interview stops the live session for all participants.")
            }
            .confirmationDialog("Delete this pad?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Pad", role: .destructive) { Task { await deletePad() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deleting the pad is permanent and cannot be undone.")
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

    /// Wires the Pad menu commands (Edit, End, Delete, Watch, Save Code), which
    /// arrive via `AppNavigation`, to their in-pane equivalents. Split out of `body`
    /// so the modifier chain stays within the type-checker's reach.
    private func menuRouting(_ content: some View) -> some View {
        content
            .onAppear {
                consumePendingEdit()
                consumePendingEnd()
                consumePendingDelete()
                consumePendingWatch()
                consumePendingSaveCode()
            }
            .onChange(of: nav.editPadID) { _, _ in consumePendingEdit() }
            .onChange(of: nav.endPadID) { _, _ in consumePendingEnd() }
            .onChange(of: nav.deletePadID) { _, _ in consumePendingDelete() }
            .onChange(of: nav.watchPlaybackPadID) { _, _ in consumePendingWatch() }
            .onChange(of: nav.saveCodePadID) { _, _ in consumePendingSaveCode() }
    }

    /// Seeds the editable drafts on appear and whenever a different pad is shown,
    /// then keeps each in sync with server-side changes (another field's save, or a
    /// push update) — except the title while it's being typed. A title edit commits
    /// when focus leaves the field, mirroring the Return key.
    private func draftSync(_ content: some View) -> some View {
        content
            .onChange(of: pad.id, initial: true) { _, _ in seedDrafts() }
            .onChange(of: pad.title) { _, newValue in if !titleFocused { titleDraft = newValue } }
            .onChange(of: pad.language) { _, newValue in draftLanguage = newValue ?? "python3" }
            .onChange(of: pad.ownerEmail) { _, newValue in draftOwner = newValue }
            .onChange(of: pad.isPrivate) { _, newValue in draftIsPrivate = newValue ?? false }
            .onChange(of: pad.executionEnabled) { _, newValue in draftExecution = newValue ?? true }
            .onChange(of: titleFocused) { _, focused in if !focused { Task { await commitTitle() } } }
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
