//
//  PadsView+FilterBar.swift
//  coderpad
//

import SwiftUI

extension PadsView {
    var availableStates: [PadState] {
        chipOptionsCache.states
    }

    var availableLanguages: [String] {
        chipOptionsCache.languages
    }

    var availableOwners: [String] {
        chipOptionsCache.owners
    }

    var availableTeams: [String] {
        chipOptionsCache.teams
    }

    /// Recompute the four filter-chip option lists once per pad-collection change.
    /// `body` re-runs several times per click as the selection settles, and only the
    /// selection differs across those passes — rebuilding each Set+sort over the whole
    /// org every time is what this avoids (#416). Called at the top of `body` alongside
    /// `refreshFiltered()`, so every `available*` read in that pass is O(1) and current.
    func refreshChipOptions() {
        guard chipOptionsCache.padsRevision != padsRevision else { return }

        chipOptionsCache.states = Array(Set(pads.map(\.status))).sorted { $0.label < $1.label }
        chipOptionsCache.languages = Array(Set(pads.compactMap { $0.language?.lowercased() })
            .filter { !$0.isEmpty }).sorted()
        chipOptionsCache.owners = Array(Set(pads.map(\.ownerEmail)).filter { !$0.isEmpty }).sorted()
        chipOptionsCache.teams = Array(Set(pads.compactMap { $0.team?.name })).sorted()
        chipOptionsCache.padsRevision = padsRevision
    }

    var filterBar: some View {
        // A wrapping flow layout rather than a horizontal scroll, so the chips
        // reflow onto extra lines as the pane narrows instead of forcing a wide
        // minimum column width. Each chip reports its own width; because
        // `FilterBarWidthKey` reduces by `max`, the column floor becomes the
        // widest single chip, letting the pane be dragged much thinner.
        FlowLayout(spacing: 8, lineSpacing: 8) {
            FilterChipMenu(
                title: String(localized: "State"),
                icon: "circle.fill",
                selected: $stateFilter,
                options: availableStates,
                formatter: { $0.label }
            )
            .measuresFilterBarWidth()
            FilterChipMenu(
                title: String(localized: "Language"),
                icon: "chevron.left.slash.chevron.right",
                selected: $languageFilter,
                options: availableLanguages,
                formatter: { $0.coderPadLanguageDisplayName }
            )
            .measuresFilterBarWidth()
            SearchableFilterChip(
                title: String(localized: "Owner"),
                icon: "person",
                selected: $ownerFilter,
                options: availableOwners,
                formatter: { directory.display($0) },
                meEmail: accounts.currentAccount?.userEmail
            )
            .measuresFilterBarWidth()
            FilterChipMenu(
                title: String(localized: "Team"),
                icon: "person.3",
                selected: $teamFilter,
                options: availableTeams,
                formatter: { $0 }
            )
            .measuresFilterBarWidth()
            FilterChipMenu(
                title: String(localized: "Type"),
                icon: "tag",
                selected: $typeFilter,
                options: InterviewType.allCases.map(\.rawValue),
                formatter: { InterviewType(rawValue: $0)?.label ?? $0.capitalized }
            )
            .measuresFilterBarWidth()
            DateRangeFilterChip(
                title: String(localized: "Updated"),
                window: $updatedWindow,
                options: Self.dateRangeOptions
            )
            .measuresFilterBarWidth()
            DateRangeFilterChip(
                title: String(localized: "Created"),
                window: $createdWindow,
                options: Self.dateRangeOptions
            )
            .measuresFilterBarWidth()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
