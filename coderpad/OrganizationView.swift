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

    /// `@AppStorage` key shared by the Organization view and the View menu's
    /// "Stats Period" command, so the toolbar picker and the menu stay in sync.
    static let storageKey = "organization.statsPeriod"

    var id: String {
        rawValue
    }

    private var days: Int? {
        switch self {
        case .days7: 7
        case .days30: 30
        case .days90: 90
        case .months12: 365
        case .custom: nil
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
    @AppStorage(StatsPeriod.storageKey) private var period: StatsPeriod = .days7
    @State private var statsTask: Task<Void, Never>?
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd = Date()

    /// Resolved (start, end) window for the active period, falling back to the
    /// custom pickers when no preset range applies.
    private var window: (start: Date, end: Date) {
        period.range() ?? (customStart, customEnd)
    }

    var body: some View {
        Group {
            if isLoading, organization == nil {
                ProgressView("Loading organization…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, organization == nil {
                APIErrorView(error: error) { Task { await reload() } }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        PaneTitle(title: "Organization")
                        VStack(alignment: .leading, spacing: 18) {
                            if period == .custom { customRangeControls }
                            header
                            statTiles
                            if organization != nil { activitySection(stats) }
                            if let supported = organization?.singleSignOnSupported {
                                singleSignOnSection(supported)
                            }
                            if let organization { usersSection(organization) }
                        }
                        .padding(.horizontal, Spacing.paneH)
                        .padding(.top, 4)
                        .padding(.bottom, Spacing.paneV)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .macPullToRefresh { await reload() }
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
            scheduleStatsReload()
        }
        .onChange(of: customStart) { _, _ in
            guard period == .custom else { return }
            scheduleStatsReload()
        }
        .onChange(of: customEnd) { _, _ in
            guard period == .custom else { return }
            scheduleStatsReload()
        }
        .focusedSceneValue(\.findAction, FindAction(id: "organization") { userSearchFocused = true })
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

    /// The custom From/To range, shown inline below the title only when the
    /// "Custom range" period is selected. These stay in the pane rather than the
    /// toolbar because their width varies and they only apply to one period.
    private var customRangeControls: some View {
        HStack(spacing: 8) {
            DatePicker("From", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                .datePickerStyle(.field)
            DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                .datePickerStyle(.field)
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AvatarCircle(label: organization?.organizationName ?? "?", diameter: 56, tint: .purple)
            VStack(alignment: .leading, spacing: 4) {
                Text(organization?.organizationName ?? "…")
                    .font(.title2.weight(.semibold))
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func singleSignOnSection(_ supported: Bool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Single sign-on", systemImage: "key.horizontal")
                LabeledRow(label: "Single sign-on", value: supported ? "Enabled" : "Disabled")
                if supported, let urlString = organization?.singleSignInURL,
                   let url = URL(string: urlString) {
                    // Always the system browser, never the in-app web view: SSO
                    // sign-in relies on the user's real browser session and
                    // password manager.
                    Button { BrowserSettings.openExternally(url) } label: {
                        Label("Open sign-in portal", systemImage: "arrow.up.forward.app")
                            .font(.callout)
                    }
                    .buttonStyle(.link)
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
        return org.users.filter {
            ($0.name ?? "").lowercased().contains(lowered) || $0.email.lowercased().contains(lowered)
        }
    }

    private func reload() async {
        guard !client.apiKey.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        let window = window
        do {
            async let orgFetch = client.organization()
            async let statsFetch = client.organizationStats(start: window.start, end: window.end)
            async let quotaFetch = client.quota()
            let fetchedOrg = try await orgFetch
            organization = fetchedOrg
            stats = try? await statsFetch
            let fetchedQuota = try? await quotaFetch
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

    /// Cancels any in-flight stats fetch before starting a new one, so rapid period
    /// or custom-date changes can't land an earlier, slower response on top of a newer
    /// one and show stats for the wrong window.
    private func scheduleStatsReload() {
        statsTask?.cancel()
        statsTask = Task { await reloadStats() }
    }

    /// Refetches just the stats when the period changes, leaving the rest of the
    /// loaded organization data in place.
    private func reloadStats() async {
        guard !client.apiKey.isEmpty else { return }
        let window = window
        let result = try? await client.organizationStats(start: window.start, end: window.end)
        // A newer request may have superseded this one while it was in flight.
        guard !Task.isCancelled else { return }
        stats = result
    }
}
