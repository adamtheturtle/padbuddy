//
//  OrganizationView.swift
//  coderpad
//

import SwiftUI

/// Selectable window for the organization pad-usage stats. `nil` dates mean the
/// API's own default (last 7 days); the presets compute an explicit range.
enum StatsPeriod: String, CaseIterable, Identifiable {
    case days7 = "Last 7 days"
    case days30 = "Last 30 days"
    case days90 = "Last 90 days"
    case months12 = "Last 12 months"
    case custom = "Custom range"

    var id: String { rawValue }

    private var days: Int? {
        switch self {
        case .days7: return 7
        case .days30: return 30
        case .days90: return 90
        case .months12: return 365
        case .custom: return nil
        }
    }

    /// The (start, end) window ending now for the selected preset, or `nil` for
    /// `.custom` where the dates come from the view's own pickers.
    func range(now: Date = Date()) -> (start: Date, end: Date)? {
        guard let days else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return (start, now)
    }
}

struct OrganizationView: View {
    let client: CoderPadClient
    @State private var accounts = AccountsStore.shared
    @State private var orgCache = OrganizationCacheStore.shared
    @State private var quotaCache = QuotaCacheStore.shared
    @State private var organization: Organization?
    @State private var stats: OrganizationStats?
    @State private var quota: Quota?
    @State private var isLoading = false
    @State private var error: Error?
    @State private var userSearch = ""
    @FocusState private var userSearchFocused: Bool
    @State private var period: StatsPeriod = .days7
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd = Date()

    /// Resolved (start, end) window for the active period, falling back to the
    /// custom pickers when no preset range applies.
    private var window: (start: Date, end: Date) {
        period.range() ?? (customStart, customEnd)
    }

    var body: some View {
        Group {
            if isLoading && organization == nil {
                ProgressView("Loading organization…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, organization == nil {
                APIErrorView(error: error) { Task { await reload() } }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        PaneTitle(title: "Organization") {
                            periodControls
                        }
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            statTiles
                            if organization != nil { activitySection(stats) }
                            if let organization { usersSection(organization) }
                        }
                        .padding(.horizontal, Spacing.paneH)
                        .padding(.top, 4)
                        .padding(.bottom, Spacing.paneV)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task(id: client.apiKey) {
            // Show the last-loaded org/quota immediately so re-entering the
            // section doesn't flash a spinner; reload refreshes them in place.
            // Stats are period-dependent, so they reload rather than restore.
            if let id = accounts.currentAccountID {
                if organization == nil { organization = orgCache.get(id) }
                if quota == nil { quota = quotaCache.get(id) }
            }
            await reload()
        }
        .onChange(of: period) { _, _ in
            Task { await reloadStats() }
        }
        .onChange(of: customStart) { _, _ in
            guard period == .custom else { return }
            Task { await reloadStats() }
        }
        .onChange(of: customEnd) { _, _ in
            guard period == .custom else { return }
            Task { await reloadStats() }
        }
        .focusedSceneValue(\.findAction, FindAction { userSearchFocused = true })
    }

    private var periodControls: some View {
        HStack(spacing: 8) {
            Picker("Period", selection: $period) {
                ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            if period == .custom {
                DatePicker("From", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
                DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
            }
            Button { Task { await reload() } } label: {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Reload")
            .accessibilityLabel("Reload")
            .disabled(isLoading)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AvatarCircle(label: organization?.organizationName ?? "?", diameter: 56, tint: .purple)
            VStack(alignment: .leading, spacing: 4) {
                Text(organization?.organizationName ?? "…")
                    .font(.title2.weight(.semibold))
                Text(organization.map { "ID #\($0.id)" } ?? " ")
                    .foregroundStyle(.secondary)
                    .font(.callout.monospaced())
            }
            Spacer()
        }
    }

    private var statTiles: some View {
        HStack(spacing: 12) {
            StatTile(title: "Users", value: organization.map { "\($0.userCount ?? $0.users.count)" } ?? "…",
                     systemImage: "person.3.fill", tint: .blue)
            StatTile(title: "Teams", value: organization.map { "\($0.teams.count)" } ?? "…",
                     systemImage: "rectangle.stack.person.crop", tint: .indigo)
            StatTile(title: "Pads (\(period.rawValue.lowercased()))", value: stats.map { "\($0.padsCreated)" } ?? "…",
                     systemImage: "doc.text.fill", tint: .teal)
            if let quota {
                if quota.unlimited == true {
                    StatTile(title: "Quota", value: "Unlimited", systemImage: "infinity", tint: .green)
                } else if let used = quota.padsUsed {
                    StatTile(title: "Pads used", value: "\(used)", systemImage: "chart.bar.fill", tint: .orange)
                }
            }
        }
    }

    private func activitySection(_ stats: OrganizationStats?) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Activity Window", systemImage: "calendar")
                // Show the rows from the first frame (even before stats load) so
                // the card doesn't pop in and shove the layout; values fill in.
                LabeledRow(label: "From", value: stats?.startTime
                    .map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "…")
                LabeledRow(label: "To", value: stats?.endTime
                    .map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "…")
                LabeledRow(label: "Pads created", value: stats.map { "\($0.padsCreated)" } ?? "…")
                if let q = quota {
                    if let reset = q.quotaReset {
                        LabeledRow(label: "Quota resets", value: reset.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let trial = q.trialExpiresAt {
                        LabeledRow(label: "Trial expires", value: trial.formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledRow(label: "Overages", value: q.overagesEnabled == true ? "Enabled" : "Disabled")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func usersSection(_ org: Organization) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Users", systemImage: "person.3")
                    Spacer()
                    Text("\(filteredUsers(org).count)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                TextField("Search users…", text: $userSearch)
                    .textFieldStyle(.roundedBorder)
                    .focused($userSearchFocused)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(filteredUsers(org)) { user in
                        Button {
                            AppNavigation.shared.showPads(PadsRequest(ownerEmail: user.email))
                        } label: {
                            HStack(spacing: 10) {
                                AvatarCircle(label: user.name ?? user.email, diameter: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.name ?? user.email)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Text(user.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(Color.subtleStroke.opacity(0.5),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Show pads owned by \(user.name ?? user.email)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func filteredUsers(_ org: Organization) -> [OrganizationUser] {
        let lowered = userSearch.lowercased()
        guard !lowered.isEmpty else { return org.users }
        return org.users.filter { ($0.name ?? "").lowercased().contains(lowered) || $0.email.lowercased().contains(lowered) }
    }

    private func reload() async {
        guard !client.apiKey.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        let window = window
        do {
            async let o = client.organization()
            async let s = client.organizationStats(start: window.start, end: window.end)
            async let q = client.quota()
            let fetchedOrg = try await o
            organization = fetchedOrg
            stats = try? await s
            let fetchedQuota = try? await q
            quota = fetchedQuota
            // Warm the shared caches so re-entering Organization — or visiting
            // the Quota section — shows data instantly instead of a spinner.
            if let id = accounts.currentAccountID {
                orgCache.set(id, organization: fetchedOrg)
                if let fetchedQuota { quotaCache.set(id, quota: fetchedQuota) }
            }
        } catch {
            self.error = error
        }
    }

    /// Refetches just the stats when the period changes, leaving the rest of the
    /// loaded organization data in place.
    private func reloadStats() async {
        guard !client.apiKey.isEmpty else { return }
        let window = window
        stats = try? await client.organizationStats(start: window.start, end: window.end)
    }
}
