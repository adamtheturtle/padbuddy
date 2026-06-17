//
//  PadDetailView.swift
//  coderpad
//

import AppKit
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
    @State private var showEndConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isMutating = false
    @State var mutateError: String?
    @State private var nav = AppNavigation.shared
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
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        }
        if let url = pad.webURL {
            ToolbarItem(id: "share", placement: .primaryAction) {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share pad")
                .accessibilityLabel("Share pad")
            }
            ToolbarItem(id: "open", placement: .primaryAction) {
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
            ToolbarItem(id: "watch", placement: .primaryAction) {
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
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        }
        ToolbarItem(id: "delete", placement: .primaryAction) {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Pad", systemImage: "trash")
            }
            .disabled(isMutating || isReadOnly)
            .help("Delete this pad")
        }
        // Opt-in only: hidden by default in the customizable toolbar so it
        // doesn't crowd the common case, but available to add for users who end
        // interviews often. Routes through the same confirmation as the Pad menu.
        ToolbarItem(id: "end-interview", placement: .primaryAction) {
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
        Group {
            if let url = browserURL {
                VStack(spacing: 0) {
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
                            Image(systemName: "macwindow.badge.plus")
                        }
                        .help("Open in separate window")
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Open in separate window")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .floatingGlass(in: Rectangle(), fallback: .thinMaterial)
                    Divider()
                    PadBrowserView(url: url)
                }
            } else {
                detailScroll
            }
        }
        .toolbar(id: "pad-detail") { detailToolbar }
        // Publish a print rendering so File ▸ Print (⌘P) can produce a hard copy
        // or PDF of the pad's summary and code (whatever has loaded so far).
        .focusedSceneValue(\.printAction, PrintAction(id: "pad-\(pad.id)") {
            printDocument(PadPrintDocument(pad: pad, files: printFiles(),
                                           displayName: directory.display),
                          jobTitle: pad.title.isEmpty ? pad.id : pad.title)
        })
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

extension PadDetailView {
    /// Honors a "Watch Playback" request from the Pad menu, opening the session
    /// playback exactly as the toolbar's Watch button does — in-app or external
    /// per the browser preference.
    private func consumePendingWatch() {
        guard nav.watchPlaybackPadID == pad.id else { return }

        nav.watchPlaybackPadID = nil
        guard let playbackURL = pad.playbackURL else { return }

        if BrowserSettings.openLinksIn == .external {
            BrowserSettings.openExternally(playbackURL)
        } else {
            browserURL = playbackURL
        }
    }

    /// Honors a "Save Code" request from the Pad menu by running the same save
    /// panel as the in-pane button (which knows which environments have loaded).
    private func consumePendingSaveCode() {
        guard nav.saveCodePadID == pad.id else { return }

        nav.saveCodePadID = nil
        saveCodeLocally()
    }

    /// Honors an "Edit Pad" request routed via `AppNavigation` from the Pad menu
    /// command by focusing the inline, editable title field — the fields are now
    /// edited in place rather than through a modal sheet.
    private func consumePendingEdit() {
        guard nav.editPadID == pad.id else { return }

        nav.editPadID = nil
        titleFocused = true
    }

    /// Honors an "End Interview" request from the Pad menu by showing the same
    /// confirmation as the in-pane action — never ending the session without it.
    private func consumePendingEnd() {
        guard nav.endPadID == pad.id else { return }

        nav.endPadID = nil
        showEndConfirm = true
    }

    /// Honors a "Delete Pad" request from the Pad menu by showing the same delete
    /// confirmation as the in-pane Delete action.
    private func consumePendingDelete() {
        guard nav.deletePadID == pad.id else { return }

        nav.deletePadID = nil
        showDeleteConfirm = true
    }

    /// The pad's code as printable sections — one per file, titled by its path,
    /// namespaced by environment so identically-named files across environments
    /// don't collide. Falls back to the legacy inline `contents` when no
    /// environment carries files, mirroring Save Code.
    private func printFiles() -> [PadPrintFile] {
        var result: [PadPrintFile] = []
        for (index, env) in environments.enumerated() {
            for file in displayFiles(for: env) {
                let title = file.path.flatMap { $0.isEmpty ? nil : $0 } ?? "Code"
                result.append(PadPrintFile(id: "\(index)-\(file.id)", title: title, code: file.contents))
            }
        }
        if result.isEmpty, let contents = pad.contents, !contents.isEmpty {
            result.append(PadPrintFile(id: "contents", title: "Code", code: contents))
        }
        return result
    }

    private func endInterview() async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await client.endPad(id: pad.id)
            // Refresh so the ended state/timestamp propagate to the list and detail.
            if let updated = try? await client.getPad(id: pad.id) {
                AppRouter.padUpdated(updated)
            }
        } catch {
            mutateError = error.localizedDescription
        }
    }

    private func deletePad() async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await client.deletePad(id: pad.id)
            AppRouter.padDeleted(id: pad.id)
        } catch {
            mutateError = error.localizedDescription
        }
    }

    func load() async {
        // Only show the blocking spinner when there's nothing to show yet. When the
        // pad was seeded from the session cache (or a prior load), refresh silently
        // over the existing content instead of flashing the spinner on top (#323).
        let hasContent = !events.isEmpty || !environments.isEmpty
        if !hasContent { isLoading = true }
        loadError = nil
        defer { isLoading = false }
        do {
            async let events = client.padEvents(padID: pad.id)
            async let envs = loadEnvironments()
            // Assign environments first — `loadEnvironments` can't throw — so a
            // failing events fetch doesn't leave environments (and the Save Code
            // availability that depends on them) stale. Both still run concurrently.
            let loadedEnvironments = await envs
            environments = loadedEnvironments
            // The API returns events newest-first; display them oldest-first so the
            // log reads top-to-bottom in chronological order (and so the grouping
            // logic, which collapses consecutive same-kind events into an
            // earliest–latest range, stays correct).
            let loadedEvents = try await events.sorted {
                ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
            }
            self.events = loadedEvents
            // Warm the session cache so a later return to this pad is instant.
            PadDetailCacheStore.shared.set(pad.id, events: loadedEvents,
                                           environments: loadedEnvironments)
        } catch {
            loadError = error
        }
    }

    private func loadEnvironments() async -> [PadEnvironment] {
        // Fan the per-id fetches out concurrently rather than awaiting each in turn,
        // so an N-environment pad pays ~1×RTT instead of N×RTT before its code
        // preview appears (#371). Order is restored by id afterward, since task
        // groups yield results as they finish.
        let environments = await withTaskGroup(of: PadEnvironment?.self) { group in
            for id in pad.padEnvironmentIDs {
                group.addTask { try? await client.padEnvironment(id: id) }
            }
            var collected: [PadEnvironment] = []
            for await env in group {
                if let env { collected.append(env) }
            }
            return collected
        }
        let order = Dictionary(uniqueKeysWithValues: pad.padEnvironmentIDs.enumerated().map { ($1, $0) })
        return environments.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }
}
