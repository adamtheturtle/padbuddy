//
//  QuestionsView+Filters.swift
//  coderpad
//

import SwiftUI

extension QuestionsView {
    var filterBar: some View {
        // A wrapping flow layout rather than a horizontal scroll, so the chips
        // reflow onto extra lines as the pane narrows instead of clipping the
        // trailing chips off the edge. Mirrors the pad filter bar.
        FlowLayout(spacing: 8, lineSpacing: 8) {
            FilterChipMenu(title: String(localized: "Language"), icon: "chevron.left.slash.chevron.right",
                           selected: $languageFilter, options: availableLanguages,
                           formatter: { $0.coderPadLanguageDisplayName })
                .measuresFilterBarWidth()
            SearchableFilterChip(title: String(localized: "Owner"), icon: "person",
                                 selected: $ownerFilter, options: availableOwners,
                                 formatter: { directory.display($0) },
                                 meEmail: accounts.currentAccount?.userEmail)
                .measuresFilterBarWidth()
            FilterChipMenu(title: String(localized: "Type"), icon: "tag",
                           selected: $typeFilter,
                           options: InterviewType.allCases.map(\.rawValue),
                           formatter: { InterviewType(rawValue: $0)?.label ?? $0.capitalized })
                .measuresFilterBarWidth()
            FilterChipMenu(title: String(localized: "Status"), icon: "doc.badge.ellipsis",
                           selected: $draftFilter, options: ["draft", "published"],
                           formatter: { $0 == "draft" ? String(localized: "Draft") : String(localized: "Published") })
                .measuresFilterBarWidth()
            // Only shown while the account has starred questions: unstarring the
            // last favorite auto-clears the filter (see `toggleFavorite`), and an
            // always-empty Favorites view isn't worth a chip (#1008).
            if hasAnyFavorites {
                ToggleFilterChip(title: String(localized: "Favorites"), icon: "star", isOn: $favoritesOnly)
                    .measuresFilterBarWidth()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func apply(_ saved: NamedSearch) {
        // Applying a recall chip turns Favorites off; the two are mutually
        // exclusive presets in the search bar.
        favoritesOnly = false
        search = saved.search
        languageFilter = saved.languageFilter
        ownerFilter = saved.ownerFilter
        // Enum-like fields restore validated: a stale or corrupt snapshot value
        // would otherwise open the list permanently empty behind an opaque
        // filter (#1651, #1653).
        typeFilter = FilterValueValidation.interviewType(saved.typeFilter)
        draftFilter = FilterValueValidation.draftState(saved.draftFilter)
    }

    func clearAllFilters() {
        search = ""
        languageFilter = nil
        ownerFilter = nil
        typeFilter = nil
        draftFilter = nil
        favoritesOnly = false
    }

    /// Whether the current account has at least one starred question, gating the
    /// Favorites preset chip. A live store read (not the per-render `favoriteIDSet`
    /// memo), so the chip and the auto-clear guard both see a star toggled this
    /// same pass; mirrors `MergedQuestionsView.hasAnyFavorites`.
    var hasAnyFavorites: Bool {
        !favorites.favorites(account: accounts.currentAccountID).isEmpty
    }

    var hasActiveFilters: Bool {
        let hasSearch = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasSearch || languageFilter != nil || ownerFilter != nil || typeFilter != nil
            || draftFilter != nil || favoritesOnly
    }

    func isActiveSearch(_ saved: NamedSearch) -> Bool {
        !favoritesOnly && search == saved.search && languageFilter == saved.languageFilter
            && ownerFilter == saved.ownerFilter && typeFilter == saved.typeFilter
            && draftFilter == saved.draftFilter
    }

    func captureCurrentSearch(named name: String) -> NamedSearch {
        NamedSearch(
            name: name, search: search,
            languageFilter: languageFilter, ownerFilter: ownerFilter,
            typeFilter: typeFilter, draftFilter: draftFilter
        )
    }

    /// A stable, Equatable digest of the live filter fields, so a single `onChange`
    /// republishes the signature no matter which control edited a filter. Built from
    /// the same fields as `captureCurrentSearch`.
    var filterSignature: String {
        FilterSignature.make([
            search.trimmingCharacters(in: .whitespacesAndNewlines),
            languageFilter,
            ownerFilter,
            typeFilter,
            draftFilter
        ])
    }

    // MARK: - Live filter persistence

    static func liveFilterKey(_ account: UUID) -> String {
        "questions.liveFilter.\(account.uuidString)"
    }

    /// Persist the current live filters for the signed-in account, so the list
    /// reopens with the same view next launch. Scoped per account because owners and
    /// languages are org-specific. Skipped until the initial restore has run, so the
    /// empty startup state never clobbers a saved snapshot. Mirrors `PadsView`.
    func persistFilters() {
        guard didRestoreFilters, let account = accounts.currentAccountID else { return }

        if let data = try? JSONEncoder().encode(captureCurrentSearch(named: "")) {
            UserDefaults.standard.set(data, forKey: Self.liveFilterKey(account))
        }
    }

    /// Restore the persisted live filters for the current account, once. A pending
    /// request (handled by `applyPendingRequest`) is applied afterward so it always
    /// wins over a restored snapshot. The `Favorites` preset isn't part of the saved
    /// `NamedSearch`, matching how `PadsView` leaves its "Mine" preset unpersisted.
    /// Guarded so a later `onAppear` (tab switch, window reopen) can't reapply the
    /// saved snapshot over filters the user changed this session (#1639).
    func restoreFilters() {
        guard !didRestoreFilters, let account = accounts.currentAccountID else { return }

        didRestoreFilters = true
        guard let data = UserDefaults.standard.data(forKey: Self.liveFilterKey(account)),
              let snapshot = try? JSONDecoder().decode(NamedSearch.self, from: data) else { return }

        apply(snapshot)
    }

    /// Re-restore for a newly selected account: clear the previous account's filters
    /// (meaningless against a different org) then load that account's own, and let the
    /// new account restore its own last-open question once its list loads.
    func restoreFiltersForAccountChange() {
        didRestoreFilters = false
        search = ""
        languageFilter = nil; ownerFilter = nil
        typeFilter = nil; draftFilter = nil
        favoritesOnly = false
        restoreFilters()
        didRestoreSelection = false
    }
}
