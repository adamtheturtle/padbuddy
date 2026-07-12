//
//  MergedScreenView.swift
//  coderpad
//
//  The combined "All Accounts" Screen section (#442). Aggregates Screen campaigns
//  across every mergeable account that has a Screen key, tagging each row with its
//  source account so selecting a campaign — and showing its test sessions in the
//  detail column (#448) — routes to the right account's `ScreenClient` (campaign and
//  test ids are numbered per org). Accounts without a Screen key are simply absent.
//  Each account's client carries its own region base URL, so a US/EU mix fans out
//  correctly. Mirrors `ScreenCampaignsView`'s campaign selection and
//  `MergedOrganizationView`'s concurrent per-account fan-out.
//

import SwiftUI

/// A Screen campaign paired with the account it belongs to. `id` namespaces the
/// per-org campaign id by account so the list selection stays unambiguous even when
/// two orgs share a campaign id.
struct ScopedScreenCampaign: Identifiable, Hashable {
    let accountID: UUID
    let account: RowAccount
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
    /// The selected campaign (namespaced id, account + per-org campaign id). Selecting a
    /// campaign drives the detail column's test-sessions list and routes it to that
    /// campaign's account `ScreenClient` (#448); single-click never swaps this list.
    @State private var selectedScopedID: String?

    var body: some View {
        List(selection: $selectedScopedID) {
            ForEach(filtered) { scoped in
                MergedScreenCampaignRow(scoped: scoped)
                    .tag(scoped.id)
                    .contextMenu { campaignActions(scoped) }
                    .draggable(scoped.copyText)
            }
        }
        .overlay { statusOverlay }
        // The campaign count with nothing selected; the selected campaign's candidate
        // count once chosen (published by the tests list via AppNavigation, #475).
        .reportsSectionCount(selectedScopedID == nil ? countSubtitle : nav.screenTestsSubtitle)
        .toolbar(id: "merged-screen") { toolbar }
        .focusedSceneValue(\.focusedScreenCampaignAction, selectedCampaignAction)
        #if os(macOS)
            .onCopyCommand(perform: copyLinkCommand(hasSelection: selectedCampaign != nil) {
                selectedCampaign?.copyText ?? ""
            })
        #endif
            .task(id: accountKey) { await load() }
            // Reload on ⌘R like the other lists (AppRouter.requestReload()).
            .task {
                for await _ in AppRouter.reloads {
                    await load()
                }
            }
            // Restore the published selection on appear, and publish each change onward so the
            // detail column shows the campaign's tests, routed to the right account (#448).
            .onAppear { restoreSelectedCampaign() }
            .onChange(of: selectedScopedID) { _, id in publishSelectedCampaign(id) }
    }

    private func restoreSelectedCampaign() {
        let id: String? = if let account = routing.selectedScreenAccountID, let campaign = nav.screenCampaignSelection {
            "\(account.uuidString):\(campaign.id)"
        } else {
            nil
        }
        guard selectedScopedID != id else { return }

        DispatchQueue.main.async {
            if selectedScopedID != id { selectedScopedID = id }
        }
    }

    private func publishSelectedCampaign(_ id: String?) {
        let scoped = scopedCampaign(id: id)
        let campaign = scoped?.campaign
        let accountID = scoped?.accountID
        guard nav.screenCampaignSelection != campaign || routing.selectedScreenAccountID != accountID else { return }

        DispatchQueue.main.async {
            if nav.screenCampaignSelection != campaign { nav.screenCampaignSelection = campaign }
            if routing.selectedScreenAccountID != accountID { routing.selectedScreenAccountID = accountID }
        }
    }

    /// Right-click actions for a campaign row, mirroring the single-account view
    /// (#466): select it to show its test sessions in the detail column, or copy its
    /// name. The Screen API exposes no per-campaign mutations.
    @ViewBuilder
    private func campaignActions(_ scoped: ScopedScreenCampaign) -> some View {
        Button("Show Test Sessions") { selectedScopedID = scoped.id }
        Button("Copy Name") { Clipboard.copy(scoped.copyText) }
    }

    private var selectedCampaign: ScopedScreenCampaign? {
        scopedCampaign(id: selectedScopedID)
    }

    private var selectedCampaignAction: ScreenCampaignAction? {
        guard let selectedCampaign else { return nil }

        return ScreenCampaignAction(id: "merged-screen-campaign-\(selectedCampaign.id)") {
            Clipboard.copy(selectedCampaign.copyText)
        } showTests: {
            selectedScopedID = selectedCampaign.id
        }
    }

    /// Resolves a namespaced row id back to its account-scoped campaign across the loaded
    /// set, so a selection can route to the right account's `ScreenClient`.
    private func scopedCampaign(id: String?) -> ScopedScreenCampaign? {
        guard let id else { return nil }

        for (account, _) in screenAccounts {
            for campaign in campaignsByAccount[account.id] ?? [] {
                let scoped = ScopedScreenCampaign(accountID: account.id, account: RowAccount(account),
                                                  campaign: campaign)
                if scoped.id == id { return scoped }
            }
        }
        return nil
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
        // While a campaign is selected the search field targets its candidates (the
        // detail column), so this list ignores the query then — keeping it in view.
        let query = selectedScopedID == nil ? search.trimmingCharacters(in: .whitespaces).lowercased() : ""
        let scoped = screenAccounts.flatMap { account, _ in
            (campaignsByAccount[account.id] ?? []).map {
                ScopedScreenCampaign(accountID: account.id, account: RowAccount(account), campaign: $0)
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
                return lhs.account.name.localizedStandardCompare(rhs.account.name) == .orderedAscending
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
        // If the selected campaign vanished (deleted, or its account lost its key),
        // clear the selection so the detail column stops showing its tests.
        if let id = selectedScopedID, scopedCampaign(id: id) == nil {
            selectedScopedID = nil
        }
    }
}

extension ScopedScreenCampaign {
    var copyText: String {
        "\(campaign.name)\t\(account.name)"
    }
}

/// One merged campaign row: the campaign's own row plus a label naming its source
/// account, matching the account tag on merged pad/question rows.
struct MergedScreenCampaignRow: View {
    let scoped: ScopedScreenCampaign

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScreenCampaignRow(campaign: scoped.campaign)
            AccountMetaLabel(account: scoped.account)
        }
        .contentShape(Rectangle())
    }
}

#Preview("Merged campaign rows") {
    // Build the sample data in its own statements so the List ViewBuilder
    // expression stays under the 250ms type-check budget (warnings-as-errors
    // makes an overrun a fatal build error).
    let backend = ScopedScreenCampaign(
        accountID: UUID(), account: RowAccount(Account(name: "Acme", apiKey: "")),
        campaign: ScreenCampaign(id: 1, name: "Backend Engineer", languages: ["python"], pinned: true)
    )
    let frontend = ScopedScreenCampaign(
        accountID: UUID(), account: RowAccount(Account(name: "Globex", apiKey: "")),
        campaign: ScreenCampaign(id: 2, name: "Frontend Engineer", languages: ["javascript"])
    )
    List {
        MergedScreenCampaignRow(scoped: backend)
        MergedScreenCampaignRow(scoped: frontend)
    }
    .frame(width: 460, height: 200)
}
