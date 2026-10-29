//
//  OrganizationView+Filtering.swift
//  coderpad
//
//  Member filtering and the stats window token, split from OrganizationView.swift
//  to keep that file under the file-length limit.
//

import SwiftUI

@MainActor
enum OrganizationReloadFanout {
    static func run(
        organization: @MainActor () async -> Void,
        stats: @MainActor () async -> Void,
        quota: @MainActor () async -> Void
    ) async {
        async let organization: Void = organization()
        async let stats: Void = stats()
        async let quota: Void = quota()
        _ = await (organization, stats, quota)
    }
}

nonisolated struct OrganizationStatsOwner: Equatable {
    let accountID: UUID?
    let clientIdentity: ClientTaskIdentity
}

extension OrganizationView {
    var customRangeHeader: some View {
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
            .padding(.top, 12)
            Text("Dates use your current time zone (\(TimeZone.current.identifier)).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.paneH)
                .padding(.bottom, 12)
            Divider()
        }
    }

    var statTiles: some View {
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

    /// The organization's members, de-duplicated and sorted once — held in state and
    /// recomputed only when the organization loads.
    ///
    /// De-duplicated by email: the rows are keyed by it, so a repeated member in the
    /// response produced unstable rows and a count that didn't match what was listed
    /// (#2380). Case-insensitive, since the same address in two casings is one person.
    /// Sorted by display name so the list reads alphabetically rather than in the
    /// API's arbitrary order.
    ///
    /// The sort used to run inside `filteredUsers`, so an O(n log n) pass of
    /// locale-aware comparisons ran over the whole org on every keystroke (#2273).
    /// Neither the membership nor the ordering depends on the query, so neither
    /// belongs on that path.
    static func preparedUsers(_ org: Organization) -> [OrganizationUser] {
        var seen = Set<String>()
        return org.users
            .compactMap { user -> (user: OrganizationUser, name: String)? in
                // Identity must remain usable for routing; do not truncate an address
                // into another member's identity merely to fit the presentation budget.
                guard user.email.utf8.count <= 254,
                      !user.email.unicodeScalars.contains(where: {
                          $0.properties.generalCategory == .control || $0.properties.generalCategory == .format
                      }), seen.insert(user.email.lowercased()).inserted else { return nil }

                let name = ExternalText.singleLine(user.name ?? user.email, limit: 120)
                return (user, name)
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .map(\.user)
    }

    func prepareUsers(_ org: Organization) {
        let users = Self.preparedUsers(org)
        preparedUsers = users
        preparedUserSearchKeys = Dictionary(uniqueKeysWithValues: users.map { user in
            let presentation = OrganizationUserPresentation(user: user)
            return (user.email, Self.normalizedSearchKey(presentation.name + "\n" + presentation.email))
        })
    }

    static func normalizedSearchKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
    }

    /// The prepared list narrowed to the query. Only this cheap filter runs per
    /// keystroke; the order it preserves is the one established above.
    ///
    /// Trimmed and locale-aware: a stray space from a paste made every row miss, and
    /// `lowercased().contains` doesn't fold diacritics — so searching "rene" skipped
    /// "René" (#2379).
    func filteredUsers(_ users: [OrganizationUser]) -> [OrganizationUser] {
        let query = settledUserSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return users }

        let key = Self.normalizedSearchKey(query)
        return users.filter { preparedUserSearchKeys[$0.email]?.contains(key) == true }
    }

    var statsWindowToken: StatsWindowToken {
        StatsWindowToken(period: period,
                         customStart: period == .custom ? customStart : nil,
                         customEnd: period == .custom ? customEnd : nil)
    }

    func reload() async {
        guard !client.apiKey.isEmpty else { return }

        reloadGeneration &+= 1
        let generation = reloadGeneration
        statsLoadGeneration &+= 1
        let requestedStatsGeneration = statsLoadGeneration
        quotaLoadGeneration &+= 1
        let requestedQuotaGeneration = quotaLoadGeneration
        let requestedOwner = statsOwner
        isLoading = true
        error = nil
        defer {
            if matchesReload(generation, owner: requestedOwner) {
                isLoading = false
            }
        }
        let window = window
        let requested = statsWindowToken
        await OrganizationReloadFanout.run(
            organization: {
                await loadOrganization(generation: generation, owner: requestedOwner)
            },
            stats: {
                await loadStats(
                    window: window, requested: requested,
                    reloadGeneration: generation,
                    statsGeneration: requestedStatsGeneration,
                    owner: requestedOwner
                )
            },
            quota: {
                await loadQuota(
                    reloadGeneration: generation,
                    quotaGeneration: requestedQuotaGeneration,
                    owner: requestedOwner
                )
            }
        )
    }

    private func loadOrganization(generation: Int, owner: OrganizationStatsOwner) async {
        do {
            let fetched = try await client.organization()
            guard !Task.isCancelled, matchesReload(generation, owner: owner) else { return }

            organization = fetched
            warmCaches(organization: fetched, quota: nil)
        } catch {
            if !Task.isCancelled, matchesReload(generation, owner: owner) {
                self.error = error
            }
        }
    }

    private func loadStats(
        window: (start: Date, end: Date),
        requested: StatsWindowToken,
        reloadGeneration: Int,
        statsGeneration: Int,
        owner: OrganizationStatsOwner
    ) async {
        // Stats were fetched for `requested`; if the period picker moved on
        // while this full reload was in flight, a separately launched
        // `reloadStats()` owns the display now (#798). A stats-only failure
        // keeps the previous stats, marked stale, instead of silently
        // clearing them to a placeholder (#799).
        let fetched = try? await client.organizationStats(start: window.start, end: window.end)
        applyStats(
            fetched,
            requested: requested,
            reloadGeneration: reloadGeneration,
            statsGeneration: statsGeneration,
            owner: owner
        )
    }

    private func loadQuota(
        reloadGeneration: Int,
        quotaGeneration: Int,
        owner: OrganizationStatsOwner
    ) async {
        // A transient quota failure keeps whatever quota is already cached, but
        // marks it stale instead of silently presenting the partial reload as
        // complete (#1515, #2381).
        let fetched: Quota?
        do {
            fetched = try await client.quota()
        } catch {
            fetched = nil
        }
        guard !Task.isCancelled, matchesReload(reloadGeneration, owner: owner) else { return }

        if quotaGeneration == quotaLoadGeneration {
            if let fetched {
                quota = fetched
                quotaError = nil
            } else {
                quotaError = String(localized: "The quota request failed.")
            }
        }
        // Warm the shared caches so re-entering Organization — or visiting
        // the Quota section — shows data instantly instead of a spinner.
        // Strictly under the captured owning account, not the live current
        // one: an in-flight reload finishing after an account switch must not
        // write this account's data into the new account's cache (#991).
        warmCaches(organization: nil, quota: quotaGeneration == quotaLoadGeneration ? fetched : nil)
    }

    /// Retries only quota. The organization and stats endpoints have independent
    /// status and retry paths, so refetching them here tripled network work (#1524).
    func reloadQuota() async {
        guard !client.apiKey.isEmpty, !quotaLoading else { return }

        quotaLoadGeneration &+= 1
        let generation = quotaLoadGeneration
        let requestedOwner = statsOwner
        quotaLoading = true
        defer {
            if generation == quotaLoadGeneration, requestedOwner == statsOwner {
                quotaLoading = false
            }
        }
        do {
            let fetched = try await client.quota()
            guard !Task.isCancelled, generation == quotaLoadGeneration,
                  requestedOwner == statsOwner else { return }

            quota = fetched
            quotaError = nil
            if let accountID {
                quotaCache.set(accountID, quota: fetched, via: client)
            }
        } catch {
            guard !Task.isCancelled, generation == quotaLoadGeneration,
                  requestedOwner == statsOwner else { return }

            quotaError = String(localized: "The quota request failed.")
        }
    }

    private func matchesReload(_ generation: Int, owner: OrganizationStatsOwner) -> Bool {
        OrganizationReloadIdentity.isCurrent(
            generation,
            currentGeneration: reloadGeneration,
            requestedOwner: owner,
            currentOwner: statsOwner
        )
    }

    private func applyStats(
        _ fetched: OrganizationStats?,
        requested: StatsWindowToken,
        reloadGeneration: Int,
        statsGeneration: Int,
        owner: OrganizationStatsOwner
    ) {
        guard requested == statsWindowToken, !Task.isCancelled,
              matchesReload(reloadGeneration, owner: owner),
              OrganizationReloadIdentity.areStatsCurrent(
                  statsGeneration: statsGeneration,
                  currentStatsGeneration: statsLoadGeneration
              ) else { return }

        if let valid = OrganizationCountQuality.validatedStats(fetched) {
            stats = valid
            statsError = nil
        } else {
            statsError = fetched == nil ? String(localized: "The pad stats request failed.")
                : OrganizationCountQuality.invalidStatsMessage
        }
    }

    private func warmCaches(organization: Organization?, quota: Quota?) {
        guard let accountID else { return }

        if let organization {
            orgCache.set(accountID, organization: organization, via: client)
        }
        if let quota {
            quotaCache.set(accountID, quota: quota, via: client)
        }
    }

    /// Cancels any in-flight stats fetch before starting a new one, so rapid period
    /// or custom-date changes can't land an earlier, slower response on top of a newer
    /// one and show stats for the wrong window.
    func scheduleStatsReload() {
        statsTask?.cancel()
        statsTask = Task {
            // Settle first. Cancelling the previous task doesn't recall a request
            // that already left, so dragging a custom date picker — which emits a
            // value per step — fired one stats request per intermediate date (#2384).
            // A cancelled sleep returns before any request is made.
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }

            await reloadStats()
        }
    }

    /// Refetches just the stats when the period changes, leaving the rest of the
    /// loaded organization data in place. A failure keeps the previous stats,
    /// marked stale (#799).
    func reloadStats() async {
        guard !client.apiKey.isEmpty else { return }

        statsLoadGeneration &+= 1
        let generation = statsLoadGeneration
        let window = window
        let requested = statsWindowToken
        let requestedOwner = statsOwner
        let result = try? await client.organizationStats(start: window.start, end: window.end)
        // A newer request may have superseded this one while it was in flight.
        guard !Task.isCancelled, generation == statsLoadGeneration,
              requested == statsWindowToken, requestedOwner == statsOwner else { return }

        if let valid = OrganizationCountQuality.validatedStats(result) {
            stats = valid
            statsError = nil
        } else {
            statsError = result == nil ? String(localized: "The pad stats request failed.")
                : OrganizationCountQuality.invalidStatsMessage
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
                            ForEach(StatsPeriod.allCases) { Text($0.displayLabel).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("Period", systemImage: "calendar")
                    }
                }
            }
    }
}
