//
//  MergedQuestionsView+Bars.swift
//  coderpad
//
//  The preset, filter, count, and error bars for the combined questions list.
//

import SwiftUI

extension MergedQuestionsView {
    func accountName(_ id: UUID) -> String {
        accounts.accounts.first { $0.id == id }?.name ?? "Account"
    }

    var presetsBar: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            if hasAnyFavorites {
                SavedSearchChip(name: "Favorites", systemImage: "star.fill", isActive: favoritesOnly) {
                    favoritesOnly.toggle()
                    if favoritesOnly { mineOnly = false; clearChips() }
                }
            }
            SavedSearchChip(name: "Mine", systemImage: "person.fill", isActive: mineOnly) {
                mineOnly.toggle()
            }
        }
        .padding(.horizontal, 12).padding(.top, 6)
    }

    /// Clear the categorical chips (not the presets), shared by the Favorites toggle
    /// so turning it on doesn't leave a stale language/owner filter applied.
    private func clearChips() {
        languageFilter = nil; ownerFilter = nil; typeFilter = nil
        draftFilter = nil; accountFilter = nil; search = ""
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
            FilterChipMenu(
                title: String(localized: "Status"), icon: "doc.badge.ellipsis",
                selected: $draftFilter, options: ["draft", "published"],
                formatter: { $0 == "draft" ? String(localized: "Draft") : String(localized: "Published") }
            )
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
    /// "Questions" title. Names the account span the merged list covers; empty while
    /// the list is empty so the subtitle falls back to the static "All accounts" cue.
    var countSubtitle: String {
        guard !scoped.isEmpty else { return "" }
        let shown = sorted.count
        let accountCount = accounts.mergeableAccounts.count
        return (activeFilterCount > 0 || favoritesOnly || !search.isEmpty)
            ? String(localized: "\(shown) of \(scoped.count) questions across \(accountCount) accounts")
            : (shown == 1
                ? String(localized: "\(shown) question across \(accountCount) accounts")
                : String(localized: "\(shown) questions across \(accountCount) accounts"))
    }

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
                    + "Showing the last loaded questions.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}
