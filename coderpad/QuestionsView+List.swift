//
//  QuestionsView+List.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import MacPullToRefresh
import SwiftUI
import UniformTypeIdentifiers

extension QuestionsView {
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

    var activeFilterCount: Int {
        [languageFilter, ownerFilter, typeFilter, draftFilter].compactMap(\.self).count
    }

    /// How many questions the current filters resolve to, shown as the window's
    /// toolbar subtitle beneath the "Questions" title. Empty when the org has no
    /// questions at all, where a "0 questions" line would just restate the empty list.
    var countSubtitle: String {
        guard !questions.isEmpty else { return "" }

        let count = sorted.count
        return count == 1 ? String(localized: "\(count) question") : String(localized: "\(count) questions")
    }

    /// Resets the question filter chips, mirroring `MergedQuestionsView.clearAllFilters`
    /// and the single-account Pads list, so the no-match overlay's Clear Filters button
    /// has a target (#617). The search field (owned by `MainSplit`) is left untouched,
    /// matching the Pads list.
    func clearAllFilters() {
        languageFilter = nil; ownerFilter = nil
        typeFilter = nil; draftFilter = nil
        favoritesOnly = false
    }

    var sidebar: some View {
        FilterableListView(
            isLoading: isLoading,
            isEmpty: questions.isEmpty,
            error: error,
            loadingMessage: "Loading questions…",
            onReload: { await reload() },
            errorView: { error, retry in APIErrorView(error: error, onRetry: retry) },
            savedSearches: { savedSearchesBar },
            filters: { filterBar },
            list: { questionsList }
        )
        // Bubble the count up to the window toolbar (shown beneath the "Questions"
        // title) so the list length is legible at a glance.
        .reportsSectionCount(countSubtitle)
        // The search field itself lives on the `NavigationSplitView` in `MainSplit`
        // (trailing window toolbar, Finder-style); this column only owns the section
        // actions below.
        .toolbar(id: "questions") {
            ToolbarItem(id: "reload", placement: .automatic) {
                ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
            }
            .defaultCustomization(.hidden)
            // Grouped beside Reload at the list column's leading edge rather
            // than floating at the trailing edge: a `.primaryAction` here shares the
            // window's trailing region with the detail pane's actions, so selecting
            // a question would shove this button leftward. Anchoring it left keeps it put.
            // (#337 tried `.navigation` to reclaim the collapsed-sidebar inset, but
            // that anchors the cluster left of the title — reverted.)
            ToolbarItem(id: "new-question", placement: .automatic) {
                Button { showCreate = true } label: {
                    Label("New Question", systemImage: "plus")
                }
                .help("Create a new question (⇧⌘N)")
                .accessibilityLabel("New Question")
                .disabled(client.apiKey.isEmpty || isReadOnly)
            }
            ToolbarItem(id: "sort", placement: .automatic) {
                Menu {
                    QuestionSortMenuContent(sort: $sort)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort questions")
                .accessibilityLabel("Sort questions")
            }
            // Opt-in detail-pane toggle, hidden by default (#404).
            DetailPaneToggleToolbarContent()
        }
    }

    /// The "New Pad" swipe action's tint. macOS uses the AppKit control-accent colour
    /// (unchanged from before); iOS, which has no `controlAccentColor`, uses SwiftUI's
    /// accent colour, which resolves to the same system accent.
    private var newPadSwipeTint: Color {
        #if os(macOS)
            Color.platformAccent
        #else
            Color.accentColor
        #endif
    }

    private var questionsList: some View {
        // NSTableView-backed (#439): recycles only visible rows, so selection is
        // instant on large lists — see `FastList` and the pads list.
        FastList(sorted, selection: $selectedQuestionIDs) { question in
            QuestionRowHostableContent(
                question: question,
                isFavorite: favoriteIDSet.contains(question.id),
                onToggleFavorite: { toggleFavorite(question) }
            )
            .fastListRowManualSelection(id: question.id, selection: $selectedQuestionIDs)
        }
        .rowHeight(FastListRowMetrics.macHeight)
        .reloadID(questionListReloadID)
        .onDoubleClick { openQuestionWindow($0) }
        .onReturnKey { openQuestionWindow($0) }
        .swipeActions(edge: .leading) { question in
            let starred = favoriteIDSet.contains(question.id)
            return [SwipeAction(
                title: starred ? String(localized: "Unfavorite") : String(localized: "Favorite"),
                tint: Color(platformColor: .systemYellow),
                systemImage: starred ? "star.slash" : "star.fill"
            ) { toggleFavorite(question) }]
        }
        .swipeActions(edge: .trailing) { question in
            guard !isReadOnly else { return [] }

            return [
                // Same path as the context-menu "Delete Question…": select the row,
                // then let its detail pane run the undoable delete.
                SwipeAction(title: String(localized: "Delete"), role: .destructive,
                            systemImage: "trash") {
                    selectedQuestionIDs = [question.id]
                    nav.deleteQuestionID = question.id
                },
                SwipeAction(title: String(localized: "New Pad"), tint: newPadSwipeTint,
                            systemImage: "plus.rectangle.on.rectangle") {
                    selectedQuestionIDs = [question.id]
                    nav.createPadForQuestionID = question.id
                }
            ]
        }
        #if os(macOS)
        .onRowDrag { questionPasteboardItem($0) }
        #endif
        // iPad: drag a question's URL into Safari, Notes, or a Split View.
        .onRowDragURL { $0.webURL(baseURL: client.baseURL) }
        .rowContextMenu { questionTableMenuItems($0) }
        .onTopRowChange { scheduleTopRowPersistence($0) }
        .scrollToRow(id: pendingScrollToID) { pendingScrollToID = nil }
        #if os(macOS)
        .onDragSession(began: FavoriteDragLifecycle.onBegan, ended: FavoriteDragLifecycle.onEnded)
        #endif
        // When filters exclude every question, explain why and offer a reset rather than
        // leaving a blank list that reads like a load failure — matching the Pads list (#617).
        .overlay {
            if sorted.isEmpty, !questions.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Questions", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No questions match the current filters.")
                } actions: {
                    Button("Clear Filters") { clearAllFilters() }
                }
            }
        }
        // Scene-scoped, mirroring PadsView: the Question menu commands stay enabled
        // whenever this window is frontmost and a question is selected.
        .focusedSceneValue(\.focusedQuestion, selection)
        // Edit ▸ Copy / ⌘C copies the selected questions' web URLs (one per line).
        // `onCopyCommand` is macOS-only (Edit-menu driven); iPad has no equivalent here.
        #if os(macOS)
        .onCopyCommand(perform: copyLinkCommand(hasSelection: !selectedQuestionIDs.isEmpty) {
            selectedQuestionURLsInOrder.joined(separator: "\n")
        })
        #endif
        .macPullToRefresh { await reload() }
    }

    private var questionListReloadID: [Int] {
        favoriteIDSet.sorted()
    }

    /// Opens a question in its own window (double-click / Return), the first click
    /// having selected it.
    private func openQuestionWindow(_ question: Question) {
        openWindow(id: "question", value: QuestionWindowID(account: accounts.currentAccountID, id: question.id))
    }

    /// The drag payload for a question row: its web URL (external link drops) plus the
    /// internal `FavoriteDrop` JSON (so it drops onto the sidebar Favorites, #297).
    #if os(macOS)
    private func questionPasteboardItem(_ question: Question) -> NSPasteboardItem? {
        let url = question.webURL(baseURL: client.baseURL)
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .URL)
        item.setString(url.absoluteString, forType: .string)
        if let account = accounts.currentAccountID,
           let data = try? JSONEncoder().encode(
               FavoriteDrop.question(account: account, id: question.id, title: question.displayTitle)
           ) {
            item.setData(data, forType: NSPasteboard.PasteboardType(UTType.coderpadFavorite.identifier))
        }
        return item
    }
    #endif

    /// The selected questions' web URLs in the order they appear in the list (not
    /// the selection set's arbitrary order), so a multi-row Copy reads top to bottom.
    private var selectedQuestionURLsInOrder: [String] {
        selectedQuestionsInOrder.map { $0.webURL(baseURL: client.baseURL).absoluteString }
    }

    /// The selected questions in list order, for a multi-row Copy or Delete.
    private var selectedQuestionsInOrder: [Question] {
        sorted.filter { selectedQuestionIDs.contains($0.id) }
    }

    /// Delete several selected questions at once, looping the same per-question API
    /// path the detail view uses (delete, then broadcast so every list drops the row
    /// and the selection follows). Surfaces a failure in the alert.
    func bulkDelete(_ questions: [Question]) async {
        for question in questions {
            do {
                try await client.deleteQuestion(id: question.id)
                AppRouter.questionDeleted(id: question.id, account: accounts.currentAccountID)
            } catch {
                bulkDeleteError = error.localizedDescription
            }
        }
    }

    /// The right-click menu for a question row in the `NSTableView`-backed list, built
    /// as AppKit `MenuItem`s (the hosted content is hit-transparent, so a SwiftUI
    /// `.contextMenu` can't be used). A multi-row selection copies/deletes the whole
    /// selection, Finder-style; a single row keeps its full menu. Actions needing the
    /// detail pane's machinery select the question first, then route through
    /// `AppNavigation`. (Share is reachable from the detail pane.)
    func questionTableMenuItems(_ question: Question) -> [MenuItem] {
        if selectedQuestionIDs.count > 1, selectedQuestionIDs.contains(question.id) {
            let questions = selectedQuestionsInOrder
            return [
                .button(title: String(localized: "Copy \(questions.count) Question Links")) {
                    Clipboard.copy(questions.map { $0.webURL(baseURL: client.baseURL).absoluteString }
                        .joined(separator: "\n"))
                },
                .separator,
                .button(title: String(localized: "Delete \(questions.count) Questions…"),
                        isEnabled: !isReadOnly,
                        role: .destructive) {
                    questionsPendingBulkDelete = questions
                }
            ]
        }
        let starred = favoriteIDSet.contains(question.id)
        var items: [MenuItem] = [
            .button(title: String(localized: "New Pad from Question"), isEnabled: !isReadOnly) {
                selectedQuestionIDs = [question.id]
                nav.createPadForQuestionID = question.id
            },
            .button(title: starred ? String(localized: "Remove from Favorites")
                : String(localized: "Add to Favorites")) {
                    toggleFavorite(question)
                },
            .separator,
            .button(title: String(localized: "Copy Title")) { Clipboard.copy(question.displayTitle) },
            .button(title: String(localized: "Copy Question URL")) {
                Clipboard.copy(question.webURL(baseURL: client.baseURL).absoluteString)
            },
            .button(title: String(localized: "Show Questions from \(directory.display(question.ownerEmail))")) {
                ownerFilter = question.ownerEmail
            }
        ]
        if let lang = question.language, !lang.isEmpty {
            items.append(.button(title: String(localized: "Show \(lang.coderPadLanguageDisplayName) Questions")) {
                languageFilter = lang.lowercased()
            })
        }
        items.append(.separator)
        items.append(.button(title: String(localized: "Delete Question…"),
                             isEnabled: !isReadOnly,
                             role: .destructive) {
                selectedQuestionIDs = [question.id]
                nav.deleteQuestionID = question.id
            })
        return items
    }

    func toggleFavorite(_ question: Question) {
        guard let account = accounts.currentAccountID else { return }

        favorites.toggle(question.id, title: question.displayTitle, account: account)
        // Unstarring the last favorite hides the Favorites chip, so drop the
        // filter too — otherwise it would strand the list on an empty result with
        // no visible control to turn it back off.
        if favoritesOnly, favoriteIDSet.isEmpty {
            favoritesOnly = false
        }
    }
}
