//
//  OrganizationView+Filtering.swift
//  coderpad
//
//  Member filtering and the stats window token, split from OrganizationView.swift
//  to keep that file under the file-length limit.
//

import SwiftUI

extension OrganizationView {
    func filteredUsers(_ org: Organization) -> [OrganizationUser] {
        // De-duplicated by email: the rows are keyed by it, so a repeated member in
        // the response produced unstable rows and a count that didn't match what was
        // listed (#2380). Case-insensitive, since the same address in two casings is
        // one person.
        var seen = Set<String>()
        let unique = org.users.filter { seen.insert($0.email.lowercased()).inserted }

        // Trimmed and locale-aware: a stray space from a paste made every row miss,
        // and `lowercased().contains` doesn't fold diacritics — so searching "rene"
        // skipped "René" (#2379).
        let query = userSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = query.isEmpty ? unique : unique.filter {
            ($0.name ?? "").localizedStandardContains(query) || $0.email.localizedStandardContains(query)
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
        async let orgFetch = client.organization()
        async let statsFetch = client.organizationStats(start: window.start, end: window.end)
        async let quotaFetch = client.quota()
        // The organization fetch is awaited with `try?` and its failure recorded,
        // rather than thrown — throwing here skipped the stats and quota results
        // entirely, so one endpoint being down discarded the other two's usable data
        // (#2383). Each result is applied on its own below.
        let fetchedOrg: Organization?
        do {
            fetchedOrg = try await orgFetch
        } catch {
            fetchedOrg = nil
            self.error = error
        }
        if let fetchedOrg {
            organization = fetchedOrg
        }
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
        // A transient quota failure keeps whatever quota is already on screen,
        // rather than blanking a usable card — the same treatment stats already
        // get above (#799, #2381). The card that remains was fetched for this
        // same account, so it is stale rather than wrong.
        if let fetchedQuota = try? await quotaFetch {
            quota = fetchedQuota
        }
        // Warm the shared caches so re-entering Organization — or visiting
        // the Quota section — shows data instantly instead of a spinner.
        // Strictly under the captured owning account, not the live current
        // one: an in-flight reload finishing after an account switch must not
        // write this account's data into the new account's cache (#991).
        if let id = accountID {
            if let fetchedOrg { orgCache.set(id, organization: fetchedOrg, via: client) }
            if let quota { quotaCache.set(id, quota: quota, via: client) }
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
