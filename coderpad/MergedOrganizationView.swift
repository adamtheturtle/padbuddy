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

import SwiftUI

struct MergedOrganizationView: View {
    @State private var accounts = AccountsStore.shared
    @State private var orgCache = OrganizationCacheStore.shared
    @State private var quotaCache = QuotaCacheStore.shared
    @State private var orgByAccount: [UUID: Organization] = [:]
    @State private var statsByAccount: [UUID: OrganizationStats] = [:]
    @State private var quotaByAccount: [UUID: Quota] = [:]
    @State private var accountErrors: [UUID: String] = [:]
    @State private var isLoading = false
    @AppStorage(StatsPeriod.storageKey) private var period: StatsPeriod = .days7
    /// In-flight stats refetch, cancelled before a new one so a slower earlier
    /// response can't land on top of a newer window (as in `OrganizationView`).
    @State private var statsTask: Task<Void, Never>?
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd = Date()

    /// Resolved (start, end) window for the active period, falling back to the
    /// custom pickers when no preset range applies.
    private var window: (start: Date, end: Date) {
        period.range() ?? (customStart, customEnd)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaneTitle(title: "Organization", subtitle: "Across all accounts")
                VStack(alignment: .leading, spacing: 18) {
                    if period == .custom { customRangeControls }
                    aggregateTiles
                    ForEach(accounts.mergeableAccounts) { account in
                        accountSection(account)
                    }
                }
                .padding(.horizontal, Spacing.paneH)
                .padding(.top, 4)
                .padding(.bottom, Spacing.paneV)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .macPullToRefresh { await reload() }
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
        .task {
            for await _ in AppRouter.reloads {
                await reload()
            }
        }
        .toolbar(id: "org.toolbar") {
            ToolbarItem(id: "period") {
                Picker("Period", selection: $period) {
                    ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .help("Stats period")
            }
            ToolbarItem(id: "reload") {
                ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
            }
        }
    }

    private var customRangeControls: some View {
        HStack(spacing: 8) {
            DatePicker("From", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                .datePickerStyle(.field)
            DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                .datePickerStyle(.field)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Aggregate

    private var loadedOrgs: [Organization] {
        accounts.mergeableAccounts.compactMap { orgByAccount[$0.id] }
    }

    private var totalUsers: Int {
        loadedOrgs.reduce(0) { $0 + ($1.userCount ?? $1.users.count) }
    }

    private var totalTeams: Int {
        loadedOrgs.reduce(0) { $0 + $1.teams.count }
    }

    private var totalPads: Int {
        accounts.mergeableAccounts.compactMap { statsByAccount[$0.id]?.padsCreated }.reduce(0, +)
    }

    private var aggregateTiles: some View {
        HStack(spacing: 12) {
            StatTile(title: "Organizations", value: "\(loadedOrgs.count)",
                     systemImage: "building.2.fill", tint: .purple)
            StatTile(title: "Users", value: "\(totalUsers)",
                     systemImage: "person.3.fill", tint: .blue)
            StatTile(title: "Teams", value: "\(totalTeams)",
                     systemImage: "rectangle.stack.person.crop", tint: .indigo)
            StatTile(title: "Pads (\(period.rawValue.lowercased()))", value: "\(totalPads)",
                     systemImage: "doc.text.fill", tint: .teal)
        }
    }

    // MARK: - Per-account

    private func accountSection(_ account: Account) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                AccountSectionHeader(account: account)
                if let org = orgByAccount[account.id] {
                    orgBreakdown(org, account: account)
                } else if let error = accountErrors[account.id] {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.secondary)
                } else if account.apiKey.isEmpty {
                    Text("No API key for this account.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func orgBreakdown(_ org: Organization, account: Account) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledRow(label: "Organization", value: org.organizationName)
            LabeledRow(label: "Users", value: "\(org.userCount ?? org.users.count)")
            LabeledRow(label: "Teams", value: "\(org.teams.count)")
            if let stats = statsByAccount[account.id] {
                LabeledRow(label: "Pads (\(period.rawValue.lowercased()))", value: "\(stats.padsCreated)")
            }
            if let quota = quotaByAccount[account.id] {
                LabeledRow(label: "Quota", value: quotaSummary(quota))
            }
            if let sso = org.singleSignOnSupported {
                LabeledRow(label: "Single sign-on", value: sso ? "Enabled" : "Disabled")
            }
        }
    }

    private func quotaSummary(_ quota: Quota) -> String {
        if quota.unlimited == true { return "Unlimited" }
        if let used = quota.padsUsed, let limit = quota.billingCyclePadLimit {
            return "\(used) / \(limit) pads used"
        }
        if let used = quota.padsUsed { return "\(used) pads used" }
        return "—"
    }

    // MARK: - Loading

    /// A token covering the merged account set (ids + key emptiness) so the load
    /// task restarts when an account is added, removed, or rekeyed — matching
    /// `MergedPadsView.accountKey`.
    private var accountKey: String {
        accounts.mergeableAccounts.map { "\($0.id.uuidString):\($0.apiKey.isEmpty ? 0 : 1)" }
            .joined(separator: ",")
    }

    private func seedFromCache() {
        for account in accounts.mergeableAccounts {
            if orgByAccount[account.id] == nil { orgByAccount[account.id] = orgCache.get(account.id) }
            if quotaByAccount[account.id] == nil { quotaByAccount[account.id] = quotaCache.get(account.id) }
        }
    }

    /// Fan out a fresh org/stats/quota fetch across every account concurrently,
    /// applying each account's result as it lands and isolating its failure.
    private func reload() async {
        let mergeable = accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }
        guard !mergeable.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        let window = window
        let targets = mergeable.map { (id: $0.id, client: $0.makeClient()) }
        await withTaskGroup(of: (UUID, Organization?, OrganizationStats?, Quota?, String?).self) { group in
            for target in targets {
                group.addTask {
                    do {
                        async let orgFetch = target.client.organization()
                        async let statsFetch = target.client.organizationStats(start: window.start, end: window.end)
                        async let quotaFetch = target.client.quota()
                        let org = try await orgFetch
                        return (target.id, org, try? await statsFetch, try? await quotaFetch, nil)
                    } catch {
                        return (target.id, nil, nil, nil, error.localizedDescription)
                    }
                }
            }
            for await (id, org, stats, quota, errorText) in group {
                if let org {
                    orgByAccount[id] = org
                    orgCache.set(id, organization: org)
                    accountErrors[id] = nil
                } else if let errorText {
                    accountErrors[id] = errorText
                }
                if let stats { statsByAccount[id] = stats }
                if let quota {
                    quotaByAccount[id] = quota
                    quotaCache.set(id, quota: quota)
                }
            }
        }
    }

    private func scheduleStatsReload() {
        statsTask?.cancel()
        statsTask = Task { await reloadStats() }
    }

    /// Refetch just the stats for the new window across every account, leaving the
    /// loaded orgs and quotas in place.
    private func reloadStats() async {
        let mergeable = accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }
        guard !mergeable.isEmpty else { return }
        let window = window
        let targets = mergeable.map { (id: $0.id, client: $0.makeClient()) }
        await withTaskGroup(of: (UUID, OrganizationStats?).self) { group in
            for target in targets {
                group.addTask {
                    (target.id, try? await target.client.organizationStats(start: window.start, end: window.end))
                }
            }
            for await (id, stats) in group {
                guard !Task.isCancelled else { return }
                if let stats { statsByAccount[id] = stats }
            }
        }
    }
}
