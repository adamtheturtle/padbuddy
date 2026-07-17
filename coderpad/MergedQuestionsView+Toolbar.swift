//
//  MergedQuestionsView+Toolbar.swift
//  coderpad
//
//  Split from MergedQuestionsView+List.swift to keep it within the lint length
//  limit: the window toolbar for the combined questions list moved here.
//

import SwiftUI

extension MergedQuestionsView {
    @ToolbarContentBuilder
    var questionsToolbar: some CustomizableToolbarContent {
        #if os(iOS)
            ToolbarItem(id: "questions-actions", placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(accounts.mergeableAccounts) { account in
                            Button(account.name) { creatingForAccount = account }
                                .disabled(account.apiKey.isEmpty)
                        }
                    } label: {
                        Label("New Question", systemImage: "plus")
                    }
                    .disabled(isReadOnly)
                    .help("Create a new question in one of your accounts")
                    .accessibilityLabel("New Question")

                    Menu {
                        Button {
                            clearAllFilters()
                        } label: {
                            Label("All Questions", systemImage: hasActiveFilters ? "tray" : "checkmark")
                        }

                        Button {
                            mineOnly = true
                            favoritesOnly = false
                        } label: {
                            Label("My Questions", systemImage: mineOnly ? "checkmark" : "person.fill.questionmark")
                        }

                        Button {
                            draftFilter = "draft"
                            favoritesOnly = false
                        } label: {
                            Label("Drafts", systemImage: draftFilter == "draft" ? "checkmark" : "doc.badge.ellipsis")
                        }
                    } label: {
                        Label("Suggestions", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .help("Apply a suggested question filter")
                    .accessibilityLabel("Suggested question filters")

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
            }
        #else
            // Hidden by default — reachable via View ▸ Customize Toolbar…, the
            // File ▸ Reload command (⌘R), or pull-to-refresh (#413).
            ToolbarItem(id: "reload", placement: .automatic) {
                ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
            }
            .defaultCustomization(.hidden)
            // Grouped beside Reload at the list column's leading edge rather than
            // floating at the trailing edge: a `.primaryAction` here shares the window's
            // trailing region with the detail pane's actions, so selecting a question
            // would shove this button leftward. Anchoring it left keeps it put.
            ToolbarItem(id: "new-question", placement: .automatic) {
                Menu {
                    ForEach(accounts.mergeableAccounts) { account in
                        Button(account.name) { creatingForAccount = account }
                            .disabled(account.apiKey.isEmpty)
                    }
                } label: {
                    Label("New Question", systemImage: "plus")
                }
                .disabled(isReadOnly)
                .help("Create a new question in one of your accounts")
                .accessibilityLabel("New Question")
            }
            ToolbarItem(id: "sort", placement: .automatic) {
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
            // Opt-in detail-pane toggle, hidden by default (#404).
            DetailPaneToggleToolbarContent()
        #endif
    }
}
