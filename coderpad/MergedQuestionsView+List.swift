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
            .onAppear { selectedQuestionID = selection?.id }
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
            .onChange(of: selectedQuestionID) { _, newID in
                if selection?.id != newID {
                    selection = newID.flatMap { id in question(forID: id) }
                }
            }
            .onChange(of: selection) { _, newValue in
                if selectedQuestionID != newValue?.id { selectedQuestionID = newValue?.id }
            }
            .task {
                for await question in NotificationCenter.default.notifications(named: .questionUpdated)
                    .compactMap({ $0.object as? Question }) {
                    applyUpdated(question)
                }
            }
            .task {
                for await id in NotificationCenter.default.notifications(named: .questionDeleted)
                    .compactMap({ $0.object as? Int }) {
                    // Move to a neighbor before dropping the row so deleting the
                    // open question keeps the detail pane populated, matching pads.
                    if selection?.id == id { selection = neighborSelection(forDeletedQuestion: id) }
                    removeQuestion(id: id)
                }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: .reloadRequested) {
                    await reload()
                }
            }
            .sheet(item: $creatingForAccount) { account in
                NewQuestionSheet(client: account.makeClient()) { created in
                    insert(created, into: account)
                    selection = created
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
                    PaneTitle(title: "Questions")
                    presetsBar
                    filterBar
                    resultCountBar
                    errorBar
                    Divider()
                    questionsList
                }
            }
        }
        .toolbar(id: "questions.toolbar") { questionsToolbar }
    }

    @ToolbarContentBuilder
    var questionsToolbar: some CustomizableToolbarContent {
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
        ToolbarItem(id: "reload") {
            ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
        }
        ToolbarItem(id: "new", placement: .primaryAction) {
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
    }

    private var questionsList: some View {
        List(selection: $selectedQuestionID) {
            ForEach(sorted) { row in
                QuestionRow(
                    question: row.item,
                    isFavorite: isFavorite(row),
                    accountName: row.account.name,
                    onToggleFavorite: { toggleFavorite(row) }
                )
                .tag(row.item.id)
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
        .overlay { questionsOverlay }
        .macPullToRefresh { await reload() }
        .focusedSceneValue(\.focusedQuestion, selection)
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
            selection = row.item
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
            selection = row.item
            nav.editQuestionID = row.item.id
        } label: {
            Label("Edit Question…", systemImage: "pencil")
        }
        Divider()
        Button { copyToPasteboard(row.item.displayTitle) } label: {
            Label("Copy Title", systemImage: "doc.on.doc")
        }
        Button { accountFilter = row.account.id } label: {
            Label("Show Only \(row.account.name)", systemImage: "person.crop.circle")
        }
        Divider()
        Button(role: .destructive) {
            selection = row.item
            nav.deleteQuestionID = row.item.id
        } label: {
            Label("Delete Question…", systemImage: "trash")
        }
    }
}
