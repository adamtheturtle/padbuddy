//
//  PadsView.swift
//  coderpad
//

import SwiftUI

struct PadsView: View {
    let client: CoderPadClient
    @Environment(\.orgDirectory) private var directory
    @Environment(\.scenePhase) private var scenePhase
    @State private var accounts = AccountsStore.shared
    @State private var nav = AppNavigation.shared
    @State private var cache = PadsCacheStore.shared
    @State private var pads: [Pad] = []
    @State private var isLoading = false
    @State private var error: Error?
    @Binding var selection: Pad?
    @State private var search = ""
    @FocusState private var searchFieldFocused: Bool
    @State private var stateFilter: String? = nil
    @State private var languageFilter: String? = nil
    @State private var ownerFilter: String? = nil
    @State private var teamFilter: String? = nil
    @State private var typeFilter: String? = nil
    @State private var showCreate = false
    @State private var previousUpdatedAt: [String: Date] = [:]
    @State private var changedPadIDs: Set<String> = []
    @State private var hasLoadedOnce = false
    @State private var dateRangeFilter: String? = nil
    @State private var savedSearches = SavedSearchStore.shared
    @State private var showSaveSearch = false
    @State private var saveSearchName = ""

    /// Big orgs return thousands of pads per sweep, and re-fetching every page every 45s is
    /// mostly wasted work for data well below the fold. The auto-refresh cadence backs off as
    /// the list grows, so large orgs poll far less often while small orgs keep the snappy
    /// refresh. Manual reload and the focused detail refresh are unaffected.
    private var nextRefreshInterval: Duration {
        switch pads.count {
        case ..<500: return .seconds(45)
        case 500..<2000: return .seconds(120)
        default: return .seconds(300)
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
        .onReceive(NotificationCenter.default.publisher(for: .reloadRequested)) { _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .padUpdated)) { note in
            if let updated = note.object as? Pad,
               let i = pads.firstIndex(where: { $0.id == updated.id }) {
                pads[i] = updated
                if selection?.id == updated.id { selection = updated }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .padDeleted)) { note in
            if let id = note.object as? String {
                pads.removeAll { $0.id == id }
                if selection?.id == id { selection = nil }
            }
        }
        .sheet(isPresented: $showSaveSearch) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Save Search").font(.title3.bold())
                TextField("Name", text: $saveSearchName, prompt: Text("e.g. Live pads, my team"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitSavedSearch() }
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { showSaveSearch = false }
                    Button("Save") { commitSavedSearch() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(saveSearchName.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private func commitSavedSearch() {
        let trimmed = saveSearchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savedSearches.add(captureCurrentSearch(named: trimmed))
        showSaveSearch = false
    }

    private static let dateRangeOptions = ["today", "last 7 days", "last 30 days"]

    private func dateRangeStart(for option: String) -> Date? {
        let cal = Calendar.current
        switch option {
        case "today": return cal.startOfDay(for: Date())
        case "last 7 days": return cal.date(byAdding: .day, value: -7, to: Date())
        case "last 30 days": return cal.date(byAdding: .day, value: -30, to: Date())
        default: return nil
        }
    }

    private var filtered: [Pad] {
        let lowered = search.lowercased()
        let rangeStart = dateRangeFilter.flatMap(dateRangeStart(for:))
        return pads.filter { pad in
            (stateFilter == nil || pad.state.lowercased() == stateFilter) &&
            (languageFilter == nil || (pad.language ?? "").lowercased() == languageFilter) &&
            (ownerFilter == nil || pad.ownerEmail == ownerFilter) &&
            (teamFilter == nil || pad.team?.name == teamFilter) &&
            (typeFilter == nil || pad.interviewType?.rawValue == typeFilter) &&
            (rangeStart == nil || (pad.updatedAt ?? .distantPast) >= rangeStart!) &&
            (lowered.isEmpty
             || pad.title.lowercased().contains(lowered)
             || pad.id.lowercased().contains(lowered)
             || pad.ownerEmail.lowercased().contains(lowered)
             || directory.display(pad.ownerEmail).lowercased().contains(lowered)
             || pad.participants.contains(where: { $0.lowercased().contains(lowered) }))
        }
    }

    private var availableStates: [String] {
        Array(Set(pads.map { $0.state.lowercased() })).sorted()
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
        [stateFilter, languageFilter, ownerFilter, teamFilter, typeFilter, dateRangeFilter].compactMap { $0 }.count
    }

    private var sidebar: some View {
        Group {
            if isLoading && pads.isEmpty {
                ProgressView("Loading pads…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                APIErrorView(error: error) { Task { await reload() } }
            } else {
                VStack(spacing: 0) {
                    PaneTitle(title: "Pads")
                    HStack(spacing: 8) {
                        InlineSearchField(query: $search, prompt: "Search title, owner, participants…",
                                          focused: $searchFieldFocused)
                        paneActions
                    }
                    .padding(.horizontal, Spacing.paneH)
                    .padding(.bottom, 8)
                    savedSearchesBar
                    filterBar
                    Divider()
                    List(selection: $selection) {
                        ForEach(filtered) { pad in
                            PadRow(pad: pad, isChanged: changedPadIDs.contains(pad.id))
                                .tag(pad)
                        }
                    }
                    .listStyle(.inset)
                    .refreshable { await reload() }
                    .focusedValue(\.focusedPad, selection)
                }
            }
        }
        .focusedSceneValue(\.findAction, FindAction { searchFieldFocused = true })
    }

    private var paneActions: some View {
        HStack(spacing: 2) {
            Button { showCreate = true } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New Pad")
            .accessibilityLabel("New Pad")
            .disabled(client.apiKey.isEmpty)
            Button { Task { await reload() } } label: {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Reload")
            .accessibilityLabel("Reload")
            .disabled(isLoading)
        }
    }

    @ViewBuilder
    private var savedSearchesBar: some View {
        if !savedSearches.searches.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(savedSearches.searches) { saved in
                        SavedSearchChip(search: saved) {
                            apply(saved)
                        } onDelete: {
                            savedSearches.remove(id: saved.id)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.top, 6)
            }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChipMenu(
                    title: "State",
                    icon: "circle.fill",
                    selected: $stateFilter,
                    options: availableStates,
                    formatter: { $0.capitalized }
                )
                FilterChipMenu(
                    title: "Language",
                    icon: "chevron.left.slash.chevron.right",
                    selected: $languageFilter,
                    options: availableLanguages,
                    formatter: { $0.languageDisplayName }
                )
                SearchableFilterChip(
                    title: "Owner",
                    icon: "person",
                    selected: $ownerFilter,
                    options: availableOwners,
                    formatter: { directory.display($0) },
                    meEmail: accounts.currentAccount?.userEmail
                )
                FilterChipMenu(
                    title: "Team",
                    icon: "person.3",
                    selected: $teamFilter,
                    options: availableTeams,
                    formatter: { $0 }
                )
                FilterChipMenu(
                    title: "Type",
                    icon: "tag",
                    selected: $typeFilter,
                    options: InterviewType.allCases.map(\.rawValue),
                    formatter: { InterviewType(rawValue: $0)?.label ?? $0.capitalized }
                )
                FilterChipMenu(
                    title: "Updated",
                    icon: "calendar",
                    selected: $dateRangeFilter,
                    options: Self.dateRangeOptions,
                    formatter: { $0.capitalized }
                )
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
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .measuresFilterBarWidth()
        }
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
                pads = snapshot
            }
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
            changedPadIDs = changes
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

struct FilterChipMenu: View {
    let title: String
    let icon: String
    @Binding var selected: String?
    let options: [String]
    let formatter: (String) -> String

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
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption)
                Text(selected.map(formatter) ?? title)
                    .font(.callout)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (selected == nil ? Color.subtleStroke : Color.accentColor.opacity(0.18)),
                in: Capsule()
            )
            .foregroundStyle(selected == nil ? Color.primary : Color.accentColor)
            .overlay(Capsule().stroke(selected == nil ? Color.subtleStroke : Color.accentColor.opacity(0.4), lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(options.isEmpty)
    }
}

private struct SavedSearchChip: View {
    let search: NamedSearch
    let onApply: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bookmark.fill").font(.caption2)
            Text(search.name).font(.caption)
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete saved search \(search.name)")
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.14), in: Capsule())
        .foregroundStyle(Color.accentColor)
        .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5))
        .onTapGesture { onApply() }
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
                    StateBadge(state: pad.state)
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
    @State private var showBrowser = false
    @State private var showEndConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isMutating = false
    @State private var mutateError: String?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.orgDirectory) private var directory
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if showBrowser, let url = URL(string: pad.url) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Button {
                            showBrowser = false
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
                    .background(.thinMaterial)
                    Divider()
                    PadBrowserView(url: url)
                }
            } else {
                detailScroll
            }
        }
        .navigationTitle(pad.title.isEmpty ? pad.id : pad.title)
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
    }

    private var isEnded: Bool {
        pad.endedAt != nil || pad.state.lowercased() == "ended"
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
            // When the pane is wide, identity and actions share one row. As it
            // narrows, the actions drop to a row below so the title keeps the full
            // pane width to wrap across, instead of being starved by the fixed-size
            // buttons down to a one-character-per-line column.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    identity
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 12)
                    actionButtons
                }
                VStack(alignment: .leading, spacing: 12) {
                    identity
                    actionButtons
                }
            }
            HStack(spacing: 6) {
                StateBadge(state: pad.state)
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
                    Chip(text: "Execution", systemImage: "play.circle", tint: .green)
                }
                if let team = pad.team {
                    Chip(text: team.name, systemImage: "person.3", tint: .purple)
                }
            }
            HStack(spacing: 6) {
                // The raw ID stays selectable so it can still be grabbed as a
                // literal token (API calls, referencing the pad in conversation).
                Text(pad.id)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                if let url = URL(string: pad.url) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .help("Share pad")
                    .accessibilityLabel("Share pad")
                }
            }
            .foregroundStyle(.secondary)
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

    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button { showEdit = true } label: {
                Label("Edit", systemImage: "pencil")
            }
            .help("Edit pad properties")
            if let url = URL(string: pad.url) {
                Button {
                    if BrowserSettings.openLinksIn == .external {
                        BrowserSettings.openExternally(url)
                    } else {
                        showBrowser = true
                    }
                } label: {
                    Label("Open Pad", systemImage: "doc.text.image")
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(.borderedProminent)
                .help("Open the pad")
            }
            Menu {
                Button {
                    showEndConfirm = true
                } label: {
                    Label("End Interview", systemImage: "flag.checkered")
                }
                .disabled(isEnded)
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Pad", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(isMutating)
            .help("More actions")
            .accessibilityLabel("More actions")
        }
        .fixedSize()
    }

    private var metaCards: some View {
        HStack(spacing: 12) {
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
            if let playback = pad.playback, let url = URL(string: playback) {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Playback", systemImage: "play.rectangle")
                        Link("Watch", destination: url)
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
                                            Text("· \(name)").font(.callout).foregroundStyle(.secondary)
                                        }
                                    }
                                    if let first = group.representative.createdAt {
                                        if group.count > 1, let last = group.lastEvent.createdAt {
                                            Text("\(first.formatted(date: .abbreviated, time: .shortened)) – \(last.formatted(date: .omitted, time: .shortened))")
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
            return CodeFile(
                id: index,
                path: file.path,
                contents: body,
                language: CodeFile.language(forPath: file.path, fallback: env.language)
            )
        }
    }

    private struct EventGroup: Identifiable {
        let id: String
        let representative: PadEvent
        let count: Int
        let lastEvent: PadEvent
    }

    private static let collapsibleKinds: Set<String> = ["typed", "edited", "ran", "executed"]

    private var groupedEvents: [EventGroup] {
        var groups: [EventGroup] = []
        for event in events {
            if let last = groups.last,
               Self.collapsibleKinds.contains(event.kind.lowercased()),
               last.representative.kind == event.kind,
               last.representative.userName == event.userName {
                groups[groups.count - 1] = EventGroup(
                    id: last.id,
                    representative: last.representative,
                    count: last.count + 1,
                    lastEvent: event
                )
            } else {
                groups.append(EventGroup(id: event.id, representative: event, count: 1, lastEvent: event))
            }
        }
        return groups
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

    private func accessibilityLabel(for group: EventGroup) -> String {
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
    let id: Int
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

    @State private var selectedFileID: Int?

    private var selected: CodeFile {
        files.first { $0.id == selectedFileID } ?? files[0]
    }

    private var isMultiFile: Bool { files.count > 1 }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                header
                if isMultiFile {
                    fileTabs
                }
                codePane
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    private var fileTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(files) { file in
                    let isSelected = file.id == selected.id
                    Button {
                        selectedFileID = file.id
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: (file.language ?? "").languageSymbol)
                                .font(.caption2)
                            Text(file.name).font(.caption)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            isSelected ? Color.accentColor.opacity(0.18) : Color.subtleStroke.opacity(0.6),
                            in: Capsule()
                        )
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help(file.path ?? file.name)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var codePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Multi-file projects show the full path above the code so the
            // selected tab's location in the project is unambiguous.
            if isMultiFile, let path = selected.path, !path.isEmpty {
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(SyntaxHighlighter.highlight(selected.contents, language: selected.language, dark: dark))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.topLeading)
            .frame(maxWidth: .infinity, maxHeight: 360, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                copyButton
                    .padding(8)
            }
        }
        .background(Color.subtleStroke.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        // Name the environment by its language, the same identity shown visually.
        let environmentName = (language?.isEmpty == false) ? language!.languageDisplayName : nil
        if isMultiFile {
            return "Code preview of \(selected.name)\(environmentName.map { " in \($0)" } ?? "") in pad \(padID)"
        }
        return environmentName != nil
            ? "Code preview of \(environmentName!) in pad \(padID)"
            : "Code preview of pad \(padID)"
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - New Pad sheet

private struct NewPadSheet: View {
    let client: CoderPadClient
    let onCreated: (Pad) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var language = "python3"
    @State private var ownerEmail = ""
    @State private var isPrivate = false
    @State private var executionEnabled = true
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var questions: [Question] = []
    @State private var selectedQuestionID: Int? = nil
    @State private var teams: [PadTeam] = []
    @State private var selectedTeamID: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Pad").font(.title3.bold())

            Form {
                TextField("Title", text: $title, prompt: Text("Optional, e.g. \"Onsite: Jane Doe\""))

                Picker("Question", selection: $selectedQuestionID) {
                    Text("None").tag(Int?.none)
                    if !questions.isEmpty {
                        Divider()
                        ForEach(questions) { q in
                            Text(q.title.isEmpty ? "#\(q.id)" : q.title).tag(Int?.some(q.id))
                        }
                    }
                }
                .disabled(questions.isEmpty)

                Picker("Language", selection: $language) {
                    ForEach(CoderPadLanguages.pickerOptions, id: \.self) { Text($0.languageDisplayName).tag($0) }
                    if !CoderPadLanguages.pickerOptions.contains(language) {
                        Text(language.languageDisplayName).tag(language)
                    }
                }

                TextField("Owner email", text: $ownerEmail, prompt: Text("Optional. Defaults to the key's owner."))

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
        .task { await loadTeams() }
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

    private func loadTeams() async {
        guard !client.apiKey.isEmpty else { return }
        if let org = try? await client.organization() {
            teams = org.teams
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
            Text(original.id).font(.caption.monospaced()).foregroundStyle(.secondary)

            Form {
                TextField("Title", text: $title)
                Picker("Language", selection: $language) {
                    ForEach(CoderPadLanguages.pickerOptions, id: \.self) { Text($0.languageDisplayName).tag($0) }
                    if !CoderPadLanguages.pickerOptions.contains(language) {
                        Text(language.languageDisplayName).tag(language)
                    }
                }
                TextField("Owner email", text: $ownerEmail)
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

