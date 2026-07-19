//
//  MergedPadsView+Bars.swift
//  coderpad
//
//  The preset, filter, count, and error bars for the combined pads list.
//

import SwiftUI

extension MergedPadsView {
    /// A name lookup for the Account chip's formatter, resolving each option in O(1)
    /// rather than scanning `accounts` per option (#368). The index itself is memoized
    /// across renders — see `MergedAccountOptionsCache` (#2467, #2468).
    func accountNameFormatter() -> (UUID) -> String {
        accountOptionsCache.formatter()
    }

    var filterBar: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            FilterChipMenu(
                title: String(localized: "Account"), icon: "person.crop.circle",
                selected: $accountFilter,
                options: accountOptionsCache.ids,
                formatter: accountNameFormatter()
            )
            .measuresFilterBarWidth()
            FilterChipMenu(
                title: String(localized: "State"), icon: "circle.fill",
                selected: $stateFilter, options: availableStates,
                formatter: { $0.label }
            )
            .measuresFilterBarWidth()
            FilterChipMenu(
                title: String(localized: "Language"), icon: "chevron.left.slash.chevron.right",
                selected: $languageFilter, options: availableLanguages,
                formatter: { $0.coderPadLanguageDisplayName }
            )
            .measuresFilterBarWidth()
            SearchableFilterChip(
                title: String(localized: "Owner"), icon: "person",
                selected: $ownerFilter, options: availableOwners,
                formatter: { directory.display($0) },
                meEmail: nil
            )
            .measuresFilterBarWidth()
            FilterChipMenu(
                title: String(localized: "Type"), icon: "tag",
                selected: $typeFilter,
                options: InterviewType.allCases.map(\.rawValue),
                formatter: { InterviewType(rawValue: $0)?.label ?? $0.capitalized }
            )
            .measuresFilterBarWidth()
            DateRangeFilterChip(title: String(localized: "Updated"), window: $updatedWindow,
                                options: PadDateRange.options)
                .measuresFilterBarWidth()
            DateRangeFilterChip(title: String(localized: "Created"), window: $createdWindow,
                                options: PadDateRange.options)
                .measuresFilterBarWidth()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The result-count summary shown as the window's toolbar subtitle beneath the
    /// "Pads" title. Names the account span the merged list covers; empty while the
    /// list is empty so the subtitle falls back to the static "All accounts" cue.
    var countSubtitle: String {
        guard !scoped.isEmpty else { return "" }

        let shown = filtered.count
        let accountCount = accounts.mergeableAccounts.count
        let base = (activeFilterCount > 0 || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ? String(localized: "\(shown) of \(scoped.count) pads across \(accountCount) accounts")
            : (shown == 1
                ? String(localized: "\(shown) pad across \(accountCount) accounts")
                : String(localized: "\(shown) pads across \(accountCount) accounts"))
        return base + freshnessSuffix
    }

    /// A trailing " · Refreshing…" / " · Updated just now" / " · Updated X ago" cue
    /// appended to the count, so the cached-then-refreshed list shows its freshness
    /// without adding chrome (#619).
    private var freshnessSuffix: String {
        if isLoading {
            return " · " + String(localized: "Refreshing…")
        }
        guard let lastRefreshed else { return "" }

        return " · " + mergedListFreshnessText(for: lastRefreshed)
    }

    /// A quiet note naming any accounts whose fetch failed, so the merged list
    /// doesn't silently look complete when one account couldn't be reached. A rejected
    /// API key reads differently from a transient network blip (red key glyph plus a
    /// jump to the account editor, vs. an orange "couldn't refresh"), so the two aren't
    /// confused (#622).
    /// The accounts whose last load failed, split by whether the failure was a
    /// rejected key or a transient network problem — the two read very differently in
    /// the bar. Empty when nothing failed, which is the usual answer.
    private func partitionedFailures() -> (auth: [Account], network: [Account]) {
        guard !accountErrors.isEmpty else { return ([], []) }

        var auth: [Account] = []
        var network: [Account] = []
        for account in accounts.mergeableAccounts where accountErrors[account.id] != nil {
            if healthMonitor.isUnauthorized(account.id) {
                auth.append(account)
            } else {
                network.append(account)
            }
        }
        return (auth, network)
    }

    @ViewBuilder
    var errorBar: some View {
        // The common case is no errors at all, and this runs on every render — so
        // check the (usually empty) error map before touching the account list, and
        // split the failures in one pass rather than three filters over it (#2469).
        let (authFailed, networkFailed) = partitionedFailures()
        if !authFailed.isEmpty || !networkFailed.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !authFailed.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "key.slash.fill")
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                        Text("The API key for \(authFailed.map(\.name).joined(separator: ", ")) was rejected.")
                            .foregroundStyle(.secondary)
                        Button("Fix in Settings") { openAccountSettings(authFailed[0]) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                }
                if !networkFailed.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            // Decorative: the adjacent message already states the failure, so
                            // VoiceOver shouldn't announce the bare symbol name before it.
                            .accessibilityHidden(true)
                        Text("Couldn't refresh \(networkFailed.map(\.name).joined(separator: ", ")). "
                            + "Showing the last loaded pads.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    /// Opens Settings on the Accounts tab with this account selected for editing, so a
    /// rejected key can be fixed where the error points (#622). Mirrors the same helper
    /// in `MergedOrganizationView`.
    private func openAccountSettings(_ account: Account) {
        let navigation = SettingsNavigation.shared
        navigation.selectedTab = .accounts
        navigation.accountToEdit = account.id
        openSettings()
    }
}

func mergedListFreshnessText(for refreshedAt: Date, now: Date = .now) -> String {
    let elapsed = now.timeIntervalSince(refreshedAt)
    guard elapsed >= 60 else {
        return String(localized: "Updated just now")
    }

    return String(localized: "Updated \(RelativeDateLabel.labels(for: refreshedAt).relative)")
}
