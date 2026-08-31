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
            if let discardedFilterNotice {
                Label(discardedFilterNotice, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
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
                           formatter: questionTypeFilterLabel)
                .measuresFilterBarWidth()
            FilterChipMenu(title: String(localized: "Status"), icon: "doc.badge.ellipsis",
                           selected: $draftFilter, options: ["draft", "published"],
                           formatter: { $0 == "draft" ? String(localized: "Draft") : String(localized: "Published") })
                .measuresFilterBarWidth()
            DateRangeFilterChip(title: String(localized: "Updated"), window: $updatedWindow,
                                options: PadDateRange.options)
                .measuresFilterBarWidth()
            DateRangeFilterChip(title: String(localized: "Created"), window: $createdWindow,
                                options: PadDateRange.options)
                .measuresFilterBarWidth()
            // Only shown while the account has starred questions: unstarring the
            // last favorite auto-clears the filter (see `toggleFavorite`), and an
            // always-empty Favorites view isn't worth a chip (#1008).
            if hasAnyFavorites {
                ToggleFilterChip(title: String(localized: "Favorites"), icon: "star", isOn: $favoritesOnly)
                    .measuresFilterBarWidth()
            }
            if hasActiveFilters {
                FilterResetChip(action: clearAllFilters)
                    .help("Reset filters to account defaults (⇧⌘K)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(questionFilterAccessibilitySummary)
    }

    private func questionTypeFilterLabel(_ type: String) -> String {
        let label = InterviewType(rawValue: type)?.label ?? type.capitalized
        let count = questions.count { $0.interviewType.rawValue == type }
        return "\(label) (\(count))"
    }

    private var questionFilterAccessibilitySummary: String {
        var active: [String] = []
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            active.append("Search")
        }
        if let languageFilter {
            active.append("Language: \(languageFilter.coderPadLanguageDisplayName)")
        }
        if ownerFilter != nil {
            active.append("Owner")
        }
        if let typeFilter {
            active.append("Type: \(InterviewType(rawValue: typeFilter)?.label ?? typeFilter)")
        }
        if let draftFilter {
            active.append("Status: \(draftFilter.capitalized)")
        }
        if favoritesOnly {
            active.append("Favorites")
        }
        if updatedWindow.isActive {
            active.append("Updated date")
        }
        if createdWindow.isActive {
            active.append("Created date")
        }
        return active.isEmpty ? String(localized: "Filters, none active")
            : String(localized: "Active filters: \(active.formatted())")
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
        let restoredType = FilterValueValidation.interviewType(saved.typeFilter)
        let restoredDraft = FilterValueValidation.draftState(saved.draftFilter)
        if (saved.typeFilter != nil && restoredType == nil) || (saved.draftFilter != nil && restoredDraft == nil) {
            discardedFilterNotice = String(localized: "Invalid saved question filters were discarded.")
        }
        typeFilter = restoredType
        draftFilter = restoredDraft
        updatedWindow = saved.updatedWindow ?? DateWindow()
        createdWindow = saved.createdWindow ?? DateWindow()
    }

    func clearAllFilters() {
        search = ""
        languageFilter = nil
        ownerFilter = nil
        typeFilter = nil
        draftFilter = nil
        favoritesOnly = false
        updatedWindow = DateWindow()
        createdWindow = DateWindow()
    }

    /// Whether the current account has at least one starred question, gating the
    /// Favorites preset chip. A live store read (not the per-render `favoriteIDSet`
    /// memo), so the chip and the auto-clear guard both see a star toggled this
    /// same pass; mirrors `MergedQuestionsView.hasAnyFavorites`.
    var hasAnyFavorites: Bool {
        favorites.hasFavorites(account: accounts.currentAccountID)
    }

    var hasActiveFilters: Bool {
        let hasSearch = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasSearch || languageFilter != nil || ownerFilter != nil || typeFilter != nil
            || draftFilter != nil || favoritesOnly || updatedWindow.isActive || createdWindow.isActive
    }

    func isActiveSearch(_ saved: NamedSearch) -> Bool {
        !favoritesOnly
            && updatedWindow == (saved.updatedWindow ?? DateWindow())
            && createdWindow == (saved.createdWindow ?? DateWindow())
            && FilterSignature.make([search, languageFilter, ownerFilter, typeFilter, draftFilter])
            == FilterSignature.make([
                saved.search, saved.languageFilter, saved.ownerFilter, saved.typeFilter, saved.draftFilter
            ])
    }

    func captureCurrentSearch(named name: String) -> NamedSearch {
        NamedSearch(
            name: name, search: search,
            languageFilter: languageFilter, ownerFilter: ownerFilter,
            typeFilter: typeFilter,
            updatedWindow: updatedWindow.isActive ? updatedWindow : nil,
            createdWindow: createdWindow.isActive ? createdWindow : nil,
            draftFilter: draftFilter
        )
    }

    /// A stable, Equatable digest of the live filter fields, so a single `onChange`
    /// republishes the signature no matter which control edited a filter. Built from
    /// the same fields as `captureCurrentSearch`.
    var filterSignature: FilterSignature {
        FilterSignature.make([
            search.trimmingCharacters(in: .whitespacesAndNewlines),
            languageFilter,
            ownerFilter,
            typeFilter,
            draftFilter,
            updatedWindow.signatureToken,
            createdWindow.signatureToken,
            dateFilterClockTick.description
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

        let snapshot = captureCurrentSearch(named: "")

        // Debounced: this fires on every filter change, including each keystroke in
        // the search field, and the snapshot is only read at launch (#4783).
        LiveFilterPersistence.shared.schedule(key: Self.liveFilterKey(account)) {
            if let data = try? SharedCoders.encoder.encode(snapshot) {
                UserDefaults.standard.set(data, forKey: Self.liveFilterKey(account))
            }
        }
    }

    /// Writes any debounced snapshot immediately, so leaving the pane does not lose
    /// the filters it was showing.
    func flushPersistedFilters() {
        guard let account = accounts.currentAccountID else { return }

        LiveFilterPersistence.shared.flush(key: Self.liveFilterKey(account))
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
              NamedSearch.snapshotDataIsWithinLimit(data),
              let snapshot = try? JSONDecoder().decode(NamedSearch.self, from: data) else { return }

        apply(snapshot)
    }

    /// Re-restore for a newly selected account: clear the previous account's filters
    /// (meaningless against a different org) then load that account's own, and let the
    /// new account restore its own last-open question once its list loads.
    func restoreFiltersForAccountChange() {
        reloadGeneration &+= 1
        let warm = accounts.currentAccountID.map { QuestionsCacheStore.shared.cached($0) } ?? []
        questions = warm
        questionsRevision &+= 1
        selectedQuestionIDs = []
        selectedQuestionID = nil
        selection = nil
        pendingSelectQuestionID = nil
        pendingScrollToID = nil
        error = nil
        isLoading = warm.isEmpty && accounts.currentAccountID != nil

        didRestoreFilters = false
        search = ""
        languageFilter = nil; ownerFilter = nil
        typeFilter = nil; draftFilter = nil
        updatedWindow = DateWindow(); createdWindow = DateWindow()
        favoritesOnly = false
        restoreFilters()
        didRestoreSelection = false
    }

    var dateFilterClockActive: Bool {
        updatedWindow.isActive || createdWindow.isActive
    }

    func runDateFilterClock() async {
        guard dateFilterClockActive else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }

            dateFilterClockTick &+= 1
        }
    }
}
