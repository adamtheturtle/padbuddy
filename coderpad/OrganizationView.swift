//
//  OrganizationView.swift
//  coderpad
//

import MacPullToRefresh
import SwiftUI

struct OrganizationView: View {
    let client: CoderPadClient
    /// The account this view shows, captured at construction (the caller keys the
    /// view `.id(account.id)` per account, so the current account at init time is
    /// the owning one). Org and quota responses are cached strictly under this id,
    /// never under whatever account is current when a slow reload lands after an
    /// account switch (#991) - mirroring `QuotaView.accountID` (#797).
    private let accountID: UUID?
    @State private var orgCache = OrganizationCacheStore.shared
    @State private var quotaCache = QuotaCacheStore.shared
    @State private var organization: Organization?
    @State private var stats: OrganizationStats?
    /// A stats-only refresh failure (#799): the previous stats stay on screen,
    /// explicitly marked stale, instead of vanishing into a silent placeholder.
    @State private var statsError: String?
    @State private var quota: Quota?
    @State private var isLoading = false
    @State private var error: (any Error)?
    @State private var userSearch = ""
    @FocusState private var userSearchFocused: Bool
    @AppStorage(StatsPeriod.storageKey) private var period: StatsPeriod = .days7
    @State private var statsTask: Task<Void, Never>?
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd = Date()

    init(client: CoderPadClient) {
        self.client = client
        let accountID = AccountsStore.shared.currentAccountID
        self.accountID = accountID
        _organization = State(initialValue: accountID.flatMap { OrganizationCacheStore.shared.get($0) })
        _quota = State(initialValue: accountID.flatMap { QuotaCacheStore.shared.get($0) })
    }

    /// Resolved (start, end) window for the active period, falling back to the
    /// custom pickers when no preset range applies.
    private var window: (start: Date, end: Date) {
        period.range() ?? (customStart, customEnd)
    }

    var body: some View {
        content
            .task(id: client.taskIdentity) {
                // Show the last-loaded org/quota immediately so re-entering the
                // section doesn't flash a spinner; reload refreshes them in place.
                // Stats are period-dependent, so they reload rather than restore.
                if let id = accountID {
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
            .onReloadRequest { await reload() }
            .toolbar(id: "organization") { organizationToolbar }
    }

    @ViewBuilder
    private var content: some View {
        if let error, organization == nil {
            APIErrorView(error: error) { Task { await reload() } }
        } else {
            loadedContent
        }
    }

    private var loadedContent: some View {
        // No blocking spinner on first load (#362): show the layout straight
        // away with the stat tiles' own "…" placeholders, and let the
        // toolbar's reload button carry the loading state instead.
        VStack(spacing: 0) {
            if period == .custom { customRangeHeader }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // A failed refresh over previously loaded org data must not
                    // pose as current (#990): keep the cached content but mark it
                    // stale with a retry, mirroring QuotaView's banner (#800).
                    if let error {
                        StaleRefreshBanner(message: error.localizedDescription) {
                            Task { await reload() }
                        }
                    }
                    statTiles
                    if let supported = organization?.singleSignOnSupported {
                        singleSignOnSection(supported)
                    }
                    if let organization { usersSection(organization) }
                }
                .padding(.horizontal, Spacing.paneH)
                .padding(.top, Spacing.paneV)
                .padding(.bottom, Spacing.paneV)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .macPullToRefresh { await reload() }
        }
    }

    @ToolbarContentBuilder
    private var organizationToolbar: some CustomizableToolbarContent {
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

    /// The custom From/To range, pinned above the ScrollView (only when the
    /// "Custom range" period is selected) so it stays visible while scrolling the
    /// user grid. It stays out of the toolbar because the date fields' width varies
    /// and they only apply to one period.
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

    private var statTiles: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                StatTile(title: "Teams", value: organization.map { "\($0.teams.count)" } ?? "…",
                         systemImage: "rectangle.stack.person.crop", tint: .indigo)
                StatTile(title: "Pads", value: stats.map { "\($0.padsCreated)" } ?? "…",
                         systemImage: "doc.text.fill", tint: .teal)
            }
            if let statsError {
                StaleRefreshBanner(message: statsError) { scheduleStatsReload() }
            }
        }
    }

    private func singleSignOnSection(_ supported: Bool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Single sign-on", systemImage: "key.horizontal")
                LabeledRow(label: "Single sign-on",
                           value: supported ? String(localized: "Enabled") : String(localized: "Disabled"))
                if supported, let urlString = organization?.singleSignInURL,
                   let url = URL(string: urlString) {
                    // Always the system browser, never the in-app web view: SSO
                    // sign-in relies on the user's real browser session and
                    // password manager.
                    Button { BrowserSettings.openExternally(url) } label: {
                        Label("Open sign-in portal", systemImage: "arrow.up.forward.app")
                            .font(.callout)
                    }
                    #if os(macOS)
                    .linkButtonStyle()
                    #endif
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func usersSection(_ org: Organization) -> some View {
        // Filter + sort the whole org once per render and reuse it for both the
        // count and the grid, rather than running it twice on every keystroke (#369).
        let users = filteredUsers(org)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Users", systemImage: "person.3")
                    Spacer()
                    Text("\(users.count)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                TextField("Search users…", text: $userSearch)
                    .textFieldStyle(.roundedBorder)
                    .focused($userSearchFocused)
                usersList(users)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func usersList(_ users: [OrganizationUser]) -> some View {
        #if os(macOS)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Name")
                        .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                    Text("Email")
                        .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

                Divider()

                LazyVStack(spacing: 0) {
                    ForEach(users) { user in
                        CompactUserRow(user: user)
                        Divider()
                    }
                }
            }
            .background(Color.subtleStroke.opacity(0.22),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.subtleStroke, lineWidth: 1)
            )
        #else
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(users) { user in
                    TouchUserCard(user: user)
                }
            }
        #endif
    }
}

private extension OrganizationView {
    func filteredUsers(_ org: Organization) -> [OrganizationUser] {
        let lowered = userSearch.lowercased()
        let matched = lowered.isEmpty ? org.users : org.users.filter {
            ($0.name ?? "").lowercased().contains(lowered) || $0.email.lowercased().contains(lowered)
        }
        // Sort by display name so the list reads alphabetically rather than in
        // the API's arbitrary order.
        return matched.sorted {
            ($0.name ?? $0.email).localizedCaseInsensitiveCompare($1.name ?? $1.email) == .orderedAscending
        }
    }

    var statsWindowToken: StatsWindowToken {
        StatsWindowToken(period: period,
                         customStart: period == .custom ? customStart : nil,
                         customEnd: period == .custom ? customEnd : nil)
    }

    func reload() async {
        guard !client.apiKey.isEmpty else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }
        let window = window
        let requested = statsWindowToken
        do {
            async let orgFetch = client.organization()
            async let statsFetch = client.organizationStats(start: window.start, end: window.end)
            async let quotaFetch = client.quota()
            let fetchedOrg = try await orgFetch
            organization = fetchedOrg
            // Stats were fetched for `requested`; if the period picker moved on
            // while this full reload was in flight, a separately launched
            // `reloadStats()` owns the display now (#798). A stats-only failure
            // keeps the previous stats, marked stale, instead of silently
            // clearing them to a placeholder (#799).
            let fetchedStats = try? await statsFetch
            if requested == statsWindowToken {
                if let fetchedStats {
                    stats = fetchedStats
                    statsError = nil
                } else {
                    statsError = String(localized: "The pad stats request failed.")
                }
            }
            let fetchedQuota = try? await quotaFetch
            quota = fetchedQuota
            // Warm the shared caches so re-entering Organization — or visiting
            // the Quota section — shows data instantly instead of a spinner.
            // Strictly under the captured owning account, not the live current
            // one: an in-flight reload finishing after an account switch must not
            // write this account's data into the new account's cache (#991).
            if let id = accountID {
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
    func scheduleStatsReload() {
        statsTask?.cancel()
        statsTask = Task { await reloadStats() }
    }

    /// Refetches just the stats when the period changes, leaving the rest of the
    /// loaded organization data in place. A failure keeps the previous stats,
    /// marked stale (#799).
    func reloadStats() async {
        guard !client.apiKey.isEmpty else { return }

        let window = window
        let requested = statsWindowToken
        let result = try? await client.organizationStats(start: window.start, end: window.end)
        // A newer request may have superseded this one while it was in flight.
        guard !Task.isCancelled, requested == statsWindowToken else { return }

        if let result {
            stats = result
            statsError = nil
        } else {
            statsError = String(localized: "The pad stats request failed.")
        }
    }
}

#Preview("Period picker") {
    @Previewable @State var period: StatsPeriod = .days7
    NavigationStack {
        Color.clear
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Picker("Period", selection: $period) {
                            ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("Period", systemImage: "calendar")
                    }
                }
            }
    }
}
