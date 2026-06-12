//
//  PadsView.swift
//  coderpad
//

import SwiftUI
import AppKit

struct PadsView: View {
    let client: CoderPadClient
    @Environment(\.orgDirectory) private var directory
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @State private var accounts = AccountsStore.shared
    @State private var nav = AppNavigation.shared
    @State private var cache = PadsCacheStore.shared
    @State private var openedStore = PadOpenedStore.shared
    @State private var pads: [Pad] = []
    @State private var isLoading = false
    @State private var error: Error?
    @Binding var selection: Pad?
    @State private var search = ""
    @FocusState private var searchFieldFocused: Bool
    @State private var stateFilter: PadState? = nil
    @State private var languageFilter: String? = nil
    @State private var ownerFilter: String? = nil
    @State private var teamFilter: String? = nil
    @State private var typeFilter: String? = nil
    @State private var showCreate = false
    @State private var previousUpdatedAt: [String: Date] = [:]
    @State private var hasLoadedOnce = false
    @State private var dateRangeFilter: String? = nil
    @State private var savedSearches = SavedSearchStore.shared
    @State private var showSaveSearch = false
    @State private var saveSearchName = ""
    @State private var isSuggestingName = false
    @State private var padPendingDelete: Pad?
    @State private var deleteError: String?
    @State private var bulkAction: BulkPadAction?
    @State private var bulkError: String?
    @State private var isBulkRunning = false

    /// A bulk operation over the pads currently shown by the list (after filtering).
    private enum BulkPadAction: String, Identifiable {
        case endStarted, makePrivate
        var id: String { rawValue }
    }

    /// Big orgs return thousands of pads per sweep, and re-fetching every page on the base
    /// cadence is mostly wasted work for data well below the fold. The auto-refresh cadence
    /// backs off as the list grows, so large orgs poll far less often while small orgs keep
    /// the snappy refresh. The base cadence is the user's configured auto-refresh interval;
    /// manual reload and the focused detail refresh are unaffected.
    private var nextRefreshInterval: Duration {
        let base = GeneralSettings.refreshInterval
        switch pads.count {
        case ..<500: return base
        case 500..<2000: return base * 2
        default: return base * 4
        }
    }

    var body: some View {
        sidebar
        .task(id: TaskKey(apiKey: client.apiKey, phase: scenePhase)) {
            guard scenePhase == .active else { return }
            if pads.isEmpty, let id = accounts.currentAccountID {
                pads = cache.get(id)
            }
            await periodicReload(interval: { nextRefreshInterval }) {
                await reload()
            }
        }
        .onAppear { applyPendingRequest() }
        .onChange(of: nav.padsRequest) { _, _ in applyPendingRequest() }
        // Opening (selecting) a pad clears its "new activity" dot until it next changes.
        .onChange(of: selection) { _, newValue in
            if let newValue, let account = accounts.currentAccountID {
                openedStore.markOpened(newValue.id, account: account)
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .reloadRequested) {
                await reload()
            }
        }
        .task {
            for await updated in NotificationCenter.default.notifications(named: .padUpdated)
                .compactMap({ $0.object as? Pad }) {
                if let i = pads.firstIndex(where: { $0.id == updated.id }) {
                    pads[i] = updated
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

    private var bulkConfirmTitle: String {
        switch bulkAction {
        case .endStarted: return "End \(PadListLogic.startedPads(in: filtered).count) started pads?"
        case .makePrivate: return "Make \(PadListLogic.nonPrivatePads(in: filtered).count) pads private?"
        case nil: return ""
        }
    }

    private func bulkConfirmButton(_ action: BulkPadAction) -> String {
        switch action {
        case .endStarted: return "End Started Pads"
        case .makePrivate: return "Make Private"
        }
    }

    private func bulkConfirmMessage(_ action: BulkPadAction) -> String {
        switch action {
        case .endStarted:
            return "This ends every started pad currently shown in the list. Ending an interview can't be undone."
        case .makePrivate:
            return "This marks every pad currently shown in the list as private."
        }
    }

    /// Runs a bulk action over the currently-visible pads, then refreshes. Failures
    /// are counted and surfaced without aborting the rest of the batch.
    private func performBulk(_ action: BulkPadAction) async {
        let targets: [Pad]
        switch action {
        case .endStarted: targets = PadListLogic.startedPads(in: filtered)
        case .makePrivate: targets = PadListLogic.nonPrivatePads(in: filtered)
        }
        guard !targets.isEmpty else { return }
        isBulkRunning = true
        defer { isBulkRunning = false }
        var failures = 0
        for pad in targets {
            do {
                switch action {
                case .endStarted: try await client.endPad(id: pad.id)
                case .makePrivate: _ = try await client.updatePad(PadUpdate(id: pad.id, isPrivate: true))
                }
            } catch {
                failures += 1
            }
        }
        if failures > 0 {
            bulkError = "\(failures) of \(targets.count) pads couldn't be updated."
        }
        await reload()
    }

    /// Delete a pad reached via swipe action. Posts `.padDeleted` so this list —
    /// and any other open window — drops the row, matching the detail view's own
    /// delete path.
    private func deletePad(_ pad: Pad) async {
        do {
            try await client.deletePad(id: pad.id)
            NotificationCenter.default.post(name: .padDeleted, object: pad.id)
        } catch {
            deleteError = error.localizedDescription
        }
    }

    /// Applies any request queued by `AppNavigation` (e.g. from clicking a user in
    /// Organization), then clears it so it isn't re-applied. Runs both on first
    /// appear — covering the case where this pane wasn't mounted when the request
    /// was made — and on change, for when the pane is already on screen.
    private func applyPendingRequest() {
        guard let request = nav.padsRequest else { return }
        nav.padsRequest = nil
        if let owner = request.ownerEmail { ownerFilter = owner }
        if let query = request.search { search = query }
        if request.startCreating { showCreate = true }
    }

    /// A sparkle button that fills the name field with an on-device suggestion
    /// built from the active filters. Shown only when the model is available; the
    /// field stays fully editable and the user opts in per save.
    @ViewBuilder
    private var suggestNameButton: some View {
        Button(action: suggestName) {
            if isSuggestingName {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "sparkles")
            }
        }
        .buttonStyle(.borderless)
        .disabled(isSuggestingName)
        .help("Suggest a name from the current filters")
        .accessibilityLabel("Suggest a name")
    }

    private func suggestName() {
        let captured = captureCurrentSearch(named: "")
        isSuggestingName = true
        Task {
            let suggestion = await SavedSearchNamer.suggestName(for: captured)
            isSuggestingName = false
            if let suggestion { saveSearchName = suggestion }
        }
    }

    private func commitSavedSearch() {
        // Return in the text field fires `onSubmit` and the default-action button can
        // also fire; guarding on the still-open sheet keeps a single keypress from
        // saving the search twice.
        guard showSaveSearch else { return }
        let trimmed = String(saveSearchName.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(NamedSearch.maxNameLength))
        guard !trimmed.isEmpty, let account = accounts.currentAccountID else { return }
        savedSearches.add(captureCurrentSearch(named: trimmed), account: account, kind: .pads)
        showSaveSearch = false
    }

    private static let dateRangeOptions = PadDateRange.options

    private var filtered: [Pad] {
        PadListLogic.filter(
            pads,
            using: PadFilterCriteria(
                search: search,
                state: stateFilter,
                language: languageFilter,
                owner: ownerFilter,
                team: teamFilter,
                type: typeFilter,
                dateRange: dateRangeFilter
            ),
            display: directory.display
        )
    }

    /// The pad to select after the pad with `id` is deleted. Picks the row that
    /// takes the deleted row's position (the next one down), falling back to the
    /// previous pad when the deleted pad was last, and to `nil` when it was the
    /// only visible pad. Resolved against `filtered` — the list the user actually
    /// sees — so a hidden pad never becomes the new selection.
    private func neighborSelection(forDeleted id: String) -> Pad? {
        let visible = filtered
        // If the deleted pad isn't in the visible list (e.g. filters changed after it
        // was selected), fall back to the first visible pad rather than blanking the
        // detail pane when there are still pads to show.
        guard let i = visible.firstIndex(where: { $0.id == id }) else { return visible.first }
        if visible.indices.contains(i + 1) { return visible[i + 1] }
        if visible.indices.contains(i - 1) { return visible[i - 1] }
        return nil
    }

    private var availableStates: [PadState] {
        Array(Set(pads.map(\.status))).sorted { $0.label < $1.label }
    }
    private var availableLanguages: [String] {
        Array(Set(pads.compactMap { $0.language?.lowercased() }).filter { !$0.isEmpty }).sorted()
    }
    private var availableOwners: [String] {
        Array(Set(pads.map { $0.ownerEmail }).filter { !$0.isEmpty }).sorted()
    }
    private var availableTeams: [String] {
        Array(Set(pads.compactMap { $0.team?.name })).sorted()
    }
    private var activeFilterCount: Int {
        (stateFilter != nil ? 1 : 0)
            + [languageFilter, ownerFilter, teamFilter, typeFilter, dateRangeFilter].compactMap { $0 }.count
    }

    private var sidebar: some View {
        Group {
            if isLoading && pads.isEmpty {
                ProgressView("Loading pads…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, pads.isEmpty {
                APIErrorView(error: error) { Task { await reload() } }
            } else {
                VStack(spacing: 0) {
                    PaneTitle(title: "Pads")
                    InlineSearchField(query: $search, prompt: "Search title, owner, participants…",
                                      focused: $searchFieldFocused)
                        .padding(.horizontal, Spacing.paneH)
                        .padding(.bottom, 8)
                    savedSearchesBar
                    filterBar
                    Divider()
                    List(selection: $selection) {
                        ForEach(filtered) { pad in
                            PadRow(pad: pad, isChanged: PadListLogic.hasNewActivitySinceOpen(
                                pad, lastOpened: openedStore.lastOpened(pad.id, account: accounts.currentAccountID)))
                                .tag(pad)
                                .contextMenu { padContextMenu(pad) }
                                // Full swipe is allowed because it only opens the
                                // confirmation dialog below — it never deletes
                                // outright, so an accidental swipe is recoverable.
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        padPendingDelete = pad
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.inset)
                    // ↑/↓ move the selection natively; Return opens the selected pad
                    // in the in-app browser (honoring the user's browser preference).
                    .onKeyPress(.return) {
                        guard let selection else { return .ignored }
                        openPad(selection)
                        return .handled
                    }
                    .macPullToRefresh { await reload() }
                    // Scene-scoped, not view-scoped: the Pad menu commands (Copy
                    // Pad ID/URL, Open in Browser) should stay enabled whenever this
                    // window is frontmost and a pad is selected — not only while the
                    // list itself holds keyboard focus. Using `.focusedValue` here
                    // also tripped a "FocusedValue update tried to update multiple
                    // times per frame" fault as the list took focus on first render.
                    .focusedSceneValue(\.focusedPad, selection)
                }
            }
        }
        .focusedSceneValue(\.findAction, FindAction(id: "pads") { searchFieldFocused = true })
        .toolbar(id: "pads.toolbar") {
            ToolbarItem(id: "reload") {
                ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
            }
            if #available(macOS 26, *) {
                ToolbarSpacer(.fixed)
            }
            ToolbarItem(id: "new", placement: .primaryAction) {
                Button { showCreate = true } label: {
                    Label("New Pad", systemImage: "plus")
                }
                .help("Create a new pad (⌘N)")
                .accessibilityLabel("New Pad")
                .disabled(client.apiKey.isEmpty)
            }
            ToolbarItem(id: "bulk") {
                Menu {
                    Button("End Started Pads…", systemImage: "flag.checkered") {
                        bulkAction = .endStarted
                    }
                    .disabled(PadListLogic.startedPads(in: filtered).isEmpty)
                    Button("Make Visible Pads Private…", systemImage: "lock") {
                        bulkAction = .makePrivate
                    }
                    .disabled(PadListLogic.nonPrivatePads(in: filtered).isEmpty)
                } label: {
                    Label("Bulk Actions", systemImage: "ellipsis.circle")
                }
                .help("Apply an action to all pads currently shown in the list")
                .disabled(client.apiKey.isEmpty || filtered.isEmpty || isBulkRunning)
            }
        }
    }

    /// Right-click actions for a pad row. These are the quick, self-contained
    /// operations (open, copy, share, narrow the list); the destructive lifecycle
    /// actions stay behind the detail view's confirmations, reached by selecting
    /// the pad first.
    @ViewBuilder
    private func padContextMenu(_ pad: Pad) -> some View {
        Button {
            selection = pad
            openPad(pad)
        } label: {
            Label("Open Pad", systemImage: "doc.text.image")
        }
        if let url = pad.webURL {
            ShareLink(item: url) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
        }
        Divider()
        Button {
            copyToPasteboard(pad.id)
        } label: {
            Label("Copy Pad ID", systemImage: "number")
        }
        Button {
            copyToPasteboard(pad.url)
        } label: {
            Label("Copy Pad URL", systemImage: "link")
        }
        Divider()
        Button {
            ownerFilter = pad.ownerEmail
        } label: {
            Label("Show Pads from \(directory.display(pad.ownerEmail))", systemImage: "person")
        }
    }

    /// Open a pad honoring the user's browser preference: externally when chosen,
    /// otherwise in a dedicated in-app browser window. The list has no inline
    /// browser pane of its own, so the in-app case opens a separate window —
    /// matching the "Open Pad in Browser" menu command.
    private func openPad(_ pad: Pad) {
        guard let url = pad.webURL else { return }
        if BrowserSettings.openLinksIn == .external {
            BrowserSettings.openExternally(url)
        } else {
            openWindow(id: "pad-browser", value: url)
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Built-in chips shown ahead of the user's saved searches. "My Pads" appears
    /// only when the account knows its user's email; "Active" filters to in-progress
    /// sessions (the API's "started" state).
    private var defaultSearches: [DefaultSearch] {
        var result: [DefaultSearch] = []
        if let me = accounts.currentAccount?.userEmail, !me.isEmpty {
            result.append(DefaultSearch(id: "my-pads", icon: "person.fill",
                                        search: NamedSearch(name: "My Pads", ownerFilter: me)))
        }
        result.append(DefaultSearch(id: "active", icon: "bolt.fill",
                                    search: NamedSearch(name: "Active", stateFilter: .active)))
        return result
    }

    @ViewBuilder
    private var savedSearchesBar: some View {
        let saved = savedSearches.searches(account: accounts.currentAccountID, kind: .pads)
        let defaults = defaultSearches
        if !defaults.isEmpty || !saved.isEmpty {
            // A wrapping flow layout rather than a horizontal scroll, so the chips
            // reflow onto extra lines as the pane narrows instead of clipping a
            // long saved-search name off the trailing edge.
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(defaults) { item in
                    SavedSearchChip(name: item.search.name, systemImage: item.icon,
                                    isActive: isActiveSearch(item.search)) {
                        apply(item.search)
                    }
                }
                ForEach(saved) { item in
                    SavedSearchChip(name: item.name, isActive: isActiveSearch(item)) {
                        apply(item)
                    } onDelete: {
                        if let account = accounts.currentAccountID {
                            savedSearches.remove(id: item.id, account: account, kind: .pads)
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 6)
        }
    }

    private func apply(_ saved: NamedSearch) {
        search = saved.search
        stateFilter = saved.stateFilter
        languageFilter = saved.languageFilter
        ownerFilter = saved.ownerFilter
        teamFilter = saved.teamFilter
        typeFilter = saved.typeFilter
        dateRangeFilter = saved.dateRangeFilter
    }

    /// Whether the list's live filters exactly match `saved`, so its chip can show
    /// as active. This is the inverse of `apply` — every field it sets is compared
    /// here — which keeps the highlight honest the instant any filter is changed.
    private func isActiveSearch(_ saved: NamedSearch) -> Bool {
        search == saved.search &&
        stateFilter == saved.stateFilter &&
        languageFilter == saved.languageFilter &&
        ownerFilter == saved.ownerFilter &&
        teamFilter == saved.teamFilter &&
        typeFilter == saved.typeFilter &&
        dateRangeFilter == saved.dateRangeFilter
    }

    private func captureCurrentSearch(named name: String) -> NamedSearch {
        NamedSearch(
            name: name, search: search,
            stateFilter: stateFilter, languageFilter: languageFilter,
            ownerFilter: ownerFilter, teamFilter: teamFilter,
            typeFilter: typeFilter, dateRangeFilter: dateRangeFilter
        )
    }

    @ViewBuilder
    private var filterBar: some View {
        // A wrapping flow layout rather than a horizontal scroll, so the chips
        // reflow onto extra lines as the pane narrows instead of forcing a wide
        // minimum column width. Each chip reports its own width; because
        // `FilterBarWidthKey` reduces by `max`, the column floor becomes the
        // widest single chip, letting the pane be dragged much thinner.
        FlowLayout(spacing: 8, lineSpacing: 8) {
            FilterChipMenu(
                title: "State",
                icon: "circle.fill",
                selected: $stateFilter,
                options: availableStates,
                formatter: { $0.label }
            )
            .measuresFilterBarWidth()
            FilterChipMenu(
                title: "Language",
                icon: "chevron.left.slash.chevron.right",
                selected: $languageFilter,
                options: availableLanguages,
                formatter: { $0.languageDisplayName }
            )
            .measuresFilterBarWidth()
            SearchableFilterChip(
                title: "Owner",
                icon: "person",
                selected: $ownerFilter,
                options: availableOwners,
                formatter: { directory.display($0) },
                meEmail: accounts.currentAccount?.userEmail
            )
            .measuresFilterBarWidth()
            FilterChipMenu(
                title: "Team",
                icon: "person.3",
                selected: $teamFilter,
                options: availableTeams,
                formatter: { $0 }
            )
            .measuresFilterBarWidth()
            FilterChipMenu(
                title: "Type",
                icon: "tag",
                selected: $typeFilter,
                options: InterviewType.allCases.map(\.rawValue),
                formatter: { InterviewType(rawValue: $0)?.label ?? $0.capitalized }
            )
            .measuresFilterBarWidth()
            FilterChipMenu(
                title: "Updated",
                icon: "calendar",
                selected: $dateRangeFilter,
                options: Self.dateRangeOptions,
                formatter: { $0.capitalized }
            )
            .measuresFilterBarWidth()
            if activeFilterCount > 0 || !search.isEmpty {
                Button {
                    saveSearchName = ""
                    showSaveSearch = true
                } label: {
                    Label("Save…", systemImage: "bookmark")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            if activeFilterCount > 0 {
                Button(role: .destructive) {
                    stateFilter = nil; languageFilter = nil
                    ownerFilter = nil; teamFilter = nil; typeFilter = nil
                    dateRangeFilter = nil
                } label: {
                    Label("Clear", systemImage: "xmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reload() async {
        guard !client.apiKey.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            // Render page 1 the moment it lands, then keep growing the list as the
            // remaining pages stream in. Snapshots arrive sorted updated_at,desc from the
            // server, so each one only appends below — no reshuffle as the list fills in.
            let isInitialLoad = pads.isEmpty
            var fetched: [Pad] = []
            for try await snapshot in client.listPadsIncrementally() {
                // The first snapshot is page 1 — the most-recently-updated pads, already
                // usable. Drop the blocking spinner now and let the rest stream in
                // silently behind the already-visible list, rather than spinning until
                // the last page lands.
                if isLoading {
                    isLoading = false
                }
                fetched = snapshot
                // Paint progressively on the first load; on a refresh keep the current
                // list until the full result is in, so a later page failing can't
                // transiently shrink the visible list to just page 1.
                if isInitialLoad {
                    pads = snapshot
                }
            }
            pads = fetched
            // Finalize diff + cache against the complete list, once.
            var changes: Set<String> = []
            if hasLoadedOnce {
                for pad in fetched {
                    if let prev = previousUpdatedAt[pad.id] {
                        if let updated = pad.updatedAt, updated > prev {
                            changes.insert(pad.id)
                        }
                    } else {
                        changes.insert(pad.id)
                    }
                }
            }
            PadActivityMonitor.shared.record(changedCount: changes.count)
            var nextState: [String: Date] = [:]
            for pad in fetched {
                if let updated = pad.updatedAt { nextState[pad.id] = updated }
            }
            previousUpdatedAt = nextState
            if let id = accounts.currentAccountID {
                cache.set(id, pads: fetched)
            }
            hasLoadedOnce = true
        } catch {
            self.error = error
        }
    }
}

private struct TaskKey: Hashable {
    let apiKey: String
    let phase: ScenePhase
}

struct FilterChipMenu<Option: Hashable>: View {
    let title: String
    let icon: String
    @Binding var selected: Option?
    let options: [Option]
    let formatter: (Option) -> String

    // Match SearchableFilterChip's selected/idle styling so a set filter always
    // shows the accent capsule. Idle is transparent; a selection paints the same
    // accent fill, stroke, and text colour the Owner chip uses.
    private var isActive: Bool { selected != nil }
    private var fillColor: Color { isActive ? Color.accentColor.opacity(0.18) : Color.clear }
    private var strokeColor: Color { isActive ? Color.accentColor.opacity(0.4) : Color.clear }
    private var labelColor: Color { isActive ? Color.accentColor : Color.primary }

    var body: some View {
        Menu {
            Button("All") { selected = nil }
            if !options.isEmpty { Divider() }
            ForEach(options, id: \.self) { option in
                Button {
                    selected = option
                } label: {
                    if option == selected {
                        Label(formatter(option), systemImage: "checkmark")
                    } else {
                        Text(formatter(option))
                    }
                }
            }
        } label: {
            // `.borderlessButton` discarded the label's custom capsule (selected
            // chips rendered as plain text). A `.button` menu style with the plain
            // button style draws the ChipLabel verbatim, so the accent fill shows.
            ChipLabel(
                title: title,
                icon: icon,
                text: selected.map(formatter) ?? title,
                fillColor: fillColor,
                strokeColor: strokeColor,
                labelColor: labelColor
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(options.isEmpty)
    }
}

/// A built-in saved search shown as a chip ahead of the user's own. Defaults
/// aren't persisted or deletable — they're recomputed per account so "My Pads"
/// and "My Questions" track whoever is signed in.
struct DefaultSearch: Identifiable {
    let id: String
    let icon: String
    let search: NamedSearch
}

struct SavedSearchChip: View {
    let name: String
    var systemImage: String = "bookmark.fill"
    /// True while the list's current filters exactly match this search — set the
    /// moment it's applied and cleared as soon as any filter is changed. Derived by
    /// the parent from filter state rather than stored, so it can never drift.
    var isActive: Bool = false
    let onApply: () -> Void
    /// Omitted for the built-in defaults, which can't be deleted.
    var onDelete: (() -> Void)? = nil

    @State private var hovered = false

    // Saved searches are *recall* buttons, not state: tapping one launches a set
    // of filters rather than toggling a value. They stay neutral until applied, at
    // which point the accent capsule marks "you are here" — the same accent the
    // active filter chips use (see FilterChipMenu) — until a filter is modified.
    private var fillStyle: AnyShapeStyle {
        if isActive { return AnyShapeStyle(Color.accentColor.opacity(0.16)) }
        return hovered ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary)
    }
    private var strokeColor: Color {
        isActive ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08)
    }
    private var contentColor: AnyShapeStyle {
        isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary)
    }

    /// New names are capped on save, but names persisted before the cap (or any
    /// odd multi-line paste) could still be unbounded. Clamp to the same limit
    /// with a trailing ellipsis so no single chip overflows the bar; the full name
    /// stays in the accessibility label below.
    private var displayName: String {
        guard name.count > NamedSearch.maxNameLength else { return name }
        return String(name.prefix(NamedSearch.maxNameLength - 1)) + "…"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            Text(displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(contentColor)
                .lineLimit(1)
            if let onDelete {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete saved search \(name)")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(fillStyle, in: Capsule())
        .overlay(Capsule().strokeBorder(strokeColor, lineWidth: 0.5))
        .contentShape(Capsule())
        .onTapGesture { onApply() }
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("Apply saved search \(name)")
    }
}

private struct PadRow: View {
    let pad: Pad
    var isChanged: Bool = false
    @Environment(\.orgDirectory) private var directory

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                AvatarCircle(label: directory.display(pad.ownerEmail), diameter: 30)
                if isChanged {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Color.cardBackground, lineWidth: 2))
                        .offset(x: 2, y: -2)
                        .help("Updated since last refresh")
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(pad.title.isEmpty ? pad.id : pad.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    StateBadge(state: pad.status)
                    if let language = pad.language, !language.isEmpty {
                        Chip(text: language.languageDisplayName, systemImage: language.languageSymbol,
                             tint: language.languageColor)
                    }
                    if pad.interviewType == .takeHome {
                        InterviewType.takeHome.chip
                    }
                }
                Text(directory.display(pad.ownerEmail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let updated = pad.informativeUpdatedAt {
                    Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        // Read the whole row as one VoiceOver element with a coherent label,
        // rather than stopping on each badge/label separately. The "changed"
        // indicator is a color-only dot, so fold it into the label as well.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [pad.title.isEmpty ? pad.id : pad.title, pad.status.label]
        if let language = pad.language, !language.isEmpty {
            parts.append(language.languageDisplayName)
        }
        if pad.interviewType == .takeHome { parts.append("Take-home") }
        parts.append(directory.display(pad.ownerEmail))
        if let updated = pad.informativeUpdatedAt {
            parts.append("updated \(updated.formatted(.relative(presentation: .named)))")
        }
        if isChanged { parts.append("recently updated") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Detail

struct PadDetailView: View {
    let client: CoderPadClient
    let pad: Pad
    @State private var events: [PadEvent] = []
    @State private var environments: [PadEnvironment] = []
    @State private var loadError: Error?
    @State private var isLoading = false
    @State private var showEdit = false
    @State private var browserURL: URL?
    @State private var showEndConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isMutating = false
    @State private var mutateError: String?
    @State private var nav = AppNavigation.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.orgDirectory) private var directory
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
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
        .navigationTitle(pad.title.isEmpty ? pad.id : pad.title)
        // Detail-column actions live in the unified window toolbar rather than in
        // the content header: there they float on the system Liquid Glass layer
        // automatically, and the header stays free for identity and metadata. A
        // leading spacer separates them from the Pads list's own toolbar items
        // (Reload, New Pad). The lifecycle/destructive actions (Save Code, End
        // Interview, Delete Pad) sit in their own trailing group behind a second
        // spacer; End Interview and Delete Pad each still require a confirmation
        // dialog, so surfacing them directly can't trigger an irreversible action
        // from a stray click.
        .toolbar(id: "pad.detail.toolbar") {
            if #available(macOS 26, *) {
                ToolbarSpacer(.fixed)
            }
            ToolbarItem(id: "editPad", placement: .primaryAction) {
                Button { showEdit = true } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .help("Edit pad properties")
            }
            if let url = pad.webURL {
                ToolbarItem(id: "sharePad", placement: .primaryAction) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .help("Share pad")
                    .accessibilityLabel("Share pad")
                }
                ToolbarItem(id: "openPad", placement: .primaryAction) {
                    Button {
                        if BrowserSettings.openLinksIn == .external {
                            BrowserSettings.openExternally(url)
                        } else {
                            browserURL = url
                        }
                    } label: {
                        Label("Open Pad", systemImage: "doc.text.image")
                    }
                    .help("Open the pad")
                }
            }
            if #available(macOS 26, *) {
                ToolbarSpacer(.fixed)
            }
            ToolbarItem(id: "saveCode", placement: .primaryAction) {
                Button {
                    saveCodeLocally()
                } label: {
                    Label("Save Code…", systemImage: "square.and.arrow.down")
                }
                .disabled(!hasSavableCode)
                .help("Save the pad's code to a file or folder on this Mac")
            }
            ToolbarItem(id: "endInterview", placement: .primaryAction) {
                Button {
                    showEndConfirm = true
                } label: {
                    Label("End Interview", systemImage: "flag.checkered")
                }
                .disabled(isEnded || isMutating)
                .help("End the interview for all participants")
            }
            ToolbarItem(id: "deletePad", placement: .primaryAction) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Pad", systemImage: "trash")
                }
                .disabled(isMutating)
                .help("Delete this pad")
            }
        }
        .task(id: pad.id) { await load() }
        .sheet(isPresented: $showEdit) {
            EditPadSheet(
                client: client,
                original: pad,
                onSaved: { updated in
                    NotificationCenter.default.post(name: .padUpdated, object: updated)
                    showEdit = false
                },
                onCancel: { showEdit = false }
            )
        }
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
        .alert("Action failed", isPresented: .init(get: { mutateError != nil }, set: { if !$0 { mutateError = nil } })) {
            Button("OK", role: .cancel) { mutateError = nil }
        } message: {
            Text(mutateError ?? "")
        }
        .onAppear {
            consumePendingEdit()
            consumePendingEnd()
            consumePendingDelete()
        }
        .onChange(of: nav.editPadID) { _, _ in consumePendingEdit() }
        .onChange(of: nav.endPadID) { _, _ in consumePendingEnd() }
        .onChange(of: nav.deletePadID) { _, _ in consumePendingDelete() }
    }

    /// Honors an "Edit Pad" request routed via `AppNavigation` from the Pad menu
    /// command by presenting the same edit sheet as the in-pane Edit button.
    private func consumePendingEdit() {
        guard nav.editPadID == pad.id else { return }
        nav.editPadID = nil
        showEdit = true
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

    private var isEnded: Bool {
        pad.isEnded
    }

    private func endInterview() async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await client.endPad(id: pad.id)
            // Refresh so the ended state/timestamp propagate to the list and detail.
            if let updated = try? await client.getPad(id: pad.id) {
                NotificationCenter.default.post(name: .padUpdated, object: updated)
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
            NotificationCenter.default.post(name: .padDeleted, object: pad.id)
        } catch {
            mutateError = error.localizedDescription
        }
    }

    // MARK: - Save code locally

    /// One file to write to disk, with a relative path that preserves any
    /// project folder structure (e.g. `src/main.rs`) so multi-file pads round-trip.
    private struct SavableFile {
        let relativePath: String
        let contents: String
    }

    /// Whether there is any code to save yet. Environments load asynchronously,
    /// so this stays false (disabling the menu item) until at least one carries
    /// files — or, for a legacy pad, until its inline `contents` is available.
    private var hasSavableCode: Bool {
        if environments.contains(where: { !displayFiles(for: $0).isEmpty }) { return true }
        return !(pad.contents ?? "").isEmpty
    }

    /// The pad's title, falling back to its ID, used to name the saved file or
    /// folder. Never empty.
    private var suggestedBaseName: String {
        let title = pad.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? pad.id : title
    }

    /// Every file the detail view renders, flattened for saving. When several
    /// environments carry code, each is namespaced into its own subfolder so
    /// identically-named files (a candidate and a reference `main.py`) don't
    /// overwrite each other. Falls back to the legacy inline `contents` when no
    /// environment provided any files.
    private func savableFiles() -> [SavableFile] {
        let envs = environments.filter { !displayFiles(for: $0).isEmpty }
        let namespacePerEnvironment = envs.count > 1
        var result: [SavableFile] = []
        for (index, env) in envs.enumerated() {
            let prefix: String
            if namespacePerEnvironment {
                let label = env.language.flatMap { $0.isEmpty ? nil : $0 } ?? "environment"
                prefix = "\(Self.sanitizeComponent(label))-\(index + 1)/"
            } else {
                prefix = ""
            }
            for file in displayFiles(for: env) {
                result.append(SavableFile(relativePath: prefix + Self.relativePath(for: file),
                                          contents: file.contents))
            }
        }
        if result.isEmpty, let contents = pad.contents, !contents.isEmpty {
            let ext = Self.fileExtension(forLanguage: pad.language)
            result.append(SavableFile(relativePath: "\(Self.sanitizeComponent(suggestedBaseName)).\(ext)",
                                      contents: contents))
        }
        return result
    }

    /// Prompts for a destination and writes the pad's code there. A single file
    /// uses a save panel (the user names the file); multiple files use a folder
    /// chooser, then write into a subfolder named after the pad with their
    /// project structure intact.
    private func saveCodeLocally() {
        let files = savableFiles()
        guard !files.isEmpty else {
            mutateError = "This pad has no code to save."
            return
        }
        do {
            if files.count == 1 {
                let panel = NSSavePanel()
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = (files[0].relativePath as NSString).lastPathComponent
                panel.message = "Save the code from \"\(suggestedBaseName)\""
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try files[0].contents.write(to: url, atomically: true, encoding: .utf8)
            } else {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = "Save"
                panel.message = "Choose where to save the \(files.count) files from \"\(suggestedBaseName)\""
                guard panel.runModal() == .OK, let directory = panel.url else { return }
                let root = directory.appending(path: Self.sanitizeComponent(suggestedBaseName))
                let fileManager = FileManager.default
                for file in files {
                    let destination = root.appending(path: file.relativePath)
                    try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
                    try file.contents.write(to: destination, atomically: true, encoding: .utf8)
                }
            }
        } catch {
            mutateError = error.localizedDescription
        }
    }

    /// A file's path with each component made filesystem-safe, preserving the
    /// `/` separators so folder structure survives. Drops empty and `.`/`..`
    /// components so a malformed path can't escape the destination folder.
    private static func relativePath(for file: CodeFile) -> String {
        if let path = file.path, !path.isEmpty {
            let components = path.split(separator: "/")
                .map(String.init)
                .filter { $0 != "." && $0 != ".." }
                .map { sanitizeComponent($0) }
                .filter { !$0.isEmpty }
            if !components.isEmpty {
                return components.joined(separator: "/")
            }
        }
        return "untitled-\(file.id).\(fileExtension(forLanguage: file.language))"
    }

    /// Replaces characters that are unsafe in a single path component, so a pad
    /// title or file name can't break out of its folder or confuse the shell.
    private static func sanitizeComponent(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "untitled" : cleaned
    }

    /// A reasonable file extension for code that has no path of its own (a
    /// legacy single-file pad), derived from its language.
    private static func fileExtension(forLanguage language: String?) -> String {
        var lowered = (language ?? "").lowercased()
        if lowered.hasPrefix("multifile_") {
            lowered = String(lowered.dropFirst("multifile_".count))
        }
        switch lowered {
        case "python", "python2", "python3": return "py"
        case "javascript", "node", "node.js", "nodejs": return "js"
        case "typescript": return "ts"
        case "swift": return "swift"
        case "go", "golang": return "go"
        case "rust": return "rs"
        case "java": return "java"
        case "kotlin": return "kt"
        case "scala": return "scala"
        case "ruby": return "rb"
        case "c": return "c"
        case "cpp", "c++": return "cpp"
        case "csharp", "c#": return "cs"
        case "objective-c", "objc": return "m"
        case "php": return "php"
        case "html": return "html"
        case "css": return "css"
        case "sql", "mysql", "postgresql", "postgres": return "sql"
        case "bash", "shell", "sh": return "sh"
        case "r": return "r"
        case "elixir": return "ex"
        case "erlang": return "erl"
        case "haskell": return "hs"
        case "perl": return "pl"
        case "lua": return "lua"
        case "dart": return "dart"
        case "clojure": return "clj"
        case "ocaml": return "ml"
        case "f#", "fsharp": return "fs"
        default: return "txt"
        }
    }

    private var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metaCards
                if !pad.participants.isEmpty {
                    participantsCard
                }
                // One code card per environment. A pad can carry several
                // environments (e.g. a candidate and reference solution, or
                // multiple languages); showing only the active one silently hid
                // the rest. Each card is identified by its language chip and
                // flags the active one, so no separate environments list is
                // needed to tell them apart.
                ForEach(environments) { env in
                    let files = displayFiles(for: env)
                    if !files.isEmpty {
                        EnvironmentCodeCard(
                            files: files,
                            isActive: env.id == pad.activeEnvironmentID,
                            showActiveBadge: environments.count > 1,
                            language: env.language,
                            padID: pad.id,
                            dark: colorScheme == .dark
                        )
                    }
                }
                if whiteboardURL != nil {
                    whiteboardCard
                }
                eventsCard
            }
            .padding(.horizontal, Spacing.paneH)
            .padding(.top, Spacing.paneV)
            .padding(.bottom, Spacing.paneV)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Actions now live in the window toolbar, so the header only carries
            // identity, the metadata chips, and the raw ID below.
            identity
            HStack(spacing: 6) {
                StateBadge(state: pad.status)
                // Skip the pad-level language chip when a single code card is
                // shown — that card names the language itself, so repeating it
                // here is redundant. Keep it when there's no card (nothing else
                // names the language) or several (this summarizes the active one).
                if let language = pad.language, !language.isEmpty, codeCardCount != 1 {
                    Chip(text: language.languageDisplayName, systemImage: language.languageSymbol,
                         tint: language.languageColor)
                }
                if let type = pad.interviewType {
                    type.chip
                }
                if pad.isPrivate == true {
                    Chip(text: "Private", systemImage: "lock", tint: .orange)
                }
                if let exec = pad.executionEnabled, exec {
                    Chip(text: "Execution enabled", systemImage: "play.circle", tint: .green)
                }
                if let team = pad.team {
                    Chip(text: team.name, systemImage: "person.3", tint: .purple)
                }
            }
        }
    }

    private var identity: some View {
        HStack(spacing: 12) {
            AvatarCircle(label: directory.display(pad.ownerEmail), diameter: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(pad.title.isEmpty ? "Untitled Pad" : pad.title)
                    .font(.title.bold())
                if let name = directory.name(for: pad.ownerEmail) {
                    Text(name).font(.callout)
                    EmailLink(email: pad.ownerEmail).font(.caption).foregroundStyle(.secondary)
                } else {
                    EmailLink(email: pad.ownerEmail).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var metaCards: some View {
        // An adaptive grid instead of a fixed HStack so the tiles wrap onto a
        // new row when the detail pane is too narrow to fit them side by side.
        // A plain HStack can't shrink the date-bearing tiles below their content
        // width, so it overflowed and the rightmost tile was clipped by the pane
        // edge.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], alignment: .leading, spacing: 12) {
            if let createdAt = pad.createdAt {
                StatTile(title: "Created", value: createdAt.formatted(date: .abbreviated, time: .shortened),
                         systemImage: "calendar.badge.plus", tint: .blue)
            }
            if let updatedAt = pad.informativeUpdatedAt {
                StatTile(title: "Updated", value: updatedAt.formatted(date: .abbreviated, time: .shortened),
                         systemImage: "clock.arrow.circlepath", tint: .teal)
            }
            if let endedAt = pad.endedAt {
                StatTile(title: "Ended", value: endedAt.formatted(date: .abbreviated, time: .shortened),
                         systemImage: "flag.checkered", tint: .gray)
            }
            if let url = pad.playbackURL {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Playback", systemImage: "play.rectangle")
                        Button("Watch") {
                            if BrowserSettings.openLinksIn == .external {
                                BrowserSettings.openExternally(url)
                            } else {
                                browserURL = url
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .font(.title3.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // The API returns participants as a flat list of names with no role, so we
    // infer who's who from the org directory: a participant whose name matches an
    // org member is an interviewer, and anyone else is the candidate. When the
    // directory hasn't loaded we can't tell them apart, so we fall back to an
    // unlabeled list rather than guess.
    private var participantRoles: (interviewers: [String], candidates: [String])? {
        let memberNames = Set(directory.nameByEmail.values.map { $0.lowercased() })
        guard !memberNames.isEmpty else { return nil }
        var interviewers: [String] = []
        var candidates: [String] = []
        for name in pad.participants {
            if memberNames.contains(name.lowercased()) {
                interviewers.append(name)
            } else {
                candidates.append(name)
            }
        }
        return (interviewers, candidates)
    }

    private var participantsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Participants", systemImage: "person.2")
                if let roles = participantRoles {
                    if !roles.candidates.isEmpty {
                        participantGroup(
                            title: roles.candidates.count == 1 ? "Candidate" : "Candidates",
                            systemImage: "person.crop.circle.badge.questionmark",
                            names: roles.candidates, tint: .blue)
                    }
                    if !roles.interviewers.isEmpty {
                        participantGroup(
                            title: roles.interviewers.count == 1 ? "Interviewer" : "Interviewers",
                            systemImage: "person.crop.circle.badge.checkmark",
                            names: roles.interviewers, tint: .purple)
                    }
                } else {
                    participantGrid(names: pad.participants, tint: .purple)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func participantGroup(title: String, systemImage: String, names: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            participantGrid(names: names, tint: tint)
        }
    }

    private func participantGrid(names: [String], tint: Color) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(names, id: \.self) { name in
                HStack(spacing: 8) {
                    AvatarCircle(label: name, diameter: 26, tint: tint)
                    Text(name).font(.callout)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.subtleStroke.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    /// The pad's whiteboard drawing, when it has one. Parsed once so the card and
    /// its visibility check agree on whether there's anything to show.
    private var whiteboardURL: URL? {
        guard let drawing = pad.drawing, !drawing.isEmpty else { return nil }
        return URL(string: drawing)
    }

    /// The whiteboard sketch from the interview, rendered inline. Tapping it opens
    /// the full-size image, honouring the same in-app/external preference as the
    /// pad and playback links.
    private var whiteboardCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Whiteboard", systemImage: "scribble.variable")
                if let url = whiteboardURL {
                    Button {
                        openExternalOrInApp(url)
                    } label: {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ZStack {
                                    Color.subtleStroke
                                    ProgressView().controlSize(.small)
                                }
                                .frame(height: 180)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                            case .failure:
                                ZStack {
                                    Color.subtleStroke
                                    Label("Couldn’t load whiteboard", systemImage: "photo")
                                        .foregroundStyle(.secondary)
                                        .font(.callout)
                                }
                                .frame(height: 120)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.subtleStroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Open the whiteboard full size")
                    .accessibilityLabel("Open the whiteboard full size")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Open a URL the same way the pad and playback links do: in the default
    /// browser or the in-pane web view, per the user's preference.
    private func openExternalOrInApp(_ url: URL) {
        if BrowserSettings.openLinksIn == .external {
            BrowserSettings.openExternally(url)
        } else {
            browserURL = url
        }
    }

    private var eventsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Events", systemImage: "list.bullet.rectangle")
                    Spacer()
                    if isLoading {
                        ProgressView().controlSize(.small)
                    }
                }
                if let loadError {
                    Label(loadError.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                } else if events.isEmpty && !isLoading {
                    Text("No events yet.").foregroundStyle(.secondary).font(.callout)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(groupedEvents) { group in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: icon(for: group.representative.kind))
                                    .foregroundStyle(color(for: group.representative.kind))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(group.representative.kind.capitalized)
                                            .font(.callout.weight(.semibold))
                                        if group.count > 1 {
                                            Chip(text: "×\(group.count)", tint: .accentColor)
                                        }
                                        if let name = group.representative.userName, !name.isEmpty {
                                            // Emphasize the most recently-active participant so the
                                            // eye is drawn to whoever acted last in the session.
                                            let isActive = name == activeParticipant
                                            Text("· \(name)")
                                                .font(.callout.weight(isActive ? .semibold : .regular))
                                                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                                        }
                                    }
                                    if let first = group.representative.createdAt {
                                        if group.count > 1, let last = group.lastEvent.createdAt {
                                            Text("\(first.formatted(date: .abbreviated, time: .shortened)) - \(last.formatted(date: .omitted, time: .shortened))")
                                                .font(.caption).foregroundStyle(.tertiary)
                                        } else {
                                            Text(first.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption).foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(accessibilityLabel(for: group))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The non-empty files of an environment, each paired with a language
    /// inferred from its own extension. A multi-file project (e.g. a Django
    /// app) mixes `.py`, `.html`, and `.css`; deriving the language per file
    /// lets each be highlighted correctly instead of forcing the environment's
    /// single language onto all of them.
    /// How many environments actually render a code card (i.e. have files to
    /// show). When exactly one does, that card's own language chip names the
    /// language, so the header chip would just repeat it.
    private var codeCardCount: Int {
        environments.filter { !displayFiles(for: $0).isEmpty }.count
    }

    private func displayFiles(for env: PadEnvironment) -> [CodeFile] {
        env.fileContents.enumerated().compactMap { index, file in
            guard let body = file.contents, !body.isEmpty else { return nil }
            let stableID = file.path.flatMap { $0.isEmpty ? nil : $0 } ?? "idx-\(index)"
            return CodeFile(
                id: stableID,
                path: file.path,
                contents: body,
                language: CodeFile.language(forPath: file.path, fallback: env.language)
            )
        }
    }

    private var groupedEvents: [PadEventGroup] {
        PadEventGrouping.group(events)
    }

    /// The participant who acted most recently in the session. Events are grouped
    /// oldest-first, so the most recent named actor is found by scanning from the
    /// end. Nil when no event carries a user name.
    private var activeParticipant: String? {
        for group in groupedEvents.reversed() {
            if let name = group.lastEvent.userName ?? group.representative.userName, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    private func icon(for kind: String) -> String {
        switch kind.lowercased() {
        case "joined": return "person.fill.badge.plus"
        case "left": return "person.fill.badge.minus"
        case "ended": return "flag.checkered"
        case "started": return "play.fill"
        case "edited", "typed": return "pencil"
        case "ran", "executed": return "play.circle"
        default: return "circle.fill"
        }
    }

    private func color(for kind: String) -> Color {
        switch kind.lowercased() {
        case "joined": return .green
        case "left": return .secondary
        case "ended": return .gray
        case "started": return .blue
        case "ran", "executed": return .orange
        default: return .accentColor
        }
    }

    private func accessibilityLabel(for group: PadEventGroup) -> String {
        var parts = [group.representative.kind]
        if group.count > 1 { parts.append("\(group.count) times") }
        if let user = group.representative.userName, !user.isEmpty { parts.append("by \(user)") }
        if let when = group.representative.createdAt {
            parts.append("at \(when.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: " ")
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            async let events = client.padEvents(padID: pad.id)
            async let envs = loadEnvironments()
            // The API returns events newest-first; display them oldest-first so the
            // log reads top-to-bottom in chronological order (and so the grouping
            // logic, which collapses consecutive same-kind events into an
            // earliest–latest range, stays correct).
            self.events = try await events.sorted {
                ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
            }
            self.environments = await envs
        } catch {
            loadError = error
        }
    }

    private func loadEnvironments() async -> [PadEnvironment] {
        var result: [PadEnvironment] = []
        for id in pad.padEnvironmentIDs {
            if let env = try? await client.padEnvironment(id: id) {
                result.append(env)
            }
        }
        return result
    }
}

// MARK: - Code preview

/// One displayable file in an environment's code preview, carrying the
/// language used to highlight it (derived from the file's own extension, with
/// the environment language as a fallback).
private struct CodeFile: Identifiable, Hashable {
    /// A stable identifier derived from the file's path (not its array position), so a
    /// reload that reorders or changes the environment's files doesn't silently remap
    /// which file a retained selection points at.
    let id: String
    let path: String?
    let contents: String
    let language: String?

    /// The file's name without its directory, for compact tab labels.
    var name: String {
        guard let path, !path.isEmpty else { return "untitled" }
        return path.split(separator: "/").last.map(String.init) ?? path
    }

    /// Strips CoderPad's `multifile_` prefix so the environment language can
    /// stand in for a file that has no recognised extension.
    private static func baseLanguage(_ language: String?) -> String? {
        guard let language else { return nil }
        let lowered = language.lowercased()
        if lowered.hasPrefix("multifile_") {
            return String(lowered.dropFirst("multifile_".count))
        }
        return language
    }

    /// Maps a file extension to a CoderPad language code the highlighter
    /// understands, falling back to the environment language when the
    /// extension is missing or unrecognised.
    static func language(forPath path: String?, fallback: String?) -> String? {
        guard let path, let dot = path.lastIndex(of: "."), dot < path.index(before: path.endIndex) else {
            return baseLanguage(fallback)
        }
        switch path[path.index(after: dot)...].lowercased() {
        case "py": return "python"
        case "js", "jsx", "mjs", "cjs": return "javascript"
        case "ts", "tsx": return "typescript"
        case "swift": return "swift"
        case "go": return "go"
        case "rs": return "rust"
        case "java": return "java"
        case "kt", "kts": return "kotlin"
        case "scala", "sc": return "scala"
        case "rb": return "ruby"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp", "hh": return "cpp"
        case "cs": return "csharp"
        case "m", "mm": return "objective-c"
        case "php": return "php"
        case "r": return "r"
        case "sql": return "sql"
        case "sh", "bash": return "bash"
        case "ex", "exs": return "elixir"
        case "erl", "hrl": return "erlang"
        case "hs": return "haskell"
        case "pl", "pm": return "perl"
        case "lua": return "lua"
        case "dart": return "dart"
        case "clj", "cljs", "cljc": return "clojure"
        case "ml", "mli": return "ocaml"
        case "fs", "fsx": return "fsharp"
        case "html", "htm": return "html"
        case "css": return "css"
        case "txt", "md", "markdown": return "plaintext"
        default: return baseLanguage(fallback)
        }
    }
}

/// A code card for one environment. Single-file environments render exactly as
/// before — a single highlighted scroll. Multi-file environments gain a row of
/// file tabs and a per-file path header, so the files no longer run together
/// in one concatenated blob and each is highlighted in its own language.
private struct EnvironmentCodeCard: View {
    let files: [CodeFile]
    let isActive: Bool
    /// Whether to flag the active environment. Only meaningful when a pad has
    /// several environments; with a single one the active flag says nothing.
    let showActiveBadge: Bool
    /// The environment-level language, shown as a chip (e.g. "Python Project").
    let language: String?
    let padID: String
    let dark: Bool

    /// The files arranged into a folder tree by their paths, folders before
    /// files and each group sorted by name. Built once in `init` rather than on
    /// every `body` pass so dragging the sidebar handle (which re-evaluates
    /// `body` each frame) doesn't re-run the recursive grouping and sorting.
    private let fileTree: [FileTreeNode]

    init(
        files: [CodeFile],
        isActive: Bool,
        showActiveBadge: Bool,
        language: String?,
        padID: String,
        dark: Bool
    ) {
        self.files = files
        self.isActive = isActive
        self.showActiveBadge = showActiveBadge
        self.language = language
        self.padID = padID
        self.dark = dark
        self.fileTree = Self.makeFileTree(from: files)
    }

    @State private var selectedFileID: String?
    /// Folder paths the user has collapsed. Absence means expanded, so every
    /// folder starts open and the whole project is visible by default.
    @State private var collapsedFolders: Set<String> = []
    /// The persisted file sidebar width. The user can drag the divider to resize
    /// it (see `resizeHandle`); a wider sidebar reveals long file names that would
    /// otherwise truncate. Stored so the chosen width sticks across launches, and
    /// shared by every code card so they stay aligned. The panes only ever render
    /// at this width — a drag previews with a lightweight indicator and commits
    /// here on release (see `resizeHandle`), so no heavy relayout runs mid-drag.
    @AppStorage("padFileSidebarWidth") private var storedWidth: Double = 180
    /// The previewed width while a resize drag is in progress, or `nil` when not
    /// dragging. Only a thin indicator line follows this; the actual sidebar keeps
    /// its committed `storedWidth` until the drag ends, so dragging never forces
    /// the code pane (a selectable, syntax-highlighted scroll view that is costly
    /// to re-lay-out) to reflow on every frame — the source of the stutter.
    @State private var liveWidth: Double?

    private var selected: CodeFile {
        files.first { $0.id == selectedFileID } ?? files[0]
    }

    private var isMultiFile: Bool { files.count > 1 }

    /// Builds the folder tree from a flat file list. Pure and static so it can run
    /// once at `init` time.
    private static func makeFileTree(from files: [CodeFile]) -> [FileTreeNode] {
        let entries = files.map { file -> (segments: [String], file: CodeFile) in
            let path = file.path ?? file.name
            let segments = path.split(separator: "/")
                .map(String.init)
                .filter { $0 != "." && $0 != ".." }
            return (segments.isEmpty ? [file.name] : segments, file)
        }
        return makeNodes(entries: entries, prefix: "")
    }

    private static func makeNodes(
        entries: [(segments: [String], file: CodeFile)],
        prefix: String
    ) -> [FileTreeNode] {
        var folderOrder: [String] = []
        var groups: [String: [(segments: [String], file: CodeFile)]] = [:]
        var leaves: [(name: String, file: CodeFile)] = []

        for entry in entries {
            if entry.segments.count <= 1 {
                leaves.append((entry.segments.first ?? entry.file.name, entry.file))
            } else {
                let head = entry.segments[0]
                if groups[head] == nil {
                    groups[head] = []
                    folderOrder.append(head)
                }
                groups[head]?.append((Array(entry.segments.dropFirst()), entry.file))
            }
        }

        var nodes: [FileTreeNode] = []
        for folder in folderOrder.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            let childPrefix = prefix.isEmpty ? folder : prefix + "/" + folder
            let children = makeNodes(entries: groups[folder] ?? [], prefix: childPrefix)
            nodes.append(FileTreeNode(id: "folder:" + childPrefix, name: folder, file: nil, children: children))
        }
        for leaf in leaves.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            nodes.append(FileTreeNode(id: "file:\(leaf.file.id)", name: leaf.name, file: leaf.file, children: []))
        }
        return nodes
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // When the environment's files change (added/removed/renamed — ids are
        // path-based), clear the retained selection so `selected` falls back to the
        // first file rather than pointing at a stale or wrong file. An in-place
        // contents update keeps the same ids, so the selection survives it.
        .onChange(of: files.map(\.id)) { _, _ in
            selectedFileID = nil
        }
    }

    /// Single-file environments render a lone highlighted scroll. Multi-file
    /// environments place a vertical file list beside the code so every file is
    /// visible at once, the way an IDE shows a project, instead of forcing a
    /// long sideways scroll through a row of tabs.
    @ViewBuilder private var content: some View {
        Group {
            if isMultiFile {
                HStack(alignment: .top, spacing: 0) {
                    fileSidebar
                    resizeHandle
                    codeScroll
                }
                // While dragging, a thin accent line previews where the divider
                // will land. The panes themselves don't move until release, so the
                // (expensive) code pane never reflows mid-drag.
                .overlay(alignment: .leading) {
                    if let liveWidth {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                            .offset(x: liveWidth)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                codeScroll
            }
        }
        .background(Color.subtleStroke.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
    }

    private var header: some View {
        HStack {
            SectionHeader(title: "Code", systemImage: "chevron.left.slash.chevron.right")
            // When several environments are stacked, flag the active one so the
            // cards don't blur together. The language chip below names each.
            if showActiveBadge && isActive {
                Chip(text: "Active", systemImage: "checkmark.seal", tint: .green)
            }
            Spacer()
            if let language, !language.isEmpty {
                Chip(text: language.languageDisplayName, tint: language.languageColor)
            }
        }
    }

    /// Floats in the top-right of the code block and copies the selected file.
    private var copyButton: some View {
        Button {
            copy(selected.contents)
        } label: {
            Image(systemName: "doc.on.doc")
                .padding(6)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.subtleStroke, lineWidth: 0.5)
        )
        .help("Copy code")
        .accessibilityLabel("Copy code")
    }

    /// A vertical list of the environment's files, pinned beside the code. It
    /// scrolls independently so even a project with many files stays browsable
    /// without the code pane having to grow.
    private var fileSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                FileTreeRows(
                    nodes: fileTree,
                    depth: 0,
                    selectedID: selected.id,
                    collapsedFolders: $collapsedFolders,
                    onSelect: { selectedFileID = $0 }
                )
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: CGFloat(storedWidth))
    }

    /// The draggable divider between the file list and the code. It draws the
    /// same hairline as a plain `Divider` but carries a wider, invisible hit
    /// target so the resize is easy to grab, and shows the left/right resize
    /// cursor on hover. Dragging only moves a preview line (`liveWidth`); the new
    /// width is committed to `storedWidth` on release so the panes relayout once,
    /// not on every frame.
    private var resizeHandle: some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(width: 10)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Measure each drag from the committed width and
                                // move only the lightweight preview indicator —
                                // the heavy panes stay put until release.
                                let next = storedWidth + Double(value.translation.width)
                                liveWidth = min(max(120, next), 420)
                            }
                            .onEnded { _ in
                                // Commit the previewed width (one relayout) and
                                // clear the preview.
                                if let liveWidth { storedWidth = liveWidth }
                                liveWidth = nil
                            }
                    )
            }
    }

    private var codeScroll: some View {
        // The highlighted code lives in its own `Equatable` view so resizing the
        // sidebar — which re-evaluates this card's `body` every drag frame —
        // doesn't re-run the (expensive) syntax highlighter. It only recomputes
        // when the file contents, language, or appearance actually change.
        HighlightedCode(contents: selected.contents, language: selected.language, dark: dark)
            .equatable()
            .overlay(alignment: .topTrailing) {
                copyButton
                    .padding(8)
            }
    }

    private var accessibilityLabel: String {
        // Name the environment by its language, the same identity shown visually.
        let environmentName = language.flatMap { $0.isEmpty ? nil : $0.languageDisplayName }
        if isMultiFile {
            return "Code preview of \(selected.name)\(environmentName.map { " in \($0)" } ?? "") in pad \(padID)"
        }
        return environmentName.map { "Code preview of \($0) in pad \(padID)" }
            ?? "Code preview of pad \(padID)"
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// The scrollable, syntax-highlighted view of one file's source. Kept separate
/// and `Equatable` so SwiftUI skips re-running the costly highlighter when the
/// enclosing card re-renders for unrelated reasons — most importantly while the
/// user drags the file sidebar's resize handle, which would otherwise re-tokenize
/// the whole file on every frame and make the drag stutter. `body` (and thus the
/// highlight pass) runs again only when the contents, language, or appearance
/// differ from the previous value.
private struct HighlightedCode: View, Equatable {
    let contents: String
    let language: String?
    let dark: Bool

    static func == (lhs: HighlightedCode, rhs: HighlightedCode) -> Bool {
        lhs.dark == rhs.dark && lhs.language == rhs.language && lhs.contents == rhs.contents
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(SyntaxHighlighter.highlight(contents, language: language, dark: dark))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .defaultScrollAnchor(.topLeading)
        .frame(maxWidth: .infinity, maxHeight: 360, alignment: .topLeading)
    }
}

/// A node in the file tree built from the files' paths. A leaf carries a
/// `file`; a folder carries `children` and a nil `file`.
private struct FileTreeNode: Identifiable {
    let id: String
    let name: String
    let file: CodeFile?
    let children: [FileTreeNode]

    var isFolder: Bool { file == nil }
}

/// Renders one level of the file tree, recursing into expanded folders. Pulled
/// out as its own view so the recursion stays straightforward and each row
/// indents by its depth.
private struct FileTreeRows: View {
    let nodes: [FileTreeNode]
    let depth: Int
    let selectedID: String
    @Binding var collapsedFolders: Set<String>
    let onSelect: (String) -> Void

    var body: some View {
        ForEach(nodes) { node in
            if node.isFolder {
                folderRow(node)
                if !collapsedFolders.contains(node.id) {
                    FileTreeRows(
                        nodes: node.children,
                        depth: depth + 1,
                        selectedID: selectedID,
                        collapsedFolders: $collapsedFolders,
                        onSelect: onSelect
                    )
                }
            } else if let file = node.file {
                fileRow(node, file: file)
            }
        }
    }

    private func folderRow(_ node: FileTreeNode) -> some View {
        let collapsed = collapsedFolders.contains(node.id)
        return Button {
            if collapsed {
                collapsedFolders.remove(node.id)
            } else {
                collapsedFolders.insert(node.id)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Image(systemName: "folder")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(node.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.trailing, 8)
            .padding(.leading, CGFloat(depth) * 12 + 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fileRow(_ node: FileTreeNode, file: CodeFile) -> some View {
        let isSelected = file.id == selectedID
        return Button {
            onSelect(file.id)
        } label: {
            HStack(spacing: 5) {
                // Align the file's icon with the folder's name column by
                // reserving the same width the disclosure chevron takes.
                Color.clear.frame(width: 10)
                Image(systemName: (file.language ?? "").languageSymbol)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(file.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.trailing, 8)
            .padding(.leading, CGFloat(depth) * 12 + 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(file.path ?? file.name)
    }
}

// MARK: - New Pad sheet

private struct NewPadSheet: View {
    let client: CoderPadClient
    let onCreated: (Pad) -> Void
    let onCancel: () -> Void

    @Environment(\.orgDirectory) private var directory
    @State private var title = ""
    @State private var language = "python3"
    /// Set once the user picks a language themselves, so a late-arriving org
    /// default doesn't overwrite their choice.
    @State private var languageEdited = false
    @State private var ownerEmail = ""
    @State private var isPrivate = false
    @State private var executionEnabled = true
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var questions: [Question] = []
    @State private var selectedQuestionID: Int? = nil
    @State private var teams: [PadTeam] = []
    @State private var selectedTeamID: String? = nil
    @State private var users: [OrganizationUser] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Pad").font(.title3.bold())

            Form {
                TextField("Title", text: $title, prompt: Text("Optional, e.g. \"Onsite: Jane Doe\""))

                LabeledContent("Question") {
                    SearchableQuestionPicker(selection: $selectedQuestionID, questions: questions)
                        .disabled(questions.isEmpty)
                }

                Picker("Language", selection: languageSelection) {
                    ForEach(CoderPadLanguages.pickerOptions, id: \.self) { Text($0.languageDisplayName).tag($0) }
                    if !CoderPadLanguages.pickerOptions.contains(language) {
                        Text(language.languageDisplayName).tag(language)
                    }
                }

                LabeledContent("Owner") {
                    SearchableOwnerPicker(ownerEmail: $ownerEmail,
                                          users: users,
                                          keyOwnerEmail: AccountsStore.shared.currentAccount?.userEmail)
                }

                if !teams.isEmpty {
                    Picker("Team", selection: $selectedTeamID) {
                        Text("Default").tag(String?.none)
                        Divider()
                        ForEach(teams, id: \.id) { team in
                            Text(team.name).tag(String?.some(team.id))
                        }
                    }
                }

                Toggle("Private", isOn: $isPrivate)
                Toggle("Execution enabled", isOn: $executionEnabled)
            }
            .formStyle(.grouped)
            .onChange(of: selectedQuestionID) { _, newValue in
                guard let id = newValue, let q = questions.first(where: { $0.id == id }) else { return }
                if title.isEmpty { title = q.title }
                if let lang = q.language, !lang.isEmpty { language = lang }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Create")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting)
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 360)
        .task { await loadQuestions() }
        .task { await loadOrganization() }
        .task { applyOrgDefaultLanguage() }
        .onChange(of: directory.defaultLanguage) { _, _ in applyOrgDefaultLanguage() }
    }

    /// The language picker's binding, marking the choice as user-made so the org
    /// default no longer overrides it.
    private var languageSelection: Binding<String> {
        Binding(get: { language }, set: { language = $0; languageEdited = true })
    }

    /// Pre-select the organization's default language, unless the user has already
    /// chosen one. Driven by `OrgDirectory`, which is loaded app-wide.
    private func applyOrgDefaultLanguage() {
        guard !languageEdited, let def = directory.defaultLanguage, !def.isEmpty else { return }
        language = def
    }

    private func loadQuestions() async {
        if questions.isEmpty, let id = AccountsStore.shared.currentAccountID {
            questions = QuestionsCacheStore.shared.get(id)
        }
        guard !client.apiKey.isEmpty else { return }
        if let fresh = try? await client.listQuestions() {
            questions = fresh.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        }
    }

    /// One `organization()` call backs both the Team picker and the searchable
    /// Owner picker, so adding owner selection costs no extra network round-trip.
    private func loadOrganization() async {
        guard !client.apiKey.isEmpty else { return }
        if let org = try? await client.organization() {
            teams = org.teams
            users = org.users.sorted {
                ($0.name ?? $0.email).localizedCaseInsensitiveCompare($1.name ?? $1.email) == .orderedAscending
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        let body = PadCreate(
            title: title.isEmpty ? nil : title,
            language: language,
            ownerEmail: ownerEmail.isEmpty ? nil : ownerEmail,
            contents: nil,
            notes: nil,
            isPrivate: isPrivate,
            executionEnabled: executionEnabled,
            questionID: selectedQuestionID,
            teamID: selectedTeamID
        )
        do {
            let pad = try await client.createPad(body)
            onCreated(pad)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A searchable replacement for a long `Picker` of questions. Shows the current
/// selection as a button; tapping opens a popover with a search field that filters
/// the (potentially large) question list so you don't scroll a huge menu.
private struct SearchableQuestionPicker: View {
    @Binding var selection: Int?
    let questions: [Question]

    @State private var isPresented = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private func title(for q: Question) -> String {
        q.title.isEmpty ? "#\(q.id)" : q.title
    }

    private var selectedTitle: String {
        guard let id = selection, let q = questions.first(where: { $0.id == id }) else { return "None" }
        return title(for: q)
    }

    private var filtered: [Question] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return questions }
        return questions.filter { title(for: $0).localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack {
                Text(selectedTitle)
                    .foregroundStyle(selection == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                TextField("Search questions", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(8)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        questionRow(id: nil, title: "None")
                        ForEach(filtered) { q in
                            questionRow(id: q.id, title: title(for: q))
                        }
                        if filtered.isEmpty {
                            Text("No questions match “\(query)”")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .padding(8)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
            .frame(width: 320)
            .onAppear { searchFocused = true }
        }
    }

    @ViewBuilder
    private func questionRow(id: Int?, title: String) -> some View {
        let isSelected = id == selection
        Button {
            selection = id
            isPresented = false
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(id == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
    }
}

private extension String {
    /// `nil` when the string is empty, otherwise itself — for collapsing optional
    /// names that arrive as empty strings into a true "missing" value.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Picks the new pad's owner. An empty `ownerEmail` means "let the API default to
/// the key's owner"; the picker surfaces that as a concrete, named "Default" row
/// (resolved from the configured account) rather than an abstract placeholder.
///
/// The search field doubles as free-text email entry: orgs where the key isn't an
/// owner may return no member list, and you may want to assign an owner who isn't
/// listed — typing any address offers a "Use …" row, so the field is never a dead
/// end when `users` is empty.
private struct SearchableOwnerPicker: View {
    @Binding var ownerEmail: String
    let users: [OrganizationUser]
    /// The configured account email, used only to label the Default row with who
    /// the key owner is. Pads are still created with an empty owner so the server
    /// resolves the true key owner.
    let keyOwnerEmail: String?

    @State private var isPresented = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var trimmedOwner: String {
        ownerEmail.trimmingCharacters(in: .whitespaces)
    }

    private func displayName(forEmail email: String) -> String? {
        users.first { $0.email.caseInsensitiveCompare(email) == .orderedSame }?.name?
            .nilIfEmpty
    }

    /// The current account's email, when known — used to recognize an explicitly
    /// self-owned pad (e.g. when editing) and to label the "Me" row by name.
    private var selfEmail: String? {
        keyOwnerEmail?.nilIfEmpty
    }

    /// True when the picker already holds the current account's own email.
    private var isSelfSelected: Bool {
        guard let selfEmail else { return false }
        return selfEmail.caseInsensitiveCompare(trimmedOwner) == .orderedSame
    }

    /// Label for the "Me" choice: the account name when we know it, else just "Me".
    private var meLabel: String {
        guard let email = selfEmail else { return "Me" }
        return (displayName(forEmail: email) ?? email) + " (Me)"
    }

    /// Subtitle for the "Me" row: the resolved key owner when known, otherwise a
    /// short explanation that an empty owner means the account holder.
    private var meSubtitle: String {
        guard let email = selfEmail else { return "Owned by your account (the API key owner)" }
        if let name = displayName(forEmail: email) { return "\(name) · \(email)" }
        return email
    }

    /// The label shown on the closed picker button. An empty owner means the pad is
    /// owned by the key owner — i.e. you — so it reads as "Me".
    private var selectedLabel: String {
        if trimmedOwner.isEmpty || isSelfSelected { return meLabel }
        return displayName(forEmail: trimmedOwner) ?? trimmedOwner
    }

    private var filteredUsers: [OrganizationUser] {
        // Exclude self — it's offered as a pinned "Me" row at the top instead.
        let members = users.filter {
            $0.email.caseInsensitiveCompare(selfEmail ?? "") != .orderedSame
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return members }
        return members.filter {
            $0.email.localizedCaseInsensitiveContains(q)
                || ($0.name?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    /// A typed address that isn't already an existing member — offered as a
    /// "Use …" row so free-text assignment still works.
    private var customEmailCandidate: String? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, q.contains("@") else { return nil }
        guard !users.contains(where: { $0.email.caseInsensitiveCompare(q) == .orderedSame }) else { return nil }
        return q
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack {
                Text(selectedLabel)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                TextField("Search members or enter email", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(8)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Pinned, always-present "Me" shortcut. An empty owner makes
                        // the server assign the pad to the key owner — you — so this
                        // works even when the account's email was never detected.
                        ownerRow(email: "",
                                 primary: meLabel,
                                 secondary: meSubtitle,
                                 isMuted: false)

                        Divider()

                        ForEach(filteredUsers) { user in
                            ownerRow(email: user.email,
                                     primary: user.name?.nilIfEmpty ?? user.email,
                                     secondary: user.name?.nilIfEmpty == nil ? nil : user.email,
                                     isMuted: false)
                        }

                        if let custom = customEmailCandidate {
                            ownerRow(email: custom,
                                     primary: "Use “\(custom)”",
                                     secondary: nil,
                                     isMuted: false)
                        }

                        if filteredUsers.isEmpty && customEmailCandidate == nil && !query.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("No members match “\(query)”")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .padding(8)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
            .frame(width: 320)
            .onAppear { searchFocused = true }
        }
    }

    @ViewBuilder
    private func ownerRow(email: String, primary: String, secondary: String?, isMuted: Bool) -> some View {
        let isSelected = email.caseInsensitiveCompare(trimmedOwner) == .orderedSame
        Button {
            ownerEmail = email
            query = ""
            isPresented = false
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(primary)
                        .foregroundStyle(isMuted ? .secondary : .primary)
                        .lineLimit(1)
                    if let secondary {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
    }
}

// MARK: - Edit Pad sheet

private struct EditPadSheet: View {
    let client: CoderPadClient
    let original: Pad
    let onSaved: (Pad) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var language: String
    @State private var ownerEmail: String
    @State private var isPrivate: Bool
    @State private var executionEnabled: Bool
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var users: [OrganizationUser] = []

    init(client: CoderPadClient,
         original: Pad,
         onSaved: @escaping (Pad) -> Void,
         onCancel: @escaping () -> Void) {
        self.client = client
        self.original = original
        self.onSaved = onSaved
        self.onCancel = onCancel
        _title = State(initialValue: original.title)
        _language = State(initialValue: original.language ?? "python3")
        _ownerEmail = State(initialValue: original.ownerEmail)
        _isPrivate = State(initialValue: original.isPrivate ?? false)
        _executionEnabled = State(initialValue: original.executionEnabled ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Pad").font(.title3.bold())

            Form {
                TextField("Title", text: $title)
                Picker("Language", selection: $language) {
                    ForEach(CoderPadLanguages.pickerOptions, id: \.self) { Text($0.languageDisplayName).tag($0) }
                    if !CoderPadLanguages.pickerOptions.contains(language) {
                        Text(language.languageDisplayName).tag(language)
                    }
                }
                LabeledContent("Owner") {
                    SearchableOwnerPicker(ownerEmail: $ownerEmail,
                                          users: users,
                                          keyOwnerEmail: AccountsStore.shared.currentAccount?.userEmail)
                }
                Toggle("Private", isOn: $isPrivate)
                Toggle("Execution enabled", isOn: $executionEnabled)
            }
            .formStyle(.grouped)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting)
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 360)
        .task { await loadOrganizationUsers() }
    }

    /// Loads org members so the owner field offers a searchable, named picker.
    /// Falls back silently to free-text entry when the list is empty or unavailable.
    private func loadOrganizationUsers() async {
        guard !client.apiKey.isEmpty else { return }
        if let org = try? await client.organization() {
            users = org.users.sorted {
                ($0.name ?? $0.email).localizedCaseInsensitiveCompare($1.name ?? $1.email) == .orderedAscending
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        let body = PadUpdate(
            id: original.id,
            title: title,
            language: language,
            ownerEmail: ownerEmail.isEmpty ? nil : ownerEmail,
            notes: nil,
            isPrivate: isPrivate,
            executionEnabled: executionEnabled
        )
        do {
            let updated = try await client.updatePad(body)
            onSaved(updated)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

