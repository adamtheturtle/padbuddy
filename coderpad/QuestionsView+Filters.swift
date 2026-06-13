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
            FilterChipMenu(title: "Language", icon: "chevron.left.slash.chevron.right",
                           selected: $languageFilter, options: availableLanguages,
                           formatter: { $0.languageDisplayName })
                .measuresFilterBarWidth()
            SearchableFilterChip(title: "Owner", icon: "person",
                                 selected: $ownerFilter, options: availableOwners,
                                 formatter: { directory.display($0) },
                                 meEmail: accounts.currentAccount?.userEmail)
                .measuresFilterBarWidth()
            FilterChipMenu(title: "Type", icon: "tag",
                           selected: $typeFilter,
                           options: InterviewType.allCases.map(\.rawValue),
                           formatter: { InterviewType(rawValue: $0)?.label ?? $0.capitalized })
                .measuresFilterBarWidth()
            FilterChipMenu(title: "Status", icon: "doc.badge.ellipsis",
                           selected: $draftFilter, options: ["draft", "published"],
                           formatter: { $0.capitalized })
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
                    languageFilter = nil; ownerFilter = nil
                    typeFilter = nil; draftFilter = nil
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
                                    isActive: favoritesOnly) {
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
                                    isActive: isActiveSearch(item.search)) {
                        apply(item.search)
                    }
                }
                ForEach(saved) { item in
                    SavedSearchChip(name: item.name, isActive: isActiveSearch(item)) {
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

    /// A sparkle button that fills the name field with an on-device suggestion
    /// built from the active filters. Shown only when the model is available; the
    /// field stays fully editable and the user opts in per save.
    var suggestNameButton: some View {
        Button(action: suggestName) {
            if isSuggestingName {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "sparkles")
            }
        }
        .buttonStyle(.borderless)
        .disabled(isSuggestingName)
        .help("Suggest a name from the current filters")
        .accessibilityLabel("Suggest a name")
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

    /// Interprets the typed query on device and, when it maps to a real filter set,
    /// applies it and closes the sheet. A query the model can't turn into any
    /// filter leaves the list untouched and surfaces a gentle hint in the sheet.
    func applySmartFilter() async {
        let query = smartFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isInterpreting = true
        smartFilterFailed = false
        defer { isInterpreting = false }
        let owners = availableOwners.map {
            SearchInterpreter.OwnerOption(email: $0, name: directory.display($0))
        }
        let result = await SearchInterpreter.interpretQuestions(
            query, languages: availableLanguages, owners: owners
        )
        if let result {
            apply(result)
            showSmartFilter = false
        } else {
            smartFilterFailed = true
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
}
