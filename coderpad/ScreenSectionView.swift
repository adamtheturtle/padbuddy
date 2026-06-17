//
//  ScreenSectionView.swift
//  coderpad
//
//  The CoderPad Screen section (campaigns and test sessions). The campaigns list is
//  the content column (#433); selecting one drives the detail column, whose test
//  sessions land in #434. Gated on the account having a Screen key (#432).
//

import SwiftUI

/// The Screen section's content column: the org's test campaigns (`GET /campaigns`),
/// modelled on `PadsView` but far leaner — Screen is read-only here. Search is the
/// shared window-toolbar field (routed via `MainSplit.activeSearch`); archived
/// campaigns are hidden by default. The selection is published to `AppNavigation`
/// so the detail column can show the campaign's test sessions (#434).
struct ScreenCampaignsView: View {
    let client: ScreenClient
    @Binding var search: String
    @State private var nav = AppNavigation.shared
    @State private var campaigns: [ScreenCampaign] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showArchived = false
    @State private var selectedID: Int?

    var body: some View {
        List(selection: $selectedID) {
            ForEach(filtered) { campaign in
                ScreenCampaignRow(campaign: campaign).tag(campaign.id)
            }
        }
        .overlay { statusOverlay }
        .reportsSectionCount(countSubtitle)
        .task(id: client.apiKey) { await load() }
        // Reload on ⌘R like the other lists (AppRouter.requestReload()).
        .task {
            for await _ in AppRouter.reloads {
                await load()
            }
        }
        .onAppear { selectedID = nav.screenCampaignSelection?.id }
        // Mirror the list selection out to the shared nav selection the detail reads.
        .onChange(of: selectedID) { _, id in
            nav.screenCampaignSelection = id.flatMap { cid in campaigns.first { $0.id == cid } }
        }
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $showArchived) {
                    Label("Show Archived", systemImage: "archivebox")
                }
                .help("Include archived campaigns in the list.")
            }
            ToolbarItem {
                Button { Task { await load() } } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help("Reload campaigns.")
                .disabled(isLoading)
            }
        }
    }

    /// Campaigns matching the search and archived filters, pinned ones first and then
    /// alphabetical so the list has a stable, predictable order.
    private var filtered: [ScreenCampaign] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return campaigns
            .filter { (showArchived || !$0.archived) && (query.isEmpty || $0.name.lowercased().contains(query)) }
            .sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned { return lhs.pinned }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var countSubtitle: String {
        guard !campaigns.isEmpty else { return "" }

        let count = filtered.count
        return count == 1
            ? String(localized: "\(count) campaign")
            : String(localized: "\(count) campaigns")
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if let loadError, campaigns.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load campaigns", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        } else if campaigns.isEmpty, isLoading {
            ProgressView()
        } else if filtered.isEmpty {
            ContentUnavailableView {
                Label("No campaigns", systemImage: "person.crop.rectangle.stack")
            } description: {
                Text(campaigns.isEmpty
                    ? "This account has no Screen campaigns yet."
                    : "No campaign matches your search.")
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            campaigns = try await client.listCampaigns()
            loadError = nil
            // Keep the published selection consistent if the selected campaign vanished.
            if let id = selectedID, !campaigns.contains(where: { $0.id == id }) {
                selectedID = nil
            }
        } catch {
            loadError = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// One campaign row: its name, language chips, and pinned/archived badges.
struct ScreenCampaignRow: View {
    let campaign: ScreenCampaign

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if campaign.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Pinned")
                        .accessibilityLabel("Pinned")
                }
                Text(campaign.name)
                    .font(.body)
                    .lineLimit(1)
                if campaign.archived {
                    MetaLabel(text: String(localized: "Archived"), systemImage: "archivebox")
                }
            }
            if !campaign.languages.isEmpty {
                Text(languageSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// The campaign's languages as friendly names (e.g. "Python, JavaScript"), reusing
    /// the same display mapping the rest of the app uses.
    private var languageSummary: String {
        campaign.languages.map(\.languageDisplayName).joined(separator: ", ")
    }
}

/// The Screen section's detail column. The selected campaign's test sessions land in
/// #434; for now it confirms which campaign is selected (or prompts for one).
struct ScreenDetailPlaceholder: View {
    var campaign: ScreenCampaign?

    var body: some View {
        if let campaign {
            ContentUnavailableView {
                Label(campaign.name, systemImage: "person.crop.rectangle.stack")
            } description: {
                Text("Test sessions for this campaign will appear here.")
            }
        } else {
            ContentUnavailableView("Select a campaign", systemImage: "person.crop.rectangle.stack")
        }
    }
}

/// The Screen section's list placeholder, used before a Screen client is available.
struct ScreenSectionPlaceholder: View {
    var body: some View {
        ContentUnavailableView {
            Label("Screen", systemImage: "person.crop.rectangle.stack")
        } description: {
            Text("Campaigns and test sessions will appear here.")
        }
    }
}

#Preview("Campaign row") {
    List {
        ScreenCampaignRow(campaign: ScreenCampaign(id: 1, name: "Backend Engineer",
                                                   languages: ["python", "go"], pinned: true))
        ScreenCampaignRow(campaign: ScreenCampaign(id: 2, name: "Frontend Engineer",
                                                   languages: ["javascript"], archived: true))
        ScreenCampaignRow(campaign: ScreenCampaign(id: 3, name: "Data Science",
                                                   languages: ["python", "sql"]))
    }
    .frame(width: 420, height: 240)
}
