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
/// campaigns are hidden by default. The selection is published to this window's
/// `WindowNavigation` so the detail column can show the campaign's test sessions (#434).
struct ScreenCampaignsView: View {
    let client: ScreenClient
    @Binding var search: String
    /// This window's published navigation state (injected by `ContentView`): the
    /// campaign selection and candidate-count subtitle are per window, so another
    /// window's Screen section can't retarget or blank this one's (#887, #888).
    @Environment(WindowNavigation.self) private var windowNav
    @State private var campaigns: [ScreenCampaign] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showArchived = false
    @State private var showWebhook = false
    /// The selected campaign's id. Selecting a campaign drives the detail column's
    /// test-sessions list (#448) — single-click selects and never swaps this list,
    /// consistent with how Pads/Questions select a row and populate the detail column.
    @State private var selectedCampaignID: Int?

    var body: some View {
        List(selection: $selectedCampaignID) {
            ForEach(filtered) { campaign in
                ScreenCampaignRow(campaign: campaign)
                    .tag(campaign.id)
                    .contextMenu { campaignActions(campaign) }
                    .draggable(campaign.name)
            }
        }
        .overlay { statusOverlay }
        // A refresh failure over previously loaded rows must not pose as current
        // data (#802): keep the rows but flag them stale with the error and retry.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let loadError, !campaigns.isEmpty {
                StaleRefreshBanner(message: loadError) { Task { await load() } }
                    .padding(8)
            }
        }
        // With no campaign selected, show the campaign count; once one is selected the
        // detail column shows its test sessions, so surface that campaign's candidate
        // count instead (published by the tests view via WindowNavigation) (#448/#475).
        .reportsSectionCount(selectedCampaignID == nil ? countSubtitle : windowNav.screenTestsSubtitle)
        .toolbar(id: "screen-campaigns") { campaignsToolbar }
        .focusedSceneValue(\.focusedScreenCampaignAction, selectedCampaignAction)
        #if os(macOS)
            .onCopyCommand(perform: copyLinkCommand(hasSelection: selectedCampaign != nil) {
                selectedCampaign?.name ?? ""
            })
        #endif
            .sheet(isPresented: $showWebhook) {
                ScreenWebhookSheet(client: client)
            }
            .task(id: client.taskIdentity) { await load() }
            // Reload on ⌘R like the other lists (AppRouter.requestReload()).
            .onReloadRequest { await load() }
            // Restore the published selection on appear, and publish each change onward so
            // the detail column can show the selected campaign's test sessions (#448).
            .onAppear { restoreSelectedCampaign() }
            .onChange(of: selectedCampaignID) { _, id in publishSelectedCampaign(id) }
            // Hiding archived campaigns must not leave a now-invisible archived
            // selection driving the detail column and the search field (#801).
            .onChange(of: showArchived) { _, show in
                if !show, selectedCampaign?.archived == true { selectedCampaignID = nil }
            }
    }

    private func restoreSelectedCampaign() {
        let id = windowNav.screenCampaignSelection?.id
        guard selectedCampaignID != id else { return }

        DispatchQueue.main.async {
            if selectedCampaignID != id { selectedCampaignID = id }
        }
    }

    private func publishSelectedCampaign(_ id: Int?) {
        let campaign = campaigns.first { $0.id == id }
        // A selected id that doesn't resolve yet means the list simply hasn't
        // loaded (this view is recreated on every section switch): publishing the
        // nil would wipe the still-valid published selection and blank the detail
        // column on re-entry (#997). `load()` re-publishes once rows exist.
        if id != nil, campaign == nil { return }

        let windowNav = windowNav
        guard windowNav.screenCampaignSelection != campaign else { return }

        DispatchQueue.main.async {
            if windowNav.screenCampaignSelection != campaign { windowNav.screenCampaignSelection = campaign }
        }
    }

    /// Right-click actions for a campaign row (#466). The Screen API exposes no
    /// per-campaign mutations, so these are selection and copy: select the campaign to
    /// show its test sessions in the detail column, or copy its name.
    @ViewBuilder
    private func campaignActions(_ campaign: ScreenCampaign) -> some View {
        Button("Show Test Sessions") { selectedCampaignID = campaign.id }
        Button("Copy Name") { Clipboard.copy(campaign.name) }
    }

    private var selectedCampaign: ScreenCampaign? {
        selectedCampaignID.flatMap { id in campaigns.first { $0.id == id } }
    }

    private var selectedCampaignAction: ScreenCampaignAction? {
        guard let selectedCampaign else { return nil }

        return ScreenCampaignAction(id: "screen-campaign-\(selectedCampaign.id)",
                                    contentFingerprint: selectedCampaign.name.hashValue) {
            Clipboard.copy(selectedCampaign.name)
        } showTests: {
            selectedCampaignID = selectedCampaign.id
        }
    }

    /// The campaigns-list toolbar. An identified, customizable toolbar (so Customize
    /// Toolbar… is enabled here too, #464) with Reload hidden by default — ⌘R already
    /// reloads, so the button is opt-in via Customize Toolbar (#465).
    @ToolbarContentBuilder
    private var campaignsToolbar: some CustomizableToolbarContent {
        ToolbarItem(id: "show-archived", placement: .automatic) {
            Toggle(isOn: $showArchived) {
                Label("Show Archived", systemImage: "archivebox")
            }
            .help("Include archived campaigns in the list.")
        }
        ToolbarItem(id: "webhook", placement: .automatic) {
            Button { showWebhook = true } label: {
                Label("Webhook", systemImage: "bolt.horizontal")
            }
            .help("View or configure the Screen event webhook.")
        }
        ToolbarItem(id: "reload", placement: .automatic) {
            Button { Task { await load() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .help("Reload campaigns.")
            .disabled(isLoading)
        }
        .defaultCustomization(.hidden)
    }

    /// Campaigns matching the search and archived filters, pinned ones first and then
    /// alphabetical so the list has a stable, predictable order. While a campaign is
    /// selected the search field targets that campaign's candidates (the detail column),
    /// so this list ignores the query then — keeping the selected campaign in view.
    private var filtered: [ScreenCampaign] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let query = selectedCampaignID == nil ? trimmed : ""
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
            // If the selected campaign vanished, clear the selection (and its detail).
            if let id = selectedCampaignID, !campaigns.contains(where: { $0.id == id }) {
                selectedCampaignID = nil
            }
            // Re-publish now that rows exist: a selection restored before this load
            // couldn't publish (see `publishSelectedCampaign`), and a renamed
            // campaign should refresh the published copy (#997).
            publishSelectedCampaign(selectedCampaignID)
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
        campaign.languages.map(\.coderPadLanguageDisplayName).joined(separator: ", ")
    }
}

/// The Screen section's detail (third) column when no campaign is selected: prompt to
/// pick one. Once a campaign is selected its test sessions fill the detail column
/// (#448); a session's report opens in its own window (`ScreenTestDetailView`, #474).
struct ScreenDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView("Select a campaign", systemImage: "person.crop.rectangle.stack")
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
    // Build the sample campaigns in their own statements to keep the List
    // ViewBuilder expression under the 250ms type-check budget.
    let backend = ScreenCampaign(id: 1, name: "Backend Engineer", languages: ["python", "go"], pinned: true)
    let frontend = ScreenCampaign(id: 2, name: "Frontend Engineer", languages: ["javascript"], archived: true)
    let dataScience = ScreenCampaign(id: 3, name: "Data Science", languages: ["python", "sql"])
    List {
        ScreenCampaignRow(campaign: backend)
        ScreenCampaignRow(campaign: frontend)
        ScreenCampaignRow(campaign: dataScience)
    }
    .frame(width: 420, height: 240)
}
