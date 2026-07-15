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

    /// How many questions the current filters resolve to, shown as the window's
    /// toolbar subtitle beneath the "Questions" title. Empty when the org has no
    /// questions at all, where a "0 questions" line would just restate the empty list.
    var countSubtitle: String {
        guard !questions.isEmpty else { return "" }

        let count = sorted.count
        return count == 1 ? String(localized: "\(count) question") : String(localized: "\(count) questions")
    }

    var sidebar: some View {
        FilterableListView(
            isLoading: isLoading && !questions.isEmpty,
            isEmpty: questions.isEmpty && !isLoading,
            error: error,
            loadingMessage: "",
            onReload: { await reload() },
            errorView: { error, retry in APIErrorView(error: error, onRetry: retry) },
            savedSearches: { EmptyView() },
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
            #if os(iOS)
                ToolbarItem(id: "questions-actions", placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Button { showCreate = true } label: {
                            Label("New Question", systemImage: "plus")
                        }
                        .help("Create a new question (⇧⌘N)")
                        .accessibilityLabel("New Question")
                        .disabled(client.apiKey.isEmpty || isReadOnly)

                        Menu {
                            Button {
                                clearAllFilters()
                            } label: {
                                Label("All Questions", systemImage: hasActiveFilters ? "tray" : "checkmark")
                            }

                            ForEach(DefaultSearch.questionDefaults(me: accounts.currentAccount?.userEmail)) { item in
                                Button {
                                    apply(item.search)
                                } label: {
                                    Label(item.search.name, systemImage: isActiveSearch(item.search) ? "checkmark" : item.icon)
                                }
                            }
                        } label: {
                            Label("Suggestions", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .help("Apply a suggested question filter")
                        .accessibilityLabel("Suggested question filters")

                        Menu {
                            QuestionSortMenuContent(sort: $sort)
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                        .help("Sort questions")
                        .accessibilityLabel("Sort questions")
                    }
                }
            #else
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
            #endif
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
        #if os(macOS)
            MacQuestionTable(
                items: sorted,
                selection: $selectedQuestionIDs,
                reloadID: questionListReloadID,
                scrollToID: pendingScrollToID,
                onScrolledToID: { pendingScrollToID = nil },
                presentation: { question in
                    listCache.rowPresentations[question.id] ?? QuestionRowPresentation(question: question, account: nil)
                },
                rowAccount: { _ in nil },
                isFavorite: { favoriteIDSet.contains($0.id) },
                toggleFavorite: { toggleFavorite($0) },
                onDoubleClick: { openQuestionWindow($0) },
                onReturn: { openQuestionWindow($0) },
                leadingActions: { question in
                    let starred = favoriteIDSet.contains(question.id)
                    return [SwipeAction(
                        title: starred ? String(localized: "Unfavorite") : String(localized: "Favorite"),
                        tint: Color(platformColor: .systemYellow),
                        systemImage: starred ? "star.slash" : "star.fill"
                    ) { toggleFavorite(question) }]
                },
                trailingActions: { question in
                    guard !isReadOnly else { return [] }

                    return [
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
                },
                pasteboardItem: { questionPasteboardItem($0) },
                menuItems: { questionTableMenuItems($0) },
                onTopRowChange: { scheduleTopRowPersistence($0) }
            )
            .overlay {
                if sorted.isEmpty, !questions.isEmpty {
                    ContentUnavailableView {
                        Label("No Matching Questions", systemImage: "line.3.horizontal.decrease.circle")
                    } actions: {
                        Button("Clear Filters") { clearAllFilters() }
                    }
                }
            }
            .focusedSceneValue(\.focusedQuestion, selection)
            .onCopyCommand(perform: copyLinkCommand(hasSelection: !selectedQuestionIDs.isEmpty) {
                selectedQuestionURLsInOrder.joined(separator: "\n")
            })
            .macPullToRefresh { await reload() }
        #else
            FastList(sorted, selection: $selectedQuestionIDs) { question in
                QuestionRowHostableContent(
                    question: question,
                    presentation: listCache.rowPresentations[question.id],
                    isFavorite: favoriteIDSet.contains(question.id),
                    onToggleFavorite: { toggleFavorite(question) }
                )
                .fastListRowManualSelection(id: question.id, selection: $selectedQuestionIDs)
                .favoriteDraggable(questionFavoritePayload(question), title: question.displayTitle)
                .favoriteRowContextMenu(questionTableMenuItems(question), title: question.displayTitle)
            }
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
            .onTopRowChange { scheduleTopRowPersistence($0) }
            .scrollToRow(id: pendingScrollToID) { pendingScrollToID = nil }
            .overlay {
                if sorted.isEmpty, !questions.isEmpty {
                    ContentUnavailableView {
                        Label("No Matching Questions", systemImage: "line.3.horizontal.decrease.circle")
                    } actions: {
                        Button("Clear Filters") { clearAllFilters() }
                    }
                }
            }
            .focusedSceneValue(\.focusedQuestion, selection)
            .macPullToRefresh { await reload() }
        #endif
    }

    private var questionListReloadID: [Int] {
        favoriteIDSet.sorted()
    }

    /// Opens a question in its own window (double-click / Return), the first click
    /// having selected it.
    private func openQuestionWindow(_ question: Question) {
        openWindow(id: "question", value: QuestionWindowID(account: accounts.currentAccountID, id: question.id))
    }

    /// The iPad drag payload for a question row: the internal `FavoriteDrop` (so it can
    /// be dropped on the sidebar Favorites to pin it, #297) plus the web URL (so external
    /// drops still receive a link). `nil` — non-draggable — when there's no current
    /// account, mirroring `questionPasteboardItem` on macOS.
    func questionFavoritePayload(_ question: Question) -> FavoriteDragPayload? {
        guard let account = accounts.currentAccountID else { return nil }

        return FavoriteDragPayload(
            drop: .question(account: account, id: question.id, title: question.displayTitle),
            url: question.webURL(baseURL: client.baseURL)
        )
    }

    // The drag payload for a question row: its web URL (external link drops) plus the
    // internal `FavoriteDrop` JSON (so it drops onto the sidebar Favorites, #297).
    #if os(macOS)
        private func questionPasteboardItem(_ question: Question) -> NSPasteboardItem? {
            if selectedQuestionIDs.count > 1, selectedQuestionIDs.contains(question.id) {
                return multiLinkPasteboardItem(selectedQuestionURLsInOrder)
            }

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

        favorites.toggle(question.id, title: question.displayTitle, account: account, undoManager: undoManager)
        // Unstarring the last favorite hides the Favorites chip, so drop the
        // filter too — otherwise it would strand the list on an empty result with
        // no visible control to turn it back off.
        if favoritesOnly, favoriteIDSet.isEmpty {
            favoritesOnly = false
        }
    }
}
