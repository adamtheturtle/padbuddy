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
                #if os(macOS)
                .linkButtonStyle()
                #endif
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Built-in chips shown ahead of the user's saved searches, mirrored in the
    /// sidebar's Defaults section.
    var defaultSearches: [DefaultSearch] {
        DefaultSearch.questionDefaults(me: accounts.currentAccount?.userEmail)
    }

    @ViewBuilder
    var savedSearchesBar: some View {
        let saved = savedSearches.searches(account: accounts.currentAccountID, kind: .questions)
        let defaults = defaultSearches
        let hasFavorites = !favoriteIDSet.isEmpty
        if hasFavorites || !defaults.isEmpty || !saved.isEmpty {
            // A wrapping flow layout rather than a horizontal scroll, so the chips
            // reflow onto extra lines as the pane narrows instead of clipping a
            // long saved-search name off the trailing edge.
            FlowLayout(spacing: 6, lineSpacing: 6) {
                // A toggle, unlike the recall chips beside it: tapping filters the
                // list to starred questions and tapping again clears it. Shown only
                // once at least one question is starred.
                if hasFavorites {
                    SavedSearchChip(name: "Favorites", systemImage: "star.fill",
                                    isActive: favoritesOnly,
                                    maxNameLength: NamedSearch.maxNameLength) {
                        favoritesOnly.toggle()
                        // Favorites and the recall chips beside it are mutually
                        // exclusive presets, so turning Favorites on clears the
                        // active filters — otherwise a chip like "My Questions"
                        // would stay highlighted alongside it.
                        if favoritesOnly {
                            search = ""
                            languageFilter = nil; ownerFilter = nil
                            typeFilter = nil; draftFilter = nil
                        }
                    }
                }
                ForEach(defaults) { item in
                    SavedSearchChip(name: item.search.name, systemImage: item.icon,
                                    isActive: isActiveSearch(item.search),
                                    maxNameLength: NamedSearch.maxNameLength) {
                        apply(item.search)
                    }
                }
                ForEach(saved) { item in
                    SavedSearchChip(name: item.name, isActive: isActiveSearch(item),
                                    maxNameLength: NamedSearch.maxNameLength) {
                        apply(item)
                    } onDelete: {
                        if let account = accounts.currentAccountID {
                            savedSearches.remove(id: item.id, account: account, kind: .questions)
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 6)
        }
    }

    func suggestName() {
        let captured = captureCurrentSearch(named: "")
        isSuggestingName = true
        Task {
            let suggestion = await SavedSearchNamer.suggestName(for: captured)
            isSuggestingName = false
            if let suggestion { saveSearchName = suggestion }
        }
    }

    func commitSavedSearch() {
        // Return in the text field fires `onSubmit` and the default-action button can
        // also fire; guarding on the still-open sheet keeps a single keypress from
        // saving the search twice.
        guard showSaveSearch else { return }

        let trimmed = String(saveSearchName.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(NamedSearch.maxNameLength))
        guard !trimmed.isEmpty, let account = accounts.currentAccountID else { return }

        savedSearches.add(captureCurrentSearch(named: trimmed), account: account, kind: .questions)
        showSaveSearch = false
    }

    func apply(_ saved: NamedSearch) {
        // Applying a recall chip turns Favorites off; the two are mutually
        // exclusive presets in the saved-search bar.
        favoritesOnly = false
        search = saved.search
        languageFilter = saved.languageFilter
        ownerFilter = saved.ownerFilter
        typeFilter = saved.typeFilter
        draftFilter = saved.draftFilter
    }

    /// Whether the list's live filters exactly match `saved`, so its chip can show
    /// as active. Mirrors `apply` field-for-field — including `draftFilter`, which
    /// the question list has but pads don't — so editing any filter drops the
    /// highlight immediately.
    func isActiveSearch(_ saved: NamedSearch) -> Bool {
        search == saved.search &&
            languageFilter == saved.languageFilter &&
            ownerFilter == saved.ownerFilter &&
            typeFilter == saved.typeFilter &&
            draftFilter == saved.draftFilter
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
        [search, languageFilter, ownerFilter, typeFilter, draftFilter]
            .map { $0 ?? "·" }.joined(separator: "|")
    }

    /// Publish the live filter signature for the sidebar to match against the
    /// suggested and saved rows, falling back to the plain "Questions" row when
    /// nothing matches.
    func publishLiveFilter() {
        nav.questionsFilter = captureCurrentSearch(named: "")
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
    func restoreFilters() {
        guard let account = accounts.currentAccountID else { return }

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
