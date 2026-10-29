//
//  OrganizationView.swift
//  coderpad
//

import MacPullToRefresh
import SwiftUI

struct OrganizationView: View {
    /// Several members below are internal rather than private because the member
    /// filtering and stats-window token live in OrganizationView+Filtering.swift,
    /// split out to keep both files under the file-length limit.
    let client: CoderPadClient
    /// The account this view shows, captured at construction (the caller keys the
    /// view `.id(account.id)` per account, so the current account at init time is
    /// the owning one). Org and quota responses are cached strictly under this id,
    /// never under whatever account is current when a slow reload lands after an
    /// account switch (#991) - mirroring `QuotaView.accountID` (#797).
    let accountID: UUID?
    @State var orgCache = OrganizationCacheStore.shared
    @State var quotaCache = QuotaCacheStore.shared
    @State var organization: Organization?
    @State var stats: OrganizationStats?
    /// A stats-only refresh failure (#799): the previous stats stay on screen,
    /// explicitly marked stale, instead of vanishing into a silent placeholder.
    @State var statsError: String?
    @State var quota: Quota?
    /// Quota refreshes are independent of organization and stats requests. Keep
    /// cached quota usable after a failure, but never let it appear freshly loaded.
    @State var quotaError: String?
    @State var quotaLoading = false
    @State var quotaLoadGeneration = 0
    @State var isLoading = false
    @State var reloadGeneration = 0
    @State var statsLoadGeneration = 0
    @State var error: (any Error)?
    @State var userSearch = ""
    /// The de-duplicated, sorted member list, rebuilt only when the organization
    /// changes — not on every keystroke (#2273). See `preparedUsers`.
    @State var preparedUsers: [OrganizationUser] = []
    @State var preparedUserSearchKeys: [String: String] = [:]
    @State var settledUserSearch = ""
    @FocusState private var userSearchFocused: Bool
    @State private var findActionPublisherID = UUID()
    @State var period: StatsPeriod = .days7
    @State var statsTask: Task<Void, Never>?
    @State var statsOwner: OrganizationStatsOwner
    @State var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State var customEnd = Date()

    private var customRangeScope: String {
        "account.\(accountID?.uuidString ?? "unknown")"
    }

    init(client: CoderPadClient, accountID: UUID) {
        self.client = client
        self.accountID = accountID
        let customRange = StatsPeriod.persistedCustomRange(scope: "account.\(accountID.uuidString)")
        _customStart = State(initialValue: customRange.start)
        _customEnd = State(initialValue: customRange.end)
        _statsOwner = State(initialValue: OrganizationStatsOwner(accountID: accountID,
                                                                 clientIdentity: client.taskIdentity))
        _organization = State(initialValue: OrganizationCacheStore.shared.get(accountID, via: client))
        _quota = State(initialValue: QuotaCacheStore.shared.get(accountID))
    }

    var body: some View {
        content
            .task(id: client.taskIdentity) {
                statsTask?.cancel()
                statsOwner = OrganizationStatsOwner(accountID: accountID, clientIdentity: client.taskIdentity)
                // Show the last-loaded org/quota immediately so re-entering the
                // section doesn't flash a spinner; reload refreshes them in place.
                // Stats are period-dependent, so they reload rather than restore.
                if let id = accountID {
                    if organization == nil {
                        organization = orgCache.get(id, via: client)
                    }
                    if quota == nil {
                        quota = quotaCache.get(id)
                    }
                }
                if let organization {
                    prepareUsers(organization)
                }
                await reload()
            }
            .onChange(of: organization) { _, org in
                if let org {
                    prepareUsers(org)
                } else {
                    preparedUsers = []
                    preparedUserSearchKeys = [:]
                }
            }
            .task(id: userSearch) {
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
                settledUserSearch = userSearch
            }
            .onChange(of: period) { _, _ in
                scheduleStatsReload()
            }
            .onChange(of: customStart) { _, _ in
                guard period == .custom else { return }

                StatsPeriod.persistCustomRange(start: customStart, end: customEnd, scope: customRangeScope)
                scheduleStatsReload()
            }
            .onChange(of: customEnd) { _, _ in
                guard period == .custom else { return }

                StatsPeriod.persistCustomRange(start: customStart, end: customEnd, scope: customRangeScope)
                scheduleStatsReload()
            }
            .focusedSceneValue(\.findAction, FindAction(id: "organization", publisherID: findActionPublisherID) {
                userSearchFocused = true
            })
            .focusedSceneValue(\.statsPeriodSelection, $period)
            .onReloadRequest { await reload() }
            // The stats fetch is held in state rather than run from `.task`, so
            // SwiftUI doesn't cancel it when the view goes away — it would keep
            // running and then write into state nobody is showing (#2385).
            .onDisappear {
                statsTask?.cancel()
                statsTask = nil
            }
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
            if period == .custom {
                customRangeHeader
            }
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
                    if let quotaError {
                        StaleRefreshBanner(message: quotaError) { Task { await reloadQuota() } }
                    }
                    statTiles
                    if let supported = organization?.singleSignOnSupported {
                        singleSignOnSection(supported)
                    }
                    if let organization {
                        usersSection(organization)
                    }
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
    /// with a calendar glyph so users don't have to open the generic overflow
    /// with a calendar glyph so users do not have to open the generic overflow
    /// before choosing a date window.
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

    /// The sign-in portal URL, or nil when the response's value isn't an https web
    /// address this app should hand to the system browser (#2378).
    static func portalURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host(), !host.isEmpty else { return nil }

        return url
    }

    private func singleSignOnSection(_ supported: Bool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Single sign-on", systemImage: "key.horizontal")
                LabeledRow(label: "Single sign-on",
                           value: supported ? String(localized: "Enabled") : String(localized: "Disabled"))
                // `URL(string:)` alone accepts file://, custom schemes, and anything
                // else the organization response happens to contain — and this hands
                // the result to the system browser. Only an https web address is
                // opened (#2378).
                if supported, let urlString = organization?.singleSignInURL,
                   let url = Self.portalURL(urlString) {
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

    private func usersSection(_: Organization) -> some View {
        // Narrowed once per render and reused for both the count and the grid, rather
        // than running twice on every keystroke (#369). The expensive de-duplication
        // and sort happened here too until #2273; they now run only when the
        // organization itself changes.
        let users = filteredUsers(preparedUsers)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Users", systemImage: "person.3")
                    Spacer()
                    // While a refresh is in flight the count describes the members
                    // loaded so far, which can be a cached or partial set — showing
                    // it bare read as an authoritative total (#2387).
                    if isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel("Updating members")
                    }
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
        if users.isEmpty, !settledUserSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView {
                Label("No Matching Users", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("No organization members match this search.")
            } actions: {
                Button("Clear Search") {
                    userSearch = ""
                    settledUserSearch = ""
                    userSearchFocused = true
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else {
            organizationUsersGrid(users)
        }
    }
}

@ViewBuilder
private func organizationUsersGrid(_ users: [OrganizationUser]) -> some View {
    #if os(macOS)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Name").frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                Text("Email").frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
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

extension OrganizationView {
    /// Resolved (start, end) window for the active period, falling back to the
    /// custom pickers when no preset range applies.
    var window: (start: Date, end: Date) {
        period.range() ?? StatsPeriod.boundedCustomRange(start: customStart, end: customEnd)
    }
}
