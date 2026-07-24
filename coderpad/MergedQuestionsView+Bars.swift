//
//  MergedQuestionsView+Bars.swift
//  coderpad
//
//  The preset, filter, count, and error bars for the combined questions list.
//

import SwiftUI

extension MergedQuestionsView {
    /// A name lookup for the Account chip's formatter, resolving each option in O(1)
    /// rather than scanning `accounts` per option (#368). The index itself is memoized
    /// across renders — see `MergedAccountOptionsCache` (#2467, #2468).
    func accountNameFormatter() -> (UUID) -> String {
        accountOptionsCache.formatter()
    }

    var filterBar: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            if let discardedFilterNotice {
                Label(discardedFilterNotice, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            FilterChipMenu(
                title: String(localized: "Account"), icon: "person.crop.circle",
                selected: $accountFilter,
                options: accountOptionsCache.ids,
                formatter: accountNameFormatter()
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
                formatter: questionTypeFilterLabel
            )
            .measuresFilterBarWidth()
            FilterChipMenu(
                title: String(localized: "Status"), icon: "doc.badge.ellipsis",
                selected: $draftFilter, options: ["draft", "published"],
                formatter: { $0 == "draft" ? String(localized: "Draft") : String(localized: "Published") }
            )
            .measuresFilterBarWidth()
            DateRangeFilterChip(title: String(localized: "Updated"), window: $updatedWindow,
                                options: PadDateRange.options)
                .measuresFilterBarWidth()
            DateRangeFilterChip(title: String(localized: "Created"), window: $createdWindow,
                                options: PadDateRange.options)
                .measuresFilterBarWidth()
            // Only shown while some account has starred questions: unstarring the
            // last favorite auto-clears the filter (see `toggleFavorite`), and an
            // always-empty Favorites view isn't worth a chip (#1008).
            if hasAnyFavorites {
                ToggleFilterChip(title: String(localized: "Favorites"), icon: "star", isOn: $favoritesOnly)
                    .measuresFilterBarWidth()
            }
            if hasActiveFilters {
                Button("Reset", systemImage: "arrow.counterclockwise", action: clearAllFilters)
                    .help("Reset all account filters (⇧⌘K)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func questionTypeFilterLabel(_ type: String) -> String {
        let label = InterviewType(rawValue: type)?.label ?? type.capitalized
        let count = scoped.count { $0.item.interviewType.rawValue == type }
        return "\(label) (\(count))"
    }

    /// The result-count summary shown as the window's toolbar subtitle beneath the
    /// "Questions" title. Names the account span the merged list covers; empty while
    /// the list is empty so the subtitle falls back to the static "All accounts" cue.
    var countSubtitle: String {
        guard !scoped.isEmpty else { return "" }

        let shown = sorted.count
        let accountCount = accounts.mergeableAccounts.count
        let hasSearch = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let base = (activeFilterCount > 0 || favoritesOnly || hasSearch)
            ? String(localized: "\(shown) of \(scoped.count) questions across \(accountCount) accounts")
            : (shown == 1
                ? String(localized: "\(shown) question across \(accountCount) accounts")
                : String(localized: "\(shown) questions across \(accountCount) accounts"))
        return base
    }

    /// Names any accounts whose fetch failed. A rejected API key reads differently from a
    /// transient network blip (red key glyph plus a jump to the account editor, vs. an
    /// orange "couldn't refresh") so the two aren't confused (#622).
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
        // split the failures in one pass rather than three filters over it (#2470).
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
                        Text("Could not refresh \(networkFailed.map(\.name).joined(separator: ", ")). "
                            + "Showing the last loaded questions.")
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
