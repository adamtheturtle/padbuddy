//
//  MergedOrganizationView.swift
//  coderpad
//

// swiftlint:disable file_length

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
    @State var quotaFailures: Set<UUID> = []
    @State var quotaLoadingIDs: Set<UUID> = []
    @State var quotaReloadGenerations: [UUID: Int] = [:]
    @State var accountErrors: [UUID: String] = [:]
    @State private var isLoading = false
    @State private var reloadGeneration = 0
    @State var statsReloadGeneration = 0
    @State private var period: StatsPeriod = .days7
    @State private var statsTask: Task<Void, Never>?
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd = Date()

    init() {
        let customRange = StatsPeriod.persistedCustomRange(scope: "merged")
        _customStart = State(initialValue: customRange.start)
        _customEnd = State(initialValue: customRange.end)
        let cachedOrgs = AccountsStore.shared.mergeableAccounts.compactMap { account -> (UUID, Organization)? in
            guard !account.apiKey.isEmpty,
                  let organization = OrganizationCacheStore.shared.get(account.id, via: account.makeClient())
            else { return nil }

            return (account.id, organization)
        }
        _orgByAccount = State(initialValue: Dictionary(cachedOrgs, uniquingKeysWith: { first, _ in first }))
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
            if period == .custom {
                customRangeHeader
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let message = aggregateFailureMessage {
                        AggregateFailureBanner(message: message) { Task { await reload() } }
                    }
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

            StatsPeriod.persistCustomRange(start: customStart, end: customEnd, scope: "merged")
            scheduleStatsReload()
        }
        .onChange(of: customEnd) { _, _ in
            guard period == .custom else { return }

            StatsPeriod.persistCustomRange(start: customStart, end: customEnd, scope: "merged")
            scheduleStatsReload()
        }
        .onReloadRequest { await reload() }
        .focusedSceneValue(\.statsPeriodSelection, $period)
        // Keep the stats task in state so disappearance can cancel it (#2385).
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

    /// Period selector: inline on macOS and a compact calendar menu on iPad.
    @ViewBuilder
    private var periodPicker: some View {
        #if os(macOS)
            Picker("Period", selection: $period) {
                ForEach(StatsPeriod.allCases) { Text($0.displayLabel).tag($0) }
            }
            .pickerStyle(.menu)
            .help("Stats period")
        #else
            Menu {
                Picker("Period", selection: $period) {
                    ForEach(StatsPeriod.allCases) { Text($0.displayLabel).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Period", systemImage: "calendar")
            }
            .help("Stats period")
        #endif
    }

    /// The custom range stays pinned above the per-account breakdown.
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

    private var aggregateFailureMessage: String? {
        let failedIDs = Set(accountErrors.keys).union(statsFailures)
        let failedAccounts = accounts.mergeableAccounts.filter { failedIDs.contains($0.id) }
        guard !failedAccounts.isEmpty else { return nil }

        let names = failedAccounts.map(Self.aggregateAccountName).joined(separator: ", ")
        let accountWord = failedAccounts.count == 1 ? "account" : "accounts"
        return String(localized: "Totals exclude \(failedAccounts.count) failing \(accountWord): \(names).")
    }

    private var aggregateTiles: some View {
        // Build the merged organization slice once per body evaluation; the three
        // aggregate readers previously rebuilt it independently (#2128).
        let eligibleIDs = Set(accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }.map(\.id))
        let orgFailedIDs = Set(accountErrors.keys).intersection(eligibleIDs)
        let loadedOrgIDs = eligibleIDs.subtracting(orgFailedIDs)
        let loadedOrgs = loadedOrgIDs.compactMap { orgByAccount[$0] }
        let totalUsersText = AggregateCounterSum.displayText(
            of: loadedOrgs.map { $0.userCount ?? $0.users.count }
        )
        let totalTeams = loadedOrgs.reduce(0) { $0 + $1.teams.count }
        let orgCoverage = AggregateCoverage.resolve(
            eligibleIDs: eligibleIDs,
            loadedIDs: Set(orgByAccount.keys),
            failedIDs: Set(accountErrors.keys)
        )
        let statsCoverage = AggregateCoverage.resolve(
            eligibleIDs: eligibleIDs,
            loadedIDs: Set(statsByAccount.keys),
            failedIDs: statsFailures
        )
        let totalPadsText = AggregateCounterSum.displayText(
            of: eligibleIDs.compactMap { statsByAccount[$0]?.padsCreated }
        )

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
            AggregateStatTile(title: "Organizations", value: orgCoverage.displayValue("\(loadedOrgs.count)"),
                              systemImage: "building.2.fill", tint: .purple, coverage: orgCoverage)
            AggregateStatTile(title: "Users", value: orgCoverage.displayValue(totalUsersText),
                              systemImage: "person.3.fill", tint: .blue, coverage: orgCoverage)
            AggregateStatTile(title: "Teams", value: orgCoverage.displayValue("\(totalTeams)"),
                              systemImage: "rectangle.stack.person.crop", tint: .indigo, coverage: orgCoverage)
            // No timeframe in the title: the toolbar's period picker already states
            // the window these pad counts cover, so repeating it here is redundant.
            AggregateStatTile(title: "Pads", value: statsCoverage.displayValue(totalPadsText),
                              systemImage: "doc.text.fill", tint: .teal, coverage: statsCoverage)
        }
    }

    private static func aggregateAccountName(_ account: Account) -> String {
        let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }

        let email = account.userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? String(localized: "Account") : email
    }

    // MARK: - Per-account

    private func accountSection(_ account: Account) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                AccountSectionHeader(account: account)
                let statsFailed = statsFailures.contains(account.id)
                let quotaFailed = quotaFailures.contains(account.id)
                if let message = Self.secondaryRefreshFailureMessage(
                    statsFailed: statsFailed, quotaFailed: quotaFailed
                ) {
                    // Stats and quota are fetched together and commonly fail for the
                    // same systemic reason (notably a 429). Present one stale-data
                    // warning and let its retry cover every failed resource (#2884).
                    StaleRefreshBanner(message: message) {
                        if statsFailed {
                            scheduleStatsReload()
                        }
                        if quotaFailed {
                            Task { await reloadQuota(for: account) }
                        }
                    }
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
    /// Restarts loading when the merged account set, credentials, or endpoints
    /// change, so stale organization data cannot survive re-keying (#993/#1033).
    var accountKey: [MergedAccountToken] {
        accounts.mergeableAccounts.map(MergedAccountToken.init(account:))
    }

    func clearKeylessEntries() {
        let eligibleIDs = Set(accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }.map(\.id))
        orgByAccount = Self.retainingEntries(orgByAccount, for: eligibleIDs)
        statsByAccount = Self.retainingEntries(statsByAccount, for: eligibleIDs)
        accountErrors = Self.retainingEntries(accountErrors, for: eligibleIDs)
        statsFailures = Self.retainingFailures(statsFailures, for: eligibleIDs)
        quotaFailures = Self.retainingFailures(quotaFailures, for: eligibleIDs)
        quotaLoadingIDs.formIntersection(eligibleIDs)
        quotaReloadGenerations = Self.retainingEntries(quotaReloadGenerations, for: eligibleIDs)
    }

    func seedFromCache() {
        clearKeylessEntries()
        for account in accounts.mergeableAccounts
            where orgByAccount[account.id] == nil && !account.apiKey.isEmpty {
            orgByAccount[account.id] = orgCache.get(account.id, via: account.makeClient())
        }
    }

    func reload() async {
        let (generation, requestedStatsGeneration) = beginFullReload()
        clearKeylessEntries()
        let mergeable = accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }
        guard !mergeable.isEmpty else {
            isLoading = false
            return
        }

        isLoading = true
        defer {
            if Self.isCurrentReload(generation, current: reloadGeneration) {
                isLoading = false
            }
        }
        let requestedWindow = window
        let requestedToken = statsWindowToken
        let targets = mergeable.map { MergedOrganizationReloadTarget(id: $0.id, client: $0.makeClient()) }
        var requestedQuotaGenerations: [UUID: Int] = [:]
        for target in targets {
            quotaReloadGenerations[target.id, default: 0] &+= 1
            requestedQuotaGenerations[target.id] = quotaReloadGenerations[target.id]
        }
        // Duplicate account IDs must not trap Organization reload (#4615).
        let targetsByID = Dictionary(targets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        await loadResources(
            targets: targets, targetsByID: targetsByID,
            context: MergedOrganizationReloadContext(
                generation: generation, statsGeneration: requestedStatsGeneration,
                window: requestedWindow, token: requestedToken,
                quotaGenerations: requestedQuotaGenerations
            )
        )
    }

    func loadResources(
        targets: [MergedOrganizationReloadTarget],
        targetsByID: [UUID: MergedOrganizationReloadTarget],
        context: MergedOrganizationReloadContext
    ) async {
        for start in stride(from: 0, to: targets.count, by: 4) {
            let batch = targets[start ..< min(start + 4, targets.count)]
            do {
                try await withThrowingTaskGroup(of: MergedOrganizationReloadResult.self) { group in
                    for target in batch {
                        group.addTask { try await Self.fetchOrganization(target) }
                        group.addTask { try await Self.fetchStats(target, window: context.window) }
                        group.addTask { try await Self.fetchQuota(target) }
                    }
                    for try await result in group {
                        guard !Task.isCancelled,
                              Self.isCurrentReload(context.generation, current: reloadGeneration) else {
                            group.cancelAll()
                            throw CancellationError()
                        }
                        guard let target = targetsByID[result.id],
                              let client = currentClient(for: target) else {
                            discardStaleResult(for: result.id)
                            continue
                        }

                        applyReloadResult(
                            result, requestedToken: context.token,
                            requestedStatsGeneration: context.statsGeneration, client: client,
                            requestedQuotaGeneration: context.quotaGenerations[result.id]
                        )
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                assertionFailure("Merged organization resource fetch only throws cancellation: \(error)")
                return
            }
        }
    }

    func scheduleStatsReload() {
        statsTask?.cancel()
        let generation = beginStatsRequest()
        statsByAccount = [:]
        statsFailures = []
        statsTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }

            await reloadStats(generation: generation)
        }
    }

    func reloadStats(generation: Int) async {
        guard Self.isCurrentStatsRequest(generation, current: statsReloadGeneration) else { return }

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
                if let target = iterator.next() {
                    group.addTask { await fetch(target) }
                }
            }
            var collected: [MergedOrganizationStatsResult] = []
            for await result in group {
                collected.append(result)
                if let target = iterator.next() {
                    group.addTask { await fetch(target) }
                }
            }
            return collected
        }
        guard !Task.isCancelled,
              Self.isCurrentStatsRequest(generation, current: statsReloadGeneration),
              requestedToken == statsWindowToken else { return }

        let currentResults = results.filter { result in
            let current = accounts.mergeableAccounts.first(where: { $0.id == result.id })?.makeClient().taskIdentity
            return Self.isCurrentTarget(result.clientIdentity, current: current)
        }
        statsByAccount = Dictionary(currentResults.compactMap { result in
            result.stats.map { (result.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
        statsFailures = Set(currentResults.compactMap { $0.stats == nil ? $0.id : nil })
    }

    func beginStatsRequest() -> Int {
        statsReloadGeneration &+= 1
        return statsReloadGeneration
    }

    func beginFullReload() -> (reload: Int, stats: Int) {
        reloadGeneration &+= 1
        return (reloadGeneration, beginStatsRequest())
    }
}
