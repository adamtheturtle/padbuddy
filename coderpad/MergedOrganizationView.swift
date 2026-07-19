//
//  MergedOrganizationView.swift
//  coderpad
//
//  The combined "All Accounts" Organization section. Each account is a distinct
//  org, so this presents two complementary layers: an aggregate header (user,
//  team, and pad counts genuinely sum across orgs, so the totals are meaningful)
//  and a compact per-account breakdown card. The full searchable user grid stays
//  in the single-account `OrganizationView`; the combined view's job is the
//  cross-account overview.
//
//  Fans out `organization()`, `organizationStats()`, and `quota()` across every
//  account concurrently (mirroring `MergedPadsView`), seeding from the org/quota
//  caches for an instant first paint. The stats window is shared across accounts
//  and refetched on its own when the period changes.
//

import MacPullToRefresh
import SwiftUI

struct MergedOrganizationView: View {
    @Environment(\.openAppSettings) private var openSettings
    @State private var accounts = AccountsStore.shared
    @State private var orgCache = OrganizationCacheStore.shared
    @State private var quotaCache = QuotaCacheStore.shared
    @State private var orgByAccount: [UUID: Organization] = [:]
    @State private var statsByAccount: [UUID: OrganizationStats] = [:]
    @State private var accountErrors: [UUID: String] = [:]
    @State private var isLoading = false
    @AppStorage(StatsPeriod.storageKey) private var period: StatsPeriod = .days7
    /// In-flight stats refetch, cancelled before a new one so a slower earlier
    /// response can't land on top of a newer window (as in `OrganizationView`).
    @State private var statsTask: Task<Void, Never>?
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd = Date()

    init() {
        // Keyless accounts are excluded so a cached org from before the key was
        // removed can't seed a stale card over the "no API key" note (#1033).
        let cachedOrgs = AccountsStore.shared.mergeableAccounts.compactMap { account -> (UUID, Organization)? in
            guard !account.apiKey.isEmpty,
                  let organization = OrganizationCacheStore.shared.get(account.id) else { return nil }

            return (account.id, organization)
        }
        _orgByAccount = State(initialValue: Dictionary(uniqueKeysWithValues: cachedOrgs))
    }

    /// Resolved (start, end) window for the active period, falling back to the
    /// custom pickers when no preset range applies.
    private var window: (start: Date, end: Date) {
        period.range() ?? (customStart, customEnd)
    }

    /// Identity of the stats window a request was made for, mirroring
    /// `OrganizationView.statsWindowToken`. The resolved `window` dates are
    /// now-anchored and never compare equal across reads, so guarding on them
    /// silently dropped every full reload's stats (#798).
    private var statsWindowToken: StatsWindowToken {
        StatsWindowToken(
            period: period,
            customStart: period == .custom ? customStart : nil,
            customEnd: period == .custom ? customEnd : nil
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if period == .custom { customRangeHeader }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    aggregateTiles
                    ForEach(accounts.mergeableAccounts) { account in
                        accountSection(account)
                    }
                }
                .padding(.horizontal, Spacing.paneH)
                .padding(.top, Spacing.paneV)
                .padding(.bottom, Spacing.paneV)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .macPullToRefresh { await reload() }
        }
        .task(id: accountKey) {
            seedFromCache()
            await reload()
        }
        .onChange(of: period) { _, _ in scheduleStatsReload() }
        .onChange(of: customStart) { _, _ in
            guard period == .custom else { return }

            scheduleStatsReload()
        }
        .onChange(of: customEnd) { _, _ in
            guard period == .custom else { return }

            scheduleStatsReload()
        }
        .onReloadRequest { await reload() }
        // The stats fetch is held in state rather than run from `.task`, so SwiftUI
        // doesn't cancel it when the view goes away — it would keep running and then
        // write into state nobody is showing (#2385).
        .onDisappear {
            statsTask?.cancel()
            statsTask = nil
        }
        .toolbar(id: "merged-organization") {
            ToolbarItem(id: "period", placement: .primaryAction) {
                periodPicker
            }
            // Hidden by default — reachable via View ▸ Customize Toolbar… or the
            // File ▸ Reload command (⌘R) (#413).
            ToolbarItem(id: "reload", placement: .automatic) {
                ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
            }
            .defaultCustomization(.hidden)
        }
    }

    /// The stats-period selector. On macOS the menu picker shows the selected
    /// window inline (there's room for it); on iPad it's a primary toolbar Menu
    /// with a calendar glyph so users don't have to open the generic overflow
    /// before choosing a date window.
    @ViewBuilder
    private var periodPicker: some View {
        #if os(macOS)
            Picker("Period", selection: $period) {
                ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .help("Stats period")
        #else
            Menu {
                Picker("Period", selection: $period) {
                    ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Period", systemImage: "calendar")
            }
            .help("Stats period")
        #endif
    }

    /// The custom From/To range, pinned above the ScrollView so it stays visible
    /// while scrolling the per-account breakdown. It stays out of the toolbar
    /// because the date fields' width varies and they only apply to one period.
    private var customRangeHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                DatePicker("From", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                #if os(macOS)
                    .datePickerStyle(.field)
                #else
                    .datePickerStyle(.compact)
                #endif
                DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                #if os(macOS)
                    .datePickerStyle(.field)
                #else
                    .datePickerStyle(.compact)
                #endif
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.paneH)
            .padding(.vertical, 12)
            Divider()
        }
    }

    // MARK: - Aggregate

    private var totalPads: Int {
        accounts.mergeableAccounts.compactMap { statsByAccount[$0.id]?.padsCreated }.reduce(0, +)
    }

    private var aggregateTiles: some View {
        // Build the merged organization slice once per body evaluation; the three
        // aggregate readers previously rebuilt it independently (#2128).
        let loadedOrgs = accounts.mergeableAccounts.compactMap { orgByAccount[$0.id] }
        let totalUsers = loadedOrgs.reduce(0) { $0 + ($1.userCount ?? $1.users.count) }
        let totalTeams = loadedOrgs.reduce(0) { $0 + $1.teams.count }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
            AggregateStatTile(title: "Organizations", value: "\(loadedOrgs.count)",
                              systemImage: "building.2.fill", tint: .purple)
            AggregateStatTile(title: "Users", value: "\(totalUsers)",
                              systemImage: "person.3.fill", tint: .blue)
            AggregateStatTile(title: "Teams", value: "\(totalTeams)",
                              systemImage: "rectangle.stack.person.crop", tint: .indigo)
            // No timeframe in the title: the toolbar's period picker already states
            // the window these pad counts cover, so repeating it here is redundant.
            AggregateStatTile(title: "Pads", value: "\(totalPads)",
                              systemImage: "doc.text.fill", tint: .teal)
        }
    }

    // MARK: - Per-account

    private func accountSection(_ account: Account) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                AccountSectionHeader(account: account)
                // The keyless branch comes first so an org card left over from
                // before the key was removed can never win over the "no API key"
                // note (#1033).
                if account.apiKey.isEmpty {
                    Text("No API key for this account.")
                        .font(.callout).foregroundStyle(.secondary)
                } else if let org = orgByAccount[account.id] {
                    // A recorded refresh failure must stay visible even while a
                    // cached breakdown is shown, or stale org data poses as
                    // current - mirroring MergedQuotaView (#996).
                    if let error = accountErrors[account.id] {
                        StaleRefreshBanner(message: error) { Task { await reload() } }
                    }
                    orgBreakdown(org, account: account)
                } else if let error = accountErrors[account.id] {
                    // The unauthorized message points the user at this account's
                    // settings; give them a one-click way there rather than leaving
                    // them to hunt for it (no detail pane carries the linked button
                    // the single-account APIErrorView shows).
                    VStack(alignment: .leading, spacing: 6) {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Open Account Settings") { openAccountSettings(account) }
                            .linkButtonStyle()
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Opens Settings on the Accounts tab with this account selected for editing,
    /// so a rejected key can be fixed where the error told the user to look.
    private func openAccountSettings(_ account: Account) {
        let navigation = SettingsNavigation.shared
        navigation.selectedTab = .accounts
        navigation.accountToEdit = account.id
        openSettings()
    }

    private func orgBreakdown(_ org: Organization, account: Account) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledRow(label: "Organization", value: org.organizationName)
            LabeledRow(label: "Users", value: "\(org.userCount ?? org.users.count)")
            LabeledRow(label: "Teams", value: "\(org.teams.count)")
            if let stats = statsByAccount[account.id] {
                LabeledRow(label: "Pads", value: "\(stats.padsCreated)")
            }
            if let sso = org.singleSignOnSupported {
                LabeledRow(label: "Single sign-on",
                           value: sso ? String(localized: "Enabled") : String(localized: "Disabled"))
            }
        }
    }
}

// MARK: - Loading

private extension MergedOrganizationView {
    /// A token covering the set of accounts being merged (ids, keys, and endpoints),
    /// so the load task restarts when an account is added, removed, rekeyed, or its
    /// Server URL changes - matching `MergedPadsView.accountKey`. Encoding only key
    /// presence missed non-empty rekeys and endpoint edits, leaving a stale or
    /// wrong-org directory painting as current (#993/#1033).
    var accountKey: [FilterSignature] {
        accounts.mergeableAccounts.map {
            FilterSignature.make([
                $0.id.uuidString,
                $0.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                $0.resolvedBaseURL.absoluteString
            ])
        }
    }

    /// Drops the in-memory entries for accounts whose key was removed, so a card
    /// cached before the removal can't outlive the "no API key" note (#1033).
    func clearKeylessEntries() {
        for account in accounts.mergeableAccounts where account.apiKey.isEmpty {
            orgByAccount[account.id] = nil
            statsByAccount[account.id] = nil
            accountErrors[account.id] = nil
        }
    }

    func seedFromCache() {
        clearKeylessEntries()
        for account in accounts.mergeableAccounts
            where orgByAccount[account.id] == nil && !account.apiKey.isEmpty {
            orgByAccount[account.id] = orgCache.get(account.id)
        }
    }

    /// Fan out a fresh org/stats/quota fetch across every account concurrently,
    /// applying each account's result as it lands and isolating its failure.
    func reload() async {
        clearKeylessEntries()
        let mergeable = accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }
        guard !mergeable.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }
        let requestedWindow = window
        let requestedToken = statsWindowToken
        let targets = mergeable.map { (id: $0.id, client: $0.makeClient()) }
        let clientsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.client) })
        await withTaskGroup(of: (UUID, Organization?, OrganizationStats?, Quota?, String?).self) { group in
            for target in targets {
                group.addTask {
                    do {
                        async let orgFetch = target.client.organization()
                        async let statsFetch = target.client.organizationStats(start: requestedWindow.start,
                                                                               end: requestedWindow.end)
                        async let quotaFetch = target.client.quota()
                        let org = try await orgFetch
                        return await (target.id, org, try? statsFetch, try? quotaFetch, nil)
                    } catch {
                        return (target.id, nil, nil, nil, error.localizedDescription)
                    }
                }
            }
            for await (id, org, stats, quota, errorText) in group {
                if let org {
                    orgByAccount[id] = org
                    if let client = clientsByID[id] {
                        orgCache.set(id, organization: org, via: client)
                    }
                    accountErrors[id] = nil
                } else if let errorText {
                    accountErrors[id] = errorText
                }
                // Org and quota are window-independent, but stats were fetched for
                // `requestedWindow`. If the period picker has since changed (a newer
                // reloadStats is the authority now), drop these to avoid overwriting
                // fresh stats with counts for the old period. #384/#798
                if let stats, requestedToken == statsWindowToken { statsByAccount[id] = stats }
                if let quota, let client = clientsByID[id] {
                    quotaCache.set(id, quota: quota, via: client)
                }
            }
        }
    }

    func scheduleStatsReload() {
        statsTask?.cancel()
        statsTask = Task {
            // Settle first, like the single-account view: cancelling doesn't recall a
            // request already in flight, and here each one fans out across every
            // account — so a dragged date picker multiplied by the account count
            // (#2384). A cancelled sleep returns before any request is made.
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }

            await reloadStats()
        }
    }

    /// Refetch just the stats for the new window across every account, leaving the
    /// loaded orgs and quotas in place.
    func reloadStats() async {
        let mergeable = accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }
        guard !mergeable.isEmpty else { return }

        let window = window
        let requestedToken = statsWindowToken
        let targets = mergeable.map { (id: $0.id, client: $0.makeClient()) }
        await withTaskGroup(of: (UUID, OrganizationStats?).self) { group in
            for target in targets {
                group.addTask {
                    await (target.id, try? target.client.organizationStats(start: window.start, end: window.end))
                }
            }
            for await (id, stats) in group {
                guard !Task.isCancelled, requestedToken == statsWindowToken else { return }

                if let stats { statsByAccount[id] = stats }
            }
        }
    }
}
