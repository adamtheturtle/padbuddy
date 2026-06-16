//
//  MergedPadsView+Bars.swift
//  coderpad
//
//  The preset, filter, count, and error bars for the combined pads list.
//

import SwiftUI

extension MergedPadsView {
    func accountName(_ id: UUID) -> String {
        accounts.accounts.first { $0.id == id }?.name ?? "Account"
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
                formatter: { accountName($0) }
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
        return (activeFilterCount > 0 || !search.isEmpty)
            ? "\(shown) of \(scoped.count) pads across \(accountCount) accounts"
            : "\(shown) \(shown == 1 ? "pad" : "pads") across \(accountCount) accounts"
    }

    /// A quiet note naming any accounts whose fetch failed, so the merged list
    /// doesn't silently look complete when one account couldn't be reached.
    @ViewBuilder
    var errorBar: some View {
        let failed = accounts.mergeableAccounts.filter { accountErrors[$0.id] != nil }
        if !failed.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    // Decorative: the adjacent message already states the failure, so
                    // VoiceOver shouldn't announce the bare symbol name before it.
                    .accessibilityHidden(true)
                Text("Couldn't refresh \(failed.map(\.name).joined(separator: ", ")). "
                    + "Showing the last loaded pads.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}
