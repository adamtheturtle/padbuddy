//
//  ScreenSectionView.swift
//  coderpad
//
//  The CoderPad Screen section (campaigns and test sessions). The campaigns list is
//  the content column (#433); selecting one drives the detail column, whose test
//  sessions land in #434. Gated on the account having a Screen key (#432).
//

// swiftlint:disable file_length

import SwiftUI

/// The Screen section's content column: the org's test campaigns (`GET /campaigns`),
/// modelled on `PadsView` but far leaner — Screen is read-only here. Search is the
/// shared window-toolbar field (routed via `MainSplit.activeSearch`); archived
/// campaigns are hidden by default. The selection is published to this window's
/// `WindowNavigation` so the detail column can show the campaign's test sessions (#434).
struct ScreenCampaignsView: View { // swiftlint:disable:this type_body_length
    let client: ScreenClient
    let accountID: UUID
    @Binding var search: String
    /// This window's published navigation state (injected by `ContentView`): the
    /// campaign selection and candidate-count subtitle are per window, so another
    /// window's Screen section can't retarget or blank this one's (#887, #888).
    @Environment(WindowNavigation.self) private var windowNav
    @State private var campaigns: [ScreenCampaign] = []
    /// Campaigns sorted once per server response with their folded search keys.
    /// Filtering while the user types is then a single bounded scan (#1467).
    @State private var campaignSearchIndex: [CampaignSearchEntry] = []
    @State private var filtered: [ScreenCampaign] = []
    @State private var isLoading = false
    @State private var loadError: String?
    /// Orders manual reloads and client changes so only the newest request for the
    /// currently displayed Screen account may publish campaigns or errors (#1463).
    @State private var loadGeneration = 0
    @State private var showArchived = false
    @State private var showWebhook = false
    @State private var showQuestionBank = false
    @State private var showCampaignCreation = false
    @Environment(\.isReadOnly) private var isReadOnly
    /// The selected campaign's id. Selecting a campaign drives the detail column's
    /// test-sessions list (#448) — single-click selects and never swaps this list,
    /// consistent with how Pads/Questions select a row and populate the detail column.
    @State private var selectedCampaignID: Int?

    struct CampaignSearchEntry {
        let campaign: ScreenCampaign
        let foldedName: String
    }

    var body: some View {
        List(selection: $selectedCampaignID) {
            ForEach(filtered) { campaign in
                ScreenCampaignRow(campaign: campaign)
                    .tag(campaign.id)
                    .contextMenu { campaignActions(campaign) }
                    .draggable(ScreenCampaignDragPayload(campaign: campaign))
            }
        }
        .overlay { statusOverlay }
        // Keep loaded rows but mark a failed refresh stale with retry (#802).
        .safeAreaInset(edge: .top, spacing: 0) {
            if let loadError, !campaigns.isEmpty {
                StaleRefreshBanner(message: loadError) { Task { await load() } }
                    .padding(8)
            }
        }
        // Once selected, surface the detail's candidate count via WindowNavigation (#448/#475).
        .reportsSectionCount(selectedCampaignID == nil ? countSubtitle : windowNav.screenTestsSubtitle)
        .toolbar(id: "screen-campaigns") { campaignsToolbar }
        .focusedSceneValue(\.focusedScreenCampaignAction, selectedCampaignAction)
        #if os(macOS)
            .onCopyCommand(perform: copyLinkCommand(hasSelection: selectedCampaign != nil) {
                selectedCampaign?.name ?? ""
            })
        #endif
            .sheet(isPresented: $showWebhook) {
                ScreenWebhookSheet(client: client, accountID: accountID)
                    .id(ScreenWebhookContext(accountID: accountID, clientIdentity: client.taskIdentity))
            }
            .sheet(isPresented: $showCampaignCreation) {
                ScreenCampaignCreationSheet(client: client, accountID: accountID) { id in
                    selectedCampaignID = id
                    Task { await load() }
                }
                .id(ScreenBankIdentity(accountID: accountID, clientIdentity: client.taskIdentity))
            }
            .sheet(isPresented: $showQuestionBank) {
                ScreenQuestionBankView(client: client, accountID: accountID)
                    .id(ScreenBankIdentity(accountID: accountID, clientIdentity: client.taskIdentity))
            }
            .onChange(of: client.taskIdentity) { _, _ in
                showWebhook = false
                showQuestionBank = false
                showCampaignCreation = false
            }
            .onChange(of: accountID) { _, _ in
                showQuestionBank = false
                showCampaignCreation = false
            }
            .task(id: client.taskIdentity) { await load() }
            .onReloadRequest { await load() }
            // Restore and publish the selected campaign for the detail column (#448).
            .onAppear { restoreSelectedCampaign() }
            .onChange(of: selectedCampaignID) { _, id in
                ScreenCampaignSelectionStore.save(id, for: accountID); publishSelectedCampaign(id); refreshDerived()
            }
            .onChange(of: search) { _, _ in refreshDerived() }
            // Hiding archived campaigns must not leave a now-invisible archived
            // selection driving the detail column and the search field (#801).
            .onChange(of: showArchived) { _, show in
                if !show, selectedCampaign?.archived == true {
                    selectedCampaignID = nil
                }
                refreshDerived()
            }
    }

    private func restoreSelectedCampaign() {
        if windowNav.screenCampaignSelection != nil, windowNav.screenCampaignAccountID != accountID {
            selectedCampaignID = nil
            windowNav.publishScreenCampaign(nil, accountID: nil)
            return
        }

        let id = windowNav.screenCampaign(for: accountID)?.id
            ?? ScreenCampaignSelectionStore.campaign(for: accountID)
        guard selectedCampaignID != id else { return }

        selectedCampaignID = id
    }

    private func publishSelectedCampaign(_ id: Int?) {
        let campaign = campaigns.first { $0.id == id }
        // A selected id that doesn't resolve yet means the list simply hasn't
        // loaded (this view is recreated on every section switch): publishing the
        // nil would wipe the still-valid published selection and blank the detail
        // column on re-entry (#997). `load()` re-publishes once rows exist.
        if id != nil, campaign == nil {
            return
        }

        guard windowNav.screenCampaignSelection != campaign
            || windowNav.screenCampaignAccountID != (campaign == nil ? nil : accountID) else { return }

        windowNav.publishScreenCampaign(campaign, accountID: accountID)
    }

    /// Right-click selection and copy actions for a campaign row (#466).
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

        let selectedID = selectedCampaign.id

        return ScreenCampaignAction(id: "screen-campaign-\(selectedID)",
                                    clientIdentity: client.taskIdentity,
                                    contentFingerprint: selectedCampaign.name.hashValue) {
            guard let current = campaigns.first(where: { $0.id == selectedID }) else { return }

            Clipboard.copy(current.name)
        } showTests: {
            guard campaigns.contains(where: { $0.id == selectedID }) else { return }

            selectedCampaignID = selectedID
        }
    }

    /// The campaigns-list toolbar. An identified, customizable toolbar (so Customize
    /// Toolbar… is enabled here too, #464) with Reload hidden by default — ⌘R already
    /// reloads, so the button is opt-in via Customize Toolbar (#465).
    @ToolbarContentBuilder
    private var campaignsToolbar: some CustomizableToolbarContent {
        ToolbarItem(id: "create-campaign", placement: .automatic) {
            Button("New Screen Campaign", systemImage: "plus") { showCampaignCreation = true }
                .disabled(isReadOnly)
        }
        ToolbarItem(id: "question-bank", placement: .automatic) {
            Button("Screen Question Bank", systemImage: "books.vertical") { showQuestionBank = true }
        }
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

    /// Campaigns matching search/archive filters, pinned first. A selected campaign
    /// stays visible while the search field targets its candidate list.
    static func filteredCampaigns(
        _ campaigns: [ScreenCampaign],
        search: String,
        showArchived: Bool,
        hasSelection: Bool
    ) -> [ScreenCampaign] {
        filteredCampaigns(
            makeCampaignSearchIndex(campaigns),
            search: search,
            showArchived: showArchived,
            hasSelection: hasSelection
        )
    }

    static func makeCampaignSearchIndex(_ campaigns: [ScreenCampaign]) -> [CampaignSearchEntry] {
        campaigns
            .map { CampaignSearchEntry(campaign: $0, foldedName: $0.name.lowercased()) }
            .sorted { lhs, rhs in
                if lhs.campaign.pinned != rhs.campaign.pinned {
                    return lhs.campaign.pinned
                }
                return lhs.campaign.name.localizedStandardCompare(rhs.campaign.name) == .orderedAscending
            }
    }

    static func deduplicatedCampaigns(_ campaigns: [ScreenCampaign]) -> [ScreenCampaign] {
        ScreenCampaignDeduplication.firstByID(campaigns)
    }

    static func selectionAfterRefreshFailure(
        _ selectedID: Int?, campaigns: [ScreenCampaign]
    ) -> Int? {
        guard let selectedID, campaigns.contains(where: { $0.id == selectedID }) else { return nil }

        return selectedID
    }

    static func filteredCampaigns(
        _ index: [CampaignSearchEntry],
        search: String,
        showArchived: Bool,
        hasSelection: Bool
    ) -> [ScreenCampaign] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let query = hasSelection ? "" : trimmed
        return index.compactMap { entry in
            let campaign = entry.campaign
            guard showArchived || !campaign.archived,
                  query.isEmpty || entry.foldedName.contains(query) else { return nil }

            return campaign
        }
    }

    private func refreshDerived() {
        filtered = Self.filteredCampaigns(
            campaignSearchIndex,
            search: search,
            showArchived: showArchived,
            hasSelection: selectedCampaignID != nil
        )
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
                Label("Could not load campaigns", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        } else if campaigns.isEmpty, isLoading {
            ProgressView("Loading campaigns…")
        } else if filtered.isEmpty {
            ContentUnavailableView {
                Label("No campaigns", systemImage: "person.crop.rectangle.stack")
            } description: {
                Text(campaigns.isEmpty
                    ? "This account has no Screen campaigns yet."
                    : "No campaign matches your search.")
            } actions: {
                if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Clear Search") { search = "" }
                }
                if !showArchived {
                    Button("Show Archived") { showArchived = true }
                }
            }
        }
    }

    private func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        let requestedClientIdentity = client.taskIdentity
        isLoading = true
        defer {
            if Self.isCurrentLoad(generation, currentGeneration: loadGeneration,
                                  requestedClientIdentity: requestedClientIdentity,
                                  currentClientIdentity: client.taskIdentity) {
                isLoading = false
            }
        }
        do {
            let result = try await client.listCampaignsResult()
            guard !Task.isCancelled,
                  Self.isCurrentLoad(generation, currentGeneration: loadGeneration,
                                     requestedClientIdentity: requestedClientIdentity,
                                     currentClientIdentity: client.taskIdentity) else { return }

            // Selection, navigation, and SwiftUI row identity all use the remote
            // numeric id. Keep the first malformed duplicate deterministically so
            // a displayed row can never route to a different campaign (#5175).
            let uniqueCampaigns = Self.deduplicatedCampaigns(result.campaigns)
            campaigns = uniqueCampaigns
            campaignSearchIndex = Self.makeCampaignSearchIndex(uniqueCampaigns)
            loadError = result.diagnostic
            if let id = selectedCampaignID, !campaigns.contains(where: { $0.id == id }) {
                selectedCampaignID = nil
            }
            refreshDerived()
            // Re-publish now that rows exist: a selection restored before this load
            // couldn't publish (see `publishSelectedCampaign`), and a renamed
            // campaign should refresh the published copy (#997).
            publishSelectedCampaign(selectedCampaignID)
        } catch is CancellationError {
            // Leaving or re-keying this Screen section cancels its load deliberately.
        } catch {
            guard !Task.isCancelled,
                  Self.isCurrentLoad(generation, currentGeneration: loadGeneration,
                                     requestedClientIdentity: requestedClientIdentity,
                                     currentClientIdentity: client.taskIdentity) else { return }

            loadError = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
            // The rows deliberately remain as stale data after a transient failure;
            // keep their still-valid selection and detail context too (#5174).
            selectedCampaignID = Self.selectionAfterRefreshFailure(
                selectedCampaignID, campaigns: campaigns
            )
            publishSelectedCampaign(selectedCampaignID)
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
        Self.languageSummary(campaign.languages)
    }

    nonisolated static func languageSummary(_ languages: [String]) -> String {
        let maximumLabels = 5
        let candidates = languages.prefix(maximumLabels).compactMap { raw -> String? in
            let bounded = String(raw.prefix(64))
            let cleaned = String(bounded.unicodeScalars.filter { scalar in
                let category = scalar.properties.generalCategory
                return category != .control && category != .format
            }).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }

            return String(cleaned.coderPadLanguageDisplayName.prefix(32))
        }
        var labels = candidates
        if languages.count > maximumLabels {
            labels.append(String(localized: "More…"))
        }
        return labels.joined(separator: ", ")
    }
}

/// The Screen section's detail (third) column when no campaign is selected: prompt to
/// pick one. Once a campaign is selected its test sessions fill the detail column
/// (#448); a session's report opens in its own window (`ScreenTestDetailView`, #474).
struct ScreenDetailPlaceholder: View {
    var body: some View {
        DetailSelectionPlaceholder(kind: .campaign)
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
    // Separate samples keep the List ViewBuilder under the type-check budget.
    // The memberwise init validates its id and name, so each sample is optional and
    // the preview renders whichever survive.
    let backend = try? ScreenCampaign(id: 1, name: "Backend Engineer", languages: ["python", "go"], pinned: true)
    let frontend = try? ScreenCampaign(
        id: 2, name: "Frontend Engineer", languages: ["javascript"], archived: true
    )
    let dataScience = try? ScreenCampaign(id: 3, name: "Data Science", languages: ["python", "sql"])
    List {
        if let backend {
            ScreenCampaignRow(campaign: backend)
        }
        if let frontend {
            ScreenCampaignRow(campaign: frontend)
        }
        if let dataScience {
            ScreenCampaignRow(campaign: dataScience)
        }
    }
    .frame(width: 420, height: 240)
}
