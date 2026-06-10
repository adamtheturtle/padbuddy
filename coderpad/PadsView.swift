//
//  PadsView.swift
//  coderpad
//

import SwiftUI

struct PadsView: View {
    let client: CoderPadClient
    @State private var pads: [Pad] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selection: Pad?
    @State private var search = ""
    @State private var stateFilter: String = "all"

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } detail: {
            if let selection {
                PadDetailView(client: client, pad: selection)
                    .id(selection.id)
            } else {
                placeholder
            }
        }
        .task(id: client.apiKey) { await reload() }
    }

    private var filtered: [Pad] {
        let lowered = search.lowercased()
        return pads.filter { pad in
            (stateFilter == "all" || pad.state.lowercased() == stateFilter) &&
            (lowered.isEmpty
             || pad.title.lowercased().contains(lowered)
             || pad.id.lowercased().contains(lowered)
             || pad.ownerEmail.lowercased().contains(lowered)
             || pad.participants.contains(where: { $0.lowercased().contains(lowered) }))
        }
    }

    private var availableStates: [String] {
        Array(Set(pads.map { $0.state.lowercased() })).sorted()
    }

    private var sidebar: some View {
        Group {
            if isLoading && pads.isEmpty {
                ProgressView("Loading pads…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView("Couldn't load pads",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                List(filtered, selection: $selection) { pad in
                    NavigationLink(value: pad) {
                        PadRow(pad: pad)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Pads")
        .searchable(text: $search, placement: .toolbar, prompt: "Search title, owner, participants…")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("All") { stateFilter = "all" }
                    Divider()
                    ForEach(availableStates, id: \.self) { state in
                        Button(state.capitalized) { stateFilter = state }
                    }
                } label: {
                    Label(stateFilter == "all" ? "All states" : stateFilter.capitalized,
                          systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem {
                Button { Task { await reload() } } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
    }

    private var placeholder: some View {
        ContentUnavailableView {
            Label("Select a pad", systemImage: "doc.text")
        } description: {
            Text(pads.isEmpty ? "Nothing here yet." : "\(pads.count) pads total. Pick one to see details.")
        }
    }

    private func reload() async {
        guard !client.apiKey.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await client.listPads()
            pads = fetched.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PadRow: View {
    let pad: Pad

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarCircle(label: pad.ownerEmail, diameter: 30)
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
                Text(pad.ownerEmail)
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

struct PadDetailView: View {
    let client: CoderPadClient
    let pad: Pad
    @State private var events: [PadEvent] = []
    @State private var environments: [PadEnvironment] = []
    @State private var loadError: String?
    @State private var isLoading = false

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
                AvatarCircle(label: pad.ownerEmail, diameter: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pad.title.isEmpty ? "Untitled Pad" : pad.title)
                        .font(.title2.weight(.semibold))
                    Text(pad.ownerEmail)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let url = URL(string: pad.url) {
                    Link(destination: url) {
                        Label("Open Pad", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent)
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
