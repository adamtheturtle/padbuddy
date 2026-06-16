//
//  PadsView+FilterBar.swift
//  coderpad
//

import SwiftUI

extension PadsView {
    /// Built-in chips shown ahead of the user's saved searches, mirrored in the
    /// sidebar's Defaults section.
    var defaultSearches: [DefaultSearch] {
        DefaultSearch.padDefaults(me: accounts.currentAccount?.userEmail)
    }

    @ViewBuilder
    var savedSearchesBar: some View {
        let saved = savedSearches.searches(account: accounts.currentAccountID, kind: .pads)
        let defaults = defaultSearches
        if !defaults.isEmpty || !saved.isEmpty {
            // A wrapping flow layout rather than a horizontal scroll, so the chips
            // reflow onto extra lines as the pane narrows instead of clipping a
            // long saved-search name off the trailing edge.
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(defaults) { item in
                    SavedSearchChip(name: item.search.name, systemImage: item.icon,
                                    isActive: isActiveSearch(item.search)) {
                        apply(item.search)
                    }
                }
                ForEach(saved) { item in
                    SavedSearchChip(name: item.name, isActive: isActiveSearch(item)) {
                        apply(item)
                    } onDelete: {
                        if let account = accounts.currentAccountID {
                            savedSearches.remove(id: item.id, account: account, kind: .pads)
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 6)
        }
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
                formatter: { $0.languageDisplayName }
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
                .buttonStyle(.link)
                .controlSize(.small)
            }
            if activeFilterCount > 0 || !search.isEmpty {
                Button {
                    saveSearchName = ""
                    showSaveSearch = true
                } label: {
                    Label("Save…", systemImage: "bookmark")
                        .labelStyle(.titleAndIcon)
                }
                // A link-styled action so it reads as a verb, not another
                // neutral capsule filter chip sitting in the same bar.
                .buttonStyle(.link)
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
}
