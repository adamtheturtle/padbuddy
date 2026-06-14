//
//  QuestionsView+List.swift
//  coderpad
//

import AppKit
import SwiftUI

extension QuestionsView {
    var filtered: [Question] {
        let favoriteIDs = favoritesOnly ? favoriteIDSet : nil
        return questions.filter { question in
            (favoriteIDs == nil || favoriteIDs!.contains(question.id)) &&
                (languageFilter == nil || (question.language ?? "").lowercased() == languageFilter) &&
                (ownerFilter == nil || question.ownerEmail == ownerFilter) &&
                (typeFilter == nil || question.interviewType.rawValue == typeFilter) &&
                (draftFilter == nil
                    || (draftFilter == "draft" && question.isDraft == true)
                    || (draftFilter == "published" && question.isDraft != true)) &&
                // Locale-aware case-insensitive matching (see PadListLogic.matches).
                (search.isEmpty
                    || question.title.localizedCaseInsensitiveContains(search)
                    || question.ownerEmail.localizedCaseInsensitiveContains(search)
                    || (question.language ?? "").localizedCaseInsensitiveContains(search)
                    || (question.authorName ?? "").localizedCaseInsensitiveContains(search))
        }
    }

    /// The current account's favorite question ids, as a set for quick membership
    /// tests in filtering, sorting, and row decoration.
    var favoriteIDSet: Set<Int> {
        Set(favorites.favorites(account: accounts.currentAccountID))
    }

    /// Filtered questions arranged by the active sort. "Last used" is backed by
    /// `updatedAt` — the only per-question recency signal the API exposes.
    /// Favorites keep their natural position in the sort order rather than being
    /// pinned to the top; the Favorites chip is there to filter the list down to
    /// them when needed.
    var sorted: [Question] {
        let items = filtered
        switch sort {
        case .titleAsc:
            return items.sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        case .titleDesc:
            return items.sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedDescending
            }
        case .lastUsedDesc:
            return items.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        case .lastUsedAsc:
            return items.sorted { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }
        case .usedDesc:
            return items.sorted { ($0.used ?? 0) > ($1.used ?? 0) }
        case .usedAsc:
            return items.sorted { ($0.used ?? 0) < ($1.used ?? 0) }
        }
    }

    /// The question to select after the question with `id` is deleted: the next
    /// visible row, then the previous, mirroring `PadsView.neighborSelection`, so
    /// deleting the open question keeps the detail pane populated instead of
    /// snapping to the empty placeholder. Resolved against `sorted` — the list the
    /// user actually sees.
    func neighborSelection(forDeletedQuestion id: Int) -> Question? {
        let visible = sorted
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return visible.first }
        if visible.indices.contains(index + 1) { return visible[index + 1] }
        if visible.indices.contains(index - 1) { return visible[index - 1] }
        return nil
    }

    /// Whether a question mutation notification applies to this single-account view:
    /// true when it carries no account (legacy) or names this view's account. Per-org
    /// ids collide across accounts, so a bare id from another account must not mutate
    /// this list.
    func scopedToThisAccount(_ account: UUID?) -> Bool {
        guard let account else { return true }
        return account == accounts.currentAccountID
    }

    var availableLanguages: [String] {
        Array(Set(questions.compactMap { $0.language?.lowercased() }).filter { !$0.isEmpty }).sorted()
    }

    var availableOwners: [String] {
        Array(Set(questions.map(\.ownerEmail)).filter { !$0.isEmpty }).sorted()
    }

    var activeFilterCount: Int {
        [languageFilter, ownerFilter, typeFilter, draftFilter].compactMap(\.self).count
    }

    var sidebar: some View {
        Group {
            if isLoading, questions.isEmpty {
                ProgressView("Loading questions…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, questions.isEmpty {
                APIErrorView(error: error) { Task { await reload() } }
            } else {
                VStack(spacing: 0) {
                    savedSearchesBar
                    filterBar
                    Divider()
                    questionsList
                }
            }
        }
        // Bubble the count up to the window toolbar (shown beneath the "Questions"
        // title) so the list length is legible at a glance.
        .reportsSectionCount(countSubtitle)
        // The search field itself lives on the `NavigationSplitView` in `MainSplit`
        // (trailing window toolbar, Finder-style); this column only owns the section
        // actions below.
        .toolbar(id: "questions.toolbar") {
            ToolbarItem(id: "sort") {
                Menu {
                    QuestionSortMenuContent(sort: $sort)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort questions")
                .accessibilityLabel("Sort questions")
            }
            ToolbarItem(id: "reload") {
                ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
            }
            if #available(macOS 26, *) {
                ToolbarSpacer(.fixed)
            }
            ToolbarItem(id: "new", placement: .primaryAction) {
                Button { showCreate = true } label: {
                    Label("New Question", systemImage: "plus")
                }
                .help("Create a new question (⇧⌘N)")
                .accessibilityLabel("New Question")
                .disabled(client.apiKey.isEmpty)
            }
        }
    }

    private var questionsList: some View {
        List(selection: $selectedQuestionID) {
            ForEach(sorted) { question in
                QuestionRow(question: question, isFavorite: favoriteIDSet.contains(question.id),
                            onToggleFavorite: { toggleFavorite(question) })
                    .tag(question.id)
                    .contextMenu { questionContextMenu(question) }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        favoriteSwipeButton(question)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            // Same path as the context menu and detail
                            // "New Pad" button: select the question, then
                            // let its detail pane create and open the pad.
                            selection = question
                            nav.createPadForQuestionID = question.id
                        } label: {
                            Label("New Pad", systemImage: "doc.badge.plus")
                        }
                        .tint(.accentColor)
                    }
            }
        }
        .listStyle(.inset)
        // Re-identify the list when the filter, favorites toggle, or sort changes so
        // SwiftUI does a fresh render (fast — same as the initial load) instead of an
        // in-place diff of the visible set against thousands of rows, which made
        // clearing a filter slow on large orgs. Keyed off the list-shape inputs only,
        // so background `questions` refreshes still take the cheap incremental diff
        // and keep scroll position.
        .id("\(filterSignature)|\(favoritesOnly)|\(sort.rawValue)")
        .transaction { $0.animation = nil }
        .macPullToRefresh { await reload() }
        // Scene-scoped, mirroring PadsView: the Question menu commands
        // stay enabled whenever this window is frontmost and a question
        // is selected, not only while the list holds keyboard focus.
        .focusedSceneValue(\.focusedQuestion, selection)
    }

    /// Right-click actions for a question row. Actions that need the detail pane's
    /// machinery (its sheets and confirmations) select the question first, then
    /// route the request through `AppNavigation` — the same pattern as "New Pad
    /// from Question" — so the detail view performs them with its existing UI.
    @ViewBuilder
    func questionContextMenu(_ question: Question) -> some View {
        Button {
            // Mirror the detail view's "New Pad" button: select the question so
            // its detail pane shows, then let that pane create the pad and open
            // it inline.
            selection = question
            nav.createPadForQuestionID = question.id
        } label: {
            Label("New Pad from Question", systemImage: "plus.rectangle.on.rectangle")
        }
        favoriteToggleButton(question)
        Button {
            selection = question
            nav.editQuestionID = question.id
        } label: {
            Label("Edit Question…", systemImage: "pencil")
        }
        Divider()
        Button {
            copyToPasteboard(question.displayTitle)
        } label: {
            Label("Copy Title", systemImage: "doc.on.doc")
        }
        Button {
            ownerFilter = question.ownerEmail
        } label: {
            Label("Show Questions from \(directory.display(question.ownerEmail))", systemImage: "person")
        }
        if let lang = question.language, !lang.isEmpty {
            Button {
                languageFilter = lang.lowercased()
            } label: {
                Label("Show \(lang.languageDisplayName) Questions",
                      systemImage: "chevron.left.slash.chevron.right")
            }
        }
        Divider()
        Button(role: .destructive) {
            selection = question
            nav.deleteQuestionID = question.id
        } label: {
            Label("Delete Question…", systemImage: "trash")
        }
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Context-menu entry that stars or unstars a question. Favorites can be
    /// filtered to via the Favorites chip and lead the menu bar's "New Pad from
    /// Question" submenu, so a frequently used question is quick to reach.
    @ViewBuilder
    func favoriteToggleButton(_ question: Question) -> some View {
        let isFavorite = favoriteIDSet.contains(question.id)
        Button {
            toggleFavorite(question)
        } label: {
            Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: isFavorite ? "star.slash" : "star")
        }
    }

    /// Leading swipe action mirroring the favorite context-menu entry.
    @ViewBuilder
    func favoriteSwipeButton(_ question: Question) -> some View {
        let isFavorite = favoriteIDSet.contains(question.id)
        Button {
            toggleFavorite(question)
        } label: {
            Label(isFavorite ? "Unfavorite" : "Favorite",
                  systemImage: isFavorite ? "star.slash" : "star")
        }
        .tint(.yellow)
    }

    func toggleFavorite(_ question: Question) {
        guard let account = accounts.currentAccountID else { return }
        favorites.toggle(question.id, account: account)
        // Unstarring the last favorite hides the Favorites chip, so drop the
        // filter too — otherwise it would strand the list on an empty result with
        // no visible control to turn it back off.
        if favoritesOnly, favoriteIDSet.isEmpty {
            favoritesOnly = false
        }
    }
}
