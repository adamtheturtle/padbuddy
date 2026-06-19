//
//  MergedScreenView.swift
//  coderpad
//
//  The combined "All Accounts" Screen section (#442). Aggregates Screen campaigns
//  across every mergeable account that has a Screen key, tagging each row with its
//  source account so drilling into a campaign — and the selected test's report in
//  the detail column — routes to the right account's `ScreenClient` (campaign and
//  test ids are numbered per org). Accounts without a Screen key are simply absent.
//  Each account's client carries its own region base URL, so a US/EU mix fans out
//  correctly. Mirrors `ScreenCampaignsView`'s campaigns → tests drill-down and
//  `MergedOrganizationView`'s concurrent per-account fan-out.
//

import SwiftUI

/// A Screen campaign paired with the account it belongs to. `id` namespaces the
/// per-org campaign id by account so the list and the `NavigationStack` path stay
/// unambiguous even when two orgs share a campaign id.
struct ScopedScreenCampaign: Identifiable, Hashable {
    let accountID: UUID
    let accountName: String
    let campaign: ScreenCampaign
    var id: String {
        "\(accountID.uuidString):\(campaign.id)"
    }
}

/// The combined Screen section's content column: campaigns from every Screen-enabled
/// account in one list, each tagged with its source account.
struct MergedScreenView: View {
    @Binding var search: String
    @State private var accounts = AccountsStore.shared
    @State private var routing = MergedRouting.shared
    @State private var nav = AppNavigation.shared
    @State private var campaignsByAccount: [UUID: [ScreenCampaign]] = [:]
    @State private var accountErrors: [UUID: String] = [:]
    @State private var isLoading = false
    @State private var showArchived = false
    /// The campaigns → tests drill-down path, carrying the account so the pushed
    /// tests list and the detail column talk to the right `ScreenClient`.
    @State private var path: [ScopedScreenCampaign] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(filtered) { scoped in
                    NavigationLink(value: scoped) {
                        MergedScreenCampaignRow(scoped: scoped)
                    }
                    .contextMenu { campaignActions(scoped) }
                }
            }
            .overlay { statusOverlay }
            // The campaign count at the list; the drilled-into campaign's candidate
            // count once pushed (published by the tests list via AppNavigation, #475).
            .reportsSectionCount(path.isEmpty ? countSubtitle : nav.screenTestsSubtitle)
            .navigationDestination(for: ScopedScreenCampaign.self) { scoped in
                destination(for: scoped)
            }
            .toolbar(id: "merged-screen") { toolbar }
        }
        .task(id: accountKey) { await load() }
        // Reload on ⌘R like the other lists (AppRouter.requestReload()).
        .task {
            for await _ in AppRouter.reloads {
                await load()
            }
        }
        // The drilled-into campaign drives the detail column's context and which
        // account's client it routes to; clear both on popping back to the list.
        .onChange(of: path) { _, newPath in
            nav.screenCampaignSelection = newPath.last?.campaign
            routing.selectedScreenAccountID = newPath.last?.accountID
            if newPath.isEmpty { nav.screenTestSelection = nil }
        }
    }

    @ViewBuilder
    private func destination(for scoped: ScopedScreenCampaign) -> some View {
        if let account = accounts.accounts.first(where: { $0.id == scoped.accountID }),
           let client = account.makeScreenClient() {
            ScreenTestsView(client: client, campaign: scoped.campaign,
                            search: $search, accountID: scoped.accountID)
        } else {
            ContentUnavailableView("Account unavailable", systemImage: "person.crop.rectangle.stack")
        }
    }

    /// Right-click actions for a campaign row, mirroring the single-account view
    /// (#466): drill into its test sessions, or copy its name. The Screen API
    /// exposes no per-campaign mutations.
    @ViewBuilder
    private func campaignActions(_ scoped: ScopedScreenCampaign) -> some View {
        Button("Show Test Sessions") { path = [scoped] }
        Button("Copy Name") { Clipboard.copy(scoped.campaign.name) }
    }

    /// An identified, customizable toolbar (so Customize Toolbar… stays enabled here,
    /// #464). The per-account webhook is deliberately omitted — it targets one
    /// account, so it stays in the single-account view; invite/cancel/resend/delete
    /// remain available once drilled into a campaign (a single-account context).
    @ToolbarContentBuilder
    private var toolbar: some CustomizableToolbarContent {
        ToolbarItem(id: "show-archived", placement: .automatic) {
            Toggle(isOn: $showArchived) {
                Label("Show Archived", systemImage: "archivebox")
            }
            .help("Include archived campaigns in the list.")
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

    // MARK: - Data

    /// Mergeable accounts that have a Screen client, paired with it. Accounts without
    /// a Screen key never appear in the combined Screen view.
    private var screenAccounts: [(account: Account, client: ScreenClient)] {
        accounts.mergeableAccounts.compactMap { account in
            account.makeScreenClient().map { (account, $0) }
        }
    }

    /// All loaded campaigns flattened to account-scoped rows, filtered by the search
    /// and archived toggles. Pinned first, then by name, then by account so the order
    /// is stable and predictable.
    private var filtered: [ScopedScreenCampaign] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let scoped = screenAccounts.flatMap { account, _ in
            (campaignsByAccount[account.id] ?? []).map {
                ScopedScreenCampaign(accountID: account.id, accountName: account.name, campaign: $0)
            }
        }
        return scoped
            .filter { (showArchived || !$0.campaign.archived)
                && (query.isEmpty || $0.campaign.name.lowercased().contains(query))
            }
            .sorted { lhs, rhs in
                if lhs.campaign.pinned != rhs.campaign.pinned { return lhs.campaign.pinned }
                let byName = lhs.campaign.name.localizedStandardCompare(rhs.campaign.name)
                if byName != .orderedSame { return byName == .orderedAscending }
                return lhs.accountName.localizedStandardCompare(rhs.accountName) == .orderedAscending
            }
    }

    private var hasAnyCampaign: Bool {
        campaignsByAccount.values.contains { !$0.isEmpty }
    }

    /// Every Screen-enabled account failed and none has cached/loaded campaigns —
    /// the only case that warrants a full error state rather than partial results.
    private var allFailed: Bool {
        !hasAnyCampaign && !screenAccounts.isEmpty
            && screenAccounts.allSatisfy { accountErrors[$0.account.id] != nil }
    }

    private var countSubtitle: String {
        guard hasAnyCampaign else { return "" }

        let count = filtered.count
        return count == 1
            ? String(localized: "\(count) campaign")
            : String(localized: "\(count) campaigns")
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if allFailed {
            ContentUnavailableView {
                Label("Couldn't load campaigns", systemImage: "exclamationmark.triangle")
            } description: {
                Text("None of your Screen accounts could load campaigns.")
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        } else if !hasAnyCampaign, isLoading {
            ProgressView()
        } else if filtered.isEmpty {
            ContentUnavailableView {
                Label("No campaigns", systemImage: "person.crop.rectangle.stack")
            } description: {
                Text(hasAnyCampaign
                    ? "No campaign matches your search."
                    : "Your Screen accounts have no campaigns yet.")
            }
        }
    }

    /// A token covering the Screen account set (ids + key + region) so the load task
    /// restarts when a Screen key is added, removed, rekeyed, or re-regioned —
    /// matching `MergedOrganizationView.accountKey`.
    private var accountKey: String {
        screenAccounts
            .map { "\($0.account.id.uuidString):\($0.account.screenApiKey ?? ""):\($0.account.screenRegion.rawValue)" }
            .joined(separator: ",")
    }

    /// Fan out `listCampaigns()` across every Screen-enabled account concurrently,
    /// applying each result as it lands and isolating per-account failure.
    private func load() async {
        let targets = screenAccounts
        guard !targets.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }
        await withTaskGroup(of: (UUID, [ScreenCampaign]?, String?).self) { group in
            for target in targets {
                group.addTask {
                    do {
                        return try await (target.account.id, target.client.listCampaigns(), nil)
                    } catch {
                        let message = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
                        return (target.account.id, nil, message)
                    }
                }
            }
            for await (id, campaigns, errorText) in group {
                if let campaigns {
                    campaignsByAccount[id] = campaigns
                    accountErrors[id] = nil
                } else if let errorText {
                    accountErrors[id] = errorText
                }
            }
        }
        // If the drilled-into campaign vanished (deleted, or its account lost its key),
        // pop back to the campaigns list.
        if let top = path.last,
           !(campaignsByAccount[top.accountID]?.contains { $0.id == top.campaign.id } ?? false) {
            path.removeAll()
        }
    }
}

/// One merged campaign row: the campaign's own row plus a label naming its source
/// account, matching the account tag on merged pad/question rows.
struct MergedScreenCampaignRow: View {
    let scoped: ScopedScreenCampaign

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScreenCampaignRow(campaign: scoped.campaign)
            MetaLabel(text: scoped.accountName, systemImage: "person.crop.circle")
        }
        .contentShape(Rectangle())
    }
}

#Preview("Merged campaign rows") {
    List {
        MergedScreenCampaignRow(scoped: ScopedScreenCampaign(
            accountID: UUID(), accountName: "Acme",
            campaign: ScreenCampaign(id: 1, name: "Backend Engineer", languages: ["python"], pinned: true)
        ))
        MergedScreenCampaignRow(scoped: ScopedScreenCampaign(
            accountID: UUID(), accountName: "Globex",
            campaign: ScreenCampaign(id: 2, name: "Frontend Engineer", languages: ["javascript"])
        ))
    }
    .frame(width: 460, height: 200)
}
