//
//  MergedPadsView+Bars.swift
//  coderpad
//
//  The preset, filter, count, and error bars for the combined pads list.
//

import SwiftUI

extension MergedPadsView {
    /// A name lookup for the Account chip's formatter that builds a `[UUID: String]`
    /// index once and captures it, so resolving each option is O(1) rather than a
    /// linear scan of `accounts` per option (#368).
    func accountNameFormatter() -> (UUID) -> String {
        let names = Dictionary(accounts.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return { names[$0] ?? "Account" }
    }

    /// Cross-account quick presets: "Mine" (owned by each account's own user) and
    /// "Active" (in-progress sessions), styled like the single-account saved-search
    /// chips so the merged list feels of a piece with `PadsView`.
    var presetsBar: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            SavedSearchChip(name: "Mine", systemImage: "person.fill", isActive: mineOnly) {
                mineOnly.toggle()
            }
            SavedSearchChip(name: "Active", systemImage: "bolt.fill",
                            isActive: stateFilter == .active) {
                stateFilter = stateFilter == .active ? nil : .active
            }
        }
        .padding(.horizontal, 12).padding(.top, 6)
    }

    var filterBar: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            FilterChipMenu(
                title: String(localized: "Account"), icon: "person.crop.circle",
                selected: $accountFilter,
                options: accounts.mergeableAccounts.map(\.id),
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
                formatter: { $0.languageDisplayName }
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
            // On-device natural-language filtering: describe what you want and the
            // model maps it onto these chips. A verb-style link like Save, shown
            // only when the model is available.
            if SearchInterpreter.isAvailable {
                Button {
                    smartFilterText = ""
                    smartFilterFailed = false
                    showSmartFilter = true
                } label: {
                    Label("Smart Filter…", systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                }
                .linkButtonStyle()
                .controlSize(.small)
            }
            if activeFilterCount > 0 {
                Button(role: .destructive) {
                    clearAllFilters()
                } label: {
                    Label("Clear", systemImage: "xmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
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
        let base = (activeFilterCount > 0 || !search.isEmpty)
            ? String(localized: "\(shown) of \(scoped.count) pads across \(accountCount) accounts")
            : (shown == 1
                ? String(localized: "\(shown) pad across \(accountCount) accounts")
                : String(localized: "\(shown) pads across \(accountCount) accounts"))
        return base + freshnessSuffix
    }

    /// A trailing " · Refreshing…" / " · Updated X ago" cue appended to the count, so the
    /// cached-then-refreshed list shows its freshness without adding chrome (#619).
    private var freshnessSuffix: String {
        if isLoading {
            return " · " + String(localized: "Refreshing…")
        }
        if let lastRefreshed {
            return " · " + String(localized: "Updated \(RelativeDateLabel.labels(for: lastRefreshed).relative)")
        }
        return ""
    }

    /// A quiet note naming any accounts whose fetch failed, so the merged list
    /// doesn't silently look complete when one account couldn't be reached. A rejected
    /// API key reads differently from a transient network blip (red key glyph plus a
    /// jump to the account editor, vs. an orange "couldn't refresh"), so the two aren't
    /// confused (#622).
    @ViewBuilder
    var errorBar: some View {
        let failed = accounts.mergeableAccounts.filter { accountErrors[$0.id] != nil }
        let authFailed = failed.filter { healthMonitor.isUnauthorized($0.id) }
        let networkFailed = failed.filter { !healthMonitor.isUnauthorized($0.id) }
        if !failed.isEmpty {
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
