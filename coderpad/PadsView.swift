//
//  PadsView.swift
//  coderpad
//

import SwiftUI

struct PadsView: View {
    let client: CoderPadClient
    @Environment(\.orgDirectory) private var directory
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

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 300, ideal: 360)
        } detail: {
            if let selection {
                PadDetailView(client: client, pad: selection)
                    .id(selection.id)
            } else {
                placeholder
            }
        }
        .task(id: client.apiKey) { await reload() }
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

    private var filtered: [Pad] {
        let lowered = search.lowercased()
        return pads.filter { pad in
            (stateFilter == nil || pad.state.lowercased() == stateFilter) &&
            (languageFilter == nil || (pad.language ?? "").lowercased() == languageFilter) &&
            (ownerFilter == nil || pad.ownerEmail == ownerFilter) &&
            (teamFilter == nil || pad.team?.name == teamFilter) &&
            (typeFilter == nil || (pad.type ?? "").lowercased() == typeFilter) &&
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
        [stateFilter, languageFilter, ownerFilter, teamFilter, typeFilter].compactMap { $0 }.count
    }

    private var sidebar: some View {
        Group {
            if isLoading && pads.isEmpty {
                ProgressView("Loading pads…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                APIErrorView(error: error) { Task { await reload() } }
            } else {
                VStack(spacing: 0) {
                    filterBar
                    Divider()
                    List(filtered, selection: $selection) { pad in
                        NavigationLink(value: pad) {
                            PadRow(pad: pad)
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .navigationTitle("Pads")
        .searchable(text: $search, placement: .toolbar, prompt: "Search title, owner, participants…")
        .toolbar {
            ToolbarItem {
                Button { showCreate = true } label: {
                    Label("New Pad", systemImage: "plus")
                }
                .disabled(client.apiKey.isEmpty)
            }
            ToolbarItem {
                Button { Task { await reload() } } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
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
                    formatter: { $0 }
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
                if activeFilterCount > 0 {
                    Button(role: .destructive) {
                        stateFilter = nil; languageFilter = nil
                        ownerFilter = nil; teamFilter = nil; typeFilter = nil
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
            let fetched = try await client.listPads()
            pads = fetched.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        } catch {
            self.error = error
        }
    }
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

private struct PadRow: View {
    let pad: Pad
    @Environment(\.orgDirectory) private var directory

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarCircle(label: directory.display(pad.ownerEmail), diameter: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(pad.title.isEmpty ? pad.id : pad.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    StateBadge(state: pad.state)
                    if let language = pad.language, !language.isEmpty {
                        Chip(text: language, systemImage: "chevron.left.slash.chevron.right",
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
    @State private var loadError: String?
    @State private var isLoading = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.orgDirectory) private var directory

    var body: some View {
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
                eventsCard
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(pad.title.isEmpty ? pad.id : pad.title)
        .task(id: pad.id) { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AvatarCircle(label: directory.display(pad.ownerEmail), diameter: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pad.title.isEmpty ? "Untitled Pad" : pad.title)
                        .font(.title2.weight(.semibold))
                    if let name = directory.name(for: pad.ownerEmail) {
                        Text(name).font(.callout)
                        EmailLink(email: pad.ownerEmail).font(.caption).foregroundStyle(.secondary)
                    } else {
                        EmailLink(email: pad.ownerEmail).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let url = URL(string: pad.url) {
                    HStack(spacing: 6) {
                        Button {
                            openWindow(id: "pad-browser", value: url)
                        } label: {
                            Label("Open Pad", systemImage: "doc.text.image")
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .help("Open in default browser")
                    }
                }
            }
            HStack(spacing: 6) {
                StateBadge(state: pad.state)
                if let language = pad.language, !language.isEmpty {
                    Chip(text: language, systemImage: "chevron.left.slash.chevron.right",
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
                            Chip(text: lang, tint: lang.languageColor)
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
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                } else if events.isEmpty && !isLoading {
                    Text("No events yet.").foregroundStyle(.secondary).font(.callout)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(events) { event in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: icon(for: event.kind))
                                    .foregroundStyle(color(for: event.kind))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(event.kind.capitalized).font(.callout.weight(.semibold))
                                        if let name = event.userName, !name.isEmpty {
                                            Text("· \(name)").font(.callout).foregroundStyle(.secondary)
                                        }
                                    }
                                    if let created = event.createdAt {
                                        Text(created.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            loadError = error.localizedDescription
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

    private let languages = [
        "python3", "javascript", "typescript", "swift", "go", "rust", "java",
        "kotlin", "ruby", "c", "cpp", "csharp", "php", "scala", "r", "sql", "bash"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Pad").font(.title3.bold())

            Form {
                TextField("Title", text: $title, prompt: Text("Optional — e.g. \"Onsite – Jane Doe\""))

                Picker("Language", selection: $language) {
                    ForEach(languages, id: \.self) { Text($0).tag($0) }
                }

                TextField("Owner email", text: $ownerEmail, prompt: Text("Optional — defaults to the key's owner"))

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
