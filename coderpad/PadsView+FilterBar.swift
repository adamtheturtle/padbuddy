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
        // Keyed on the directory too. Owners are listed in the order their *display
        // names* read, so a directory that finishes loading — or a member renamed —
        // changes the right order without changing the pads at all, and keying on
        // `padsRevision` alone left the list sorted by the previous names (#2487).
        let key = PadChipOptionsCache.Key(padsRevision: padsRevision, directoryRevision: directory.revision)
        guard chipOptionsCache.key != key else { return }

        chipOptionsCache.states = Array(Set(pads.map(\.status))).sorted { $0.label < $1.label }
        // Normalized before de-duplication and sorted locale-aware, so case variants
        // don't become separate chips for the same filter and the order follows the
        // user's locale rather than Unicode scalar values.
        chipOptionsCache.languages = Set(pads.compactMap {
            $0.language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        .filter { !$0.isEmpty }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        // Whitespace-only owner/team values would render blank-looking, hard to
        // deselect options (#1661, mirroring the question owners fix in #1662).
        chipOptionsCache.owners = Set(pads.map { $0.ownerEmail.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { !$0.isEmpty }
            .sorted {
                directory.display($0)
                    .localizedCaseInsensitiveCompare(directory.display($1)) == .orderedAscending
            }
        chipOptionsCache.teams = Set(pads.compactMap {
            $0.team?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        .filter { !$0.isEmpty }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        chipOptionsCache.key = key
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(padFilterAccessibilitySummary)
    }

    private var padFilterAccessibilitySummary: String {
        var active: [String] = []
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { active.append("Search") }
        if let stateFilter { active.append("State: \(stateFilter.label)") }
        if let languageFilter { active.append("Language: \(languageFilter.coderPadLanguageDisplayName)") }
        if ownerFilter != nil { active.append("Owner") }
        if let teamFilter { active.append("Team: \(teamFilter)") }
        if let typeFilter { active.append("Type: \(InterviewType(rawValue: typeFilter)?.label ?? typeFilter)") }
        if updatedWindow.isActive { active.append("Updated date") }
        if createdWindow.isActive { active.append("Created date") }
        return active.isEmpty ? String(localized: "Filters, none active")
            : String(localized: "Active filters: \(active.formatted())")
    }
}
