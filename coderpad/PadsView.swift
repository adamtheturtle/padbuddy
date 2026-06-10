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
    @State private var cache = PadsCacheStore.shared
    @State private var pads: [Pad] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var selection: Pad?
    @State private var search = ""
    @State private var stateFilter: String? = nil
    @State private var languageFilter: String? = nil
    @State private var ownerFilter: String? = nil
    @State private var teamFilter: String? = nil
    @State private var typeFilter: String? = nil
    @State private var showCreate = false
    @State private var lastFetched: Date?
    @State private var previousUpdatedAt: [String: Date] = [:]
    @State private var changedPadIDs: Set<String> = []
    @State private var hasLoadedOnce = false
    @State private var dateRangeFilter: String? = nil
    @State private var savedSearches = SavedSearchStore.shared
    @State private var showSaveSearch = false
    @State private var saveSearchName = ""

    private static let refreshInterval: Duration = .seconds(45)

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 360, ideal: 440, max: 720)
        } detail: {
            if let selection {
                PadDetailView(client: client, pad: selection)
                    .id(selection.id)
            } else {
                placeholder
            }
        }
        .task(id: TaskKey(apiKey: client.apiKey, phase: scenePhase)) {
            guard scenePhase == .active else { return }
            if pads.isEmpty, let id = accounts.currentAccountID {
                pads = cache.get(id)
            }
            await periodicReload(interval: Self.refreshInterval) {
                await reload()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .createPadRequested)) { _ in
            showCreate = true
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .padsSearchRequested)) { note in
            if let q = note.object as? String { search = q }
        }
        .onReceive(NotificationCenter.default.publisher(for: .padsFilterByOwnerRequested)) { note in
            if let email = note.object as? String { ownerFilter = email }
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
            (typeFilter == nil || (pad.type ?? "").lowercased() == typeFilter) &&
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
    private var availableTypes: [String] {
        Array(Set(pads.compactMap { $0.type?.lowercased() }).filter { !$0.isEmpty }).sorted()
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
                    InlineSearchField(query: $search, prompt: "Search title, owner, participants…")
                        .padding(.horizontal, Spacing.paneH)
                        .padding(.top, Spacing.paneTitleTop)
                        .padding(.bottom, 8)
                    savedSearchesBar
                    filterBar
                    Divider()
                    List(filtered, selection: $selection) { pad in
                        NavigationLink(value: pad) {
                            PadRow(pad: pad, isChanged: changedPadIDs.contains(pad.id))
                        }
                    }
                    .listStyle(.inset)
                    .refreshable { await reload() }
                    .focusedValue(\.focusedPad, selection)
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { showCreate = true } label: {
                    Label("New Pad", systemImage: "plus")
                }
                .disabled(client.apiKey.isEmpty)
            }
            ToolbarItem {
                Button { Task { await reload() } } label: {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
            }
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
                    formatter: { directory.display($0) }
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
                    options: availableTypes,
                    formatter: { $0.capitalized }
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
        }
    }

    private var placeholder: some View {
        ContentUnavailableView {
            Label("Select a pad", systemImage: "doc.text")
        } description: {
            Text(pads.isEmpty ? "Nothing here yet." : "\(filtered.count) of \(pads.count) shown.")
        }
    }

    private func reload() async {
        guard !client.apiKey.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let fetched = try await client.listPads().sorted {
                ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
            }
            // Diff against previous snapshot
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
            pads = fetched
            if let id = accounts.currentAccountID {
                cache.set(id, pads: fetched)
            }
            lastFetched = Date()
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
                }
                Text(directory.display(pad.ownerEmail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let updated = pad.updatedAt {
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
    @Environment(\.openWindow) private var openWindow
    @Environment(\.orgDirectory) private var directory

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
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .help("Open in default browser")
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Open in default browser")
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
    }

    private var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metaCards
                if !pad.participants.isEmpty {
                    participantsCard
                }
                if !environments.isEmpty {
                    environmentsCard
                }
                if let active = activeEnvironment,
                   let contents = active.contents,
                   !contents.isEmpty {
                    codePreviewCard(active, contents: contents)
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
                Spacer()
                HStack(spacing: 6) {
                    Button { showEdit = true } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .help("Edit pad properties")
                    if URL(string: pad.url) != nil {
                        Button {
                            showBrowser = true
                        } label: {
                            Label("Open Pad", systemImage: "doc.text.image")
                        }
                        .buttonStyle(.borderedProminent)
                        .help("Open the pad in this pane")
                        if let url = URL(string: pad.url) {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Image(systemName: "safari")
                            }
                            .help("Open in default browser")
                            .accessibilityLabel("Open in default browser")
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                StateBadge(state: pad.state)
                if let language = pad.language, !language.isEmpty {
                    Chip(text: language.languageDisplayName, systemImage: language.languageSymbol,
                         tint: language.languageColor)
                }
                if let type = pad.type, !type.isEmpty {
                    Chip(text: type, systemImage: "tag")
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
                Text(pad.id).font(.caption.monospaced())
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pad.id, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy ID")
                .accessibilityLabel("Copy pad ID")
            }
            .foregroundStyle(.secondary)
        }
    }

    private var metaCards: some View {
        HStack(spacing: 12) {
            if let createdAt = pad.createdAt {
                StatTile(title: "Created", value: createdAt.formatted(date: .abbreviated, time: .shortened),
                         systemImage: "calendar.badge.plus", tint: .blue)
            }
            if let updatedAt = pad.updatedAt {
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

    private var participantsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Participants", systemImage: "person.2")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(pad.participants, id: \.self) { name in
                        HStack(spacing: 8) {
                            AvatarCircle(label: name, diameter: 26, tint: .purple)
                            Text(name).font(.callout)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.subtleStroke.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var environmentsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Environments", systemImage: "cube.box")
                ForEach(environments) { env in
                    HStack {
                        Text(env.title ?? "Environment #\(env.id)").font(.callout.weight(.medium))
                        if let lang = env.language, !lang.isEmpty {
                            Chip(text: lang.languageDisplayName, tint: lang.languageColor)
                        }
                        if env.id == pad.activeEnvironmentID {
                            Chip(text: "Active", systemImage: "checkmark.seal", tint: .green)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var activeEnvironment: PadEnvironment? {
        environments.first(where: { $0.id == pad.activeEnvironmentID })
            ?? environments.first
    }

    private func codePreviewCard(_ env: PadEnvironment, contents: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Code", systemImage: "chevron.left.slash.chevron.right")
                    Spacer()
                    if let lang = env.language, !lang.isEmpty {
                        Chip(text: lang.languageDisplayName, tint: lang.languageColor)
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(contents, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy code")
                    .accessibilityLabel("Copy code")
                }
                ScrollView([.vertical, .horizontal]) {
                    Text(contents)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 360)
                .background(Color.subtleStroke.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Code preview of pad \(pad.id)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            self.events = try await events
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Pad").font(.title3.bold())

            Form {
                TextField("Title", text: $title, prompt: Text("Optional, e.g. \"Onsite: Jane Doe\""))

                Picker("Language", selection: $language) {
                    ForEach(CoderPadLanguages.pickerOptions, id: \.self) { Text($0.languageDisplayName).tag($0) }
                }

                TextField("Owner email", text: $ownerEmail, prompt: Text("Optional. Defaults to the key's owner."))

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
                        Text("Create")
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
        let body = PadCreate(
            title: title.isEmpty ? nil : title,
            language: language,
            ownerEmail: ownerEmail.isEmpty ? nil : ownerEmail,
            contents: nil,
            notes: nil,
            isPrivate: isPrivate,
            executionEnabled: executionEnabled,
            questionIDs: nil
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

