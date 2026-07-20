//
//  MergedOrganizationView.swift
//  coderpad
//

import MacPullToRefresh
import SwiftUI

struct MergedOrganizationView: View {
    @Environment(\.openAppSettings) private var openSettings
    @State var accounts = AccountsStore.shared
    @State var orgCache = OrganizationCacheStore.shared
    @State var quotaCache = QuotaCacheStore.shared
    @State var orgByAccount: [UUID: Organization] = [:]
    @State var statsByAccount: [UUID: OrganizationStats] = [:]
    @State var statsFailures: Set<UUID> = []
    @State var accountErrors: [UUID: String] = [:]
    @State private var isLoading = false
    @State private var reloadGeneration = 0
    @AppStorage(StatsPeriod.storageKey) private var period: StatsPeriod = .days7
    @State private var statsTask: Task<Void, Never>?
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd = Date()

    init() {
        let cachedOrgs = AccountsStore.shared.mergeableAccounts.compactMap { account -> (UUID, Organization)? in
            guard !account.apiKey.isEmpty,
                  let organization = OrganizationCacheStore.shared.get(account.id, via: account.makeClient())
            else { return nil }

            return (account.id, organization)
        }
        _orgByAccount = State(initialValue: Dictionary(uniqueKeysWithValues: cachedOrgs))
    }

    private var window: (start: Date, end: Date) {
        period.range() ?? StatsPeriod.boundedCustomRange(start: customStart, end: customEnd)
    }

    var statsWindowToken: StatsWindowToken {
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
            AggregateStatTile(title: "Pads", value: statsFailures.isEmpty ? "\(totalPads)" : "—",
                              systemImage: "doc.text.fill", tint: .teal)
        }
    }

    // MARK: - Per-account

    private func accountSection(_ account: Account) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                AccountSectionHeader(account: account)
                if statsFailures.contains(account.id) {
                    StaleRefreshBanner(message: "The pad stats request failed.") { scheduleStatsReload() }
                }
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
    var accountKey: [MergedAccountToken] {
        accounts.mergeableAccounts.map(MergedAccountToken.init(account:))
    }

    func clearKeylessEntries() {
        let eligibleIDs = Set(accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }.map(\.id))
        orgByAccount = Self.retainingEntries(orgByAccount, for: eligibleIDs)
        statsByAccount = Self.retainingEntries(statsByAccount, for: eligibleIDs)
        accountErrors = Self.retainingEntries(accountErrors, for: eligibleIDs)
    }

    func seedFromCache() {
        clearKeylessEntries()
        for account in accounts.mergeableAccounts
            where orgByAccount[account.id] == nil && !account.apiKey.isEmpty {
            orgByAccount[account.id] = orgCache.get(account.id, via: account.makeClient())
        }
    }

    func reload() async {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        clearKeylessEntries()
        let mergeable = accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }
        guard !mergeable.isEmpty else {
            isLoading = false
            return
        }

        isLoading = true
        defer {
            if Self.isCurrentReload(generation, current: reloadGeneration) { isLoading = false }
        }
        let requestedWindow = window
        let requestedToken = statsWindowToken
        let targets = mergeable.map { MergedOrganizationReloadTarget(id: $0.id, client: $0.makeClient()) }
        let targetsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
        await withTaskGroup(of: MergedOrganizationReloadResult.self) { group in
            var iterator = targets.makeIterator()
            for _ in 0 ..< min(4, targets.count) {
                if let target = iterator.next() {
                    group.addTask { await Self.fetch(target, window: requestedWindow) }
                }
            }
            for await result in group {
                guard !Task.isCancelled,
                      Self.isCurrentReload(generation, current: reloadGeneration) else {
                    group.cancelAll()
                    return
                }

                if let target = iterator.next() {
                    group.addTask { await Self.fetch(target, window: requestedWindow) }
                }

                guard let target = targetsByID[result.id], let client = currentClient(for: target) else {
                    discardStaleResult(for: result.id)
                    continue
                }

                applyReloadResult(result, requestedToken: requestedToken, client: client)
            }
        }
    }

    func scheduleStatsReload() {
        statsTask?.cancel()
        statsByAccount = [:]
        statsFailures = []
        statsTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }

            await reloadStats()
        }
    }

    func reloadStats() async {
        let mergeable = accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }
        guard !mergeable.isEmpty else { return }

        let window = window
        let requestedToken = statsWindowToken
        let targets = mergeable.map { MergedOrganizationReloadTarget(id: $0.id, client: $0.makeClient()) }
        statsByAccount = [:]
        statsFailures = []
        let results = await withTaskGroup(
            of: MergedOrganizationStatsResult.self,
            returning: [MergedOrganizationStatsResult].self
        ) { group in
            var iterator = targets.makeIterator()
            func fetch(_ target: MergedOrganizationReloadTarget) async -> MergedOrganizationStatsResult {
                await MergedOrganizationStatsResult(
                    id: target.id,
                    clientIdentity: target.clientIdentity,
                    stats: try? target.client.organizationStats(start: window.start, end: window.end)
                )
            }
            for _ in 0 ..< min(4, targets.count) {
                if let target = iterator.next() { group.addTask { await fetch(target) } }
            }
            var collected: [MergedOrganizationStatsResult] = []
            for await result in group {
                collected.append(result)
                if let target = iterator.next() { group.addTask { await fetch(target) } }
            }
            return collected
        }
        guard !Task.isCancelled, requestedToken == statsWindowToken else { return }

        let currentResults = results.filter { result in
            let current = accounts.mergeableAccounts.first(where: { $0.id == result.id })?.makeClient().taskIdentity
            return Self.isCurrentTarget(result.clientIdentity, current: current)
        }
        statsByAccount = Dictionary(uniqueKeysWithValues: currentResults.compactMap { result in
            result.stats.map { (result.id, $0) }
        })
        statsFailures = Set(currentResults.compactMap { $0.stats == nil ? $0.id : nil })
    }
}
