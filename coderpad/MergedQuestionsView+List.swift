//
//  MergedQuestionsView+List.swift
//  coderpad
//
//  The view body, list, rows, and lifecycle modifiers for the combined questions
//  list. Kept out of the primary struct so its body-length stays small.
//

import AppKit
import SwiftUI

extension MergedQuestionsView {
    var decorated: some View {
        content
            .task(id: QuestionsTaskKey(apiKey: accountKey, phase: scenePhase)) {
                guard scenePhase == .active else { return }
                seedFromCache()
                await periodicReload(interval: { GeneralSettings.refreshInterval }, work: {
                    await reload()
                })
            }
            .onAppear {
                selectedRowID = selection.flatMap { sel in scoped.first { $0.item.id == sel.id }?.id }
            }
            // Keep the sidebar's "My Questions" row in sync with this list's "Mine"
            // preset: publish the live state and consume any sidebar toggle, the
            // same bridge `MergedPadsView` uses for "My Pads".
            .onChange(of: mineOnly, initial: true) { _, isOn in
                if nav.mergedQuestionsMineOnly != isOn { nav.mergedQuestionsMineOnly = isOn }
            }
            .onChange(of: nav.mergedQuestionsMineRequest, initial: true) { _, request in
                guard let request else { return }
                nav.mergedQuestionsMineRequest = nil
                if mineOnly != request { mineOnly = request }
            }
            .onChange(of: selectedRowID) { _, newID in selectRow(newID) }
            .task {
                for await update in AppRouter.questionUpdates {
                    applyUpdated(update.question, account: update.account)
                }
            }
            .task {
                for await deletion in AppRouter.questionDeletions {
                    let id = deletion.id
                    let account = deletion.account
                    // If the open (selected) row is the deleted question — matched by
                    // account too, since per-org ids collide — move to a neighbor
                    // before dropping the row. Computed while `sorted` still holds it.
                    if let current = selectedRowID, let selected = row(forRowID: current),
                       selected.item.id == id, account == nil || selected.account.id == account {
                        selectedRowID = neighborRowID(forDeletedRowID: current)
                    }
                    removeQuestion(id: id, account: account)
                    // Keep the disk cache and Spotlight index in step.
                    cache.removeQuestion(id: id, account: account)
                }
            }
            .task {
                for await _ in AppRouter.reloads {
                    await reload()
                }
            }
            .sheet(item: $creatingForAccount) { account in
                NewQuestionSheet(client: account.makeClient()) { created in
                    insert(created, into: account)
                    select(AccountScoped(account: account, item: created,
                                         id: MergedQuestionsView.rowID(account: account.id, question: created.id)))
                    creatingForAccount = nil
                } onCancel: {
                    creatingForAccount = nil
                }
            }
    }

    var content: some View {
        Group {
            if isLoading, scoped.isEmpty {
                ProgressView("Loading questions…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    presetsBar
                    filterBar
                    errorBar
                    Divider()
                    questionsList
                }
            }
        }
        // Surface the count beneath the "Questions" title in the window toolbar
        // rather than as an inline bar above the list.
        .reportsSectionCount(countSubtitle)
        .toolbar(id: "questions.toolbar") { questionsToolbar }
    }

    @ToolbarContentBuilder
    var questionsToolbar: some CustomizableToolbarContent {
        ToolbarItem(id: "reload") {
            ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
        }
        // Grouped beside Reload at the list column's leading edge rather than
        // floating at the trailing edge: a `.primaryAction` here shares the window's
        // trailing region with the detail pane's actions, so selecting a question
        // would shove this button leftward. Anchoring it left keeps it put.
        ToolbarItem(id: "new") {
            Menu {
                ForEach(accounts.mergeableAccounts) { account in
                    Button(account.name) { creatingForAccount = account }
                        .disabled(account.apiKey.isEmpty)
                }
            } label: {
                Label("New Question", systemImage: "plus")
            }
            .help("Create a new question in one of your accounts")
            .accessibilityLabel("New Question")
        }
        ToolbarItem(id: "sort") {
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(QuestionSort.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort questions")
            .accessibilityLabel("Sort questions")
        }
        // List vs. Table presentation, sharing the single-account list's preference
        // key so the choice is consistent across both question lists.
        ToolbarItem(id: "viewMode") {
            Picker("View", selection: $presentation) {
                ForEach(QuestionListPresentation.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Show the questions as a list or a sortable table")
            .accessibilityLabel("List or table view")
        }
    }

    /// The questions presentation: either the inset List or the sortable Table, with
    /// the shared empty-state overlay, pull-to-refresh, and focused-question command
    /// target around both.
    private var questionsList: some View {
        Group {
            if presentation == .table {
                questionsTable
            } else {
                questionsListView
            }
        }
        .overlay { questionsOverlay }
        .macPullToRefresh { await reload() }
        .focusedSceneValue(\.focusedQuestion, selection)
    }

    private var questionsListView: some View {
        List(selection: $selectedRowID) {
            ForEach(sorted) { row in
                QuestionRow(
                    question: row.item,
                    isFavorite: isFavorite(row),
                    accountName: row.account.name,
                    onToggleFavorite: { toggleFavorite(row) }
                )
                .tag(row.id)
                .contextMenu { questionContextMenu(row) }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        toggleFavorite(row)
                    } label: {
                        Label(isFavorite(row) ? "Unfavorite" : "Favorite",
                              systemImage: isFavorite(row) ? "star.slash" : "star")
                    }
                    .tint(.yellow)
                }
            }
        }
        .listStyle(.inset)
        .id("\(filterSignature)|\(favoritesOnly)|\(sort.rawValue)")
        .transaction { $0.animation = nil }
    }

    /// A sortable, resizable Table alternative to the List, shown when the view-mode
    /// toggle selects Table. Adds an Account column (this is the combined list);
    /// clicking a header sorts and columns resize/reorder natively. Rows are
    /// `AccountScoped<Question>` whose `id` is the namespaced row id, so selection
    /// reuses `selectedRowID` exactly as the List does.
    private var questionsTable: some View {
        Table(sorted.sorted(using: sortOrder), selection: $selectedRowID, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.item.displayTitle) { row in
                Text(row.item.displayTitle).lineLimit(1)
            }
            TableColumn("Account", value: \.account.name) { row in
                Text(row.account.name).lineLimit(1)
            }
            TableColumn("Language", value: \.item.languageSortKey) { row in
                Text(row.item.language?.languageDisplayName ?? "—")
            }
            TableColumn("Owner", value: \.item.ownerEmail) { row in
                Text(directory.display(row.item.ownerEmail)).lineLimit(1)
            }
            TableColumn("Used", value: \.item.usedSortKey) { row in
                Text(row.item.used.map(String.init) ?? "—")
            }
            TableColumn("Last used", value: \.item.updatedSortKey) { row in
                Text(row.item.updatedAt.map { $0.formatted(date: .long, time: .shortened) } ?? "—")
            }
        }
        .contextMenu(forSelectionType: AccountScoped<Question>.ID.self) { ids in
            if let id = ids.first, let row = sorted.first(where: { $0.id == id }) {
                questionContextMenu(row)
            }
        }
    }

    @ViewBuilder
    private var questionsOverlay: some View {
        if sorted.isEmpty, !scoped.isEmpty {
            ContentUnavailableView {
                Label("No Matching Questions", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No questions match the current filters.")
            } actions: {
                Button("Clear Filters") { clearAllFilters() }
            }
        } else if scoped.isEmpty, !isLoading {
            ContentUnavailableView("No Questions", systemImage: "questionmark.bubble")
        }
    }

    @ViewBuilder
    private func questionContextMenu(_ row: AccountScoped<Question>) -> some View {
        Button {
            select(row)
            nav.createPadForQuestionID = row.item.id
        } label: {
            Label("New Pad from Question", systemImage: "plus.rectangle.on.rectangle")
        }
        Button {
            toggleFavorite(row)
        } label: {
            Label(isFavorite(row) ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: isFavorite(row) ? "star.slash" : "star")
        }
        Button {
            select(row)
            nav.editQuestionID = row.item.id
        } label: {
            Label("Edit Question…", systemImage: "pencil")
        }
        ShareLink(item: row.item.webURL(baseURL: row.account.resolvedBaseURL)) {
            Label("Share…", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button { copyToPasteboard(row.item.displayTitle) } label: {
            Label("Copy Title", systemImage: "doc.on.doc")
        }
        Button { copyToPasteboard(row.item.webURL(baseURL: row.account.resolvedBaseURL).absoluteString) } label: {
            Label("Copy Question URL", systemImage: "link")
        }
        Button { accountFilter = row.account.id } label: {
            Label("Show Only \(row.account.name)", systemImage: "person.crop.circle")
        }
        Divider()
        Button(role: .destructive) {
            select(row)
            nav.deleteQuestionID = row.item.id
        } label: {
            Label("Delete Question…", systemImage: "trash")
        }
    }
}
