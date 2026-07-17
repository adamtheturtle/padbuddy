//
//  MergedPadsView+Toolbar.swift
//  coderpad
//
//  Split from MergedPadsView+List.swift to keep it within the lint length limit:
//  the window toolbar for the combined pads list moved here.
//

import SwiftUI

extension MergedPadsView {
    /// The account a deep-link New Pad targets in merged mode: the current account
    /// when its key is usable, else the first mergeable account that has a key. Nil
    /// only when no account has a key, in which case the request is a no-op.
    var newPadDefaultAccount: Account? {
        if let current = accounts.currentAccount, !current.apiKey.isEmpty { return current }
        return accounts.mergeableAccounts.first { !$0.apiKey.isEmpty }
    }

    @ToolbarContentBuilder
    var padsToolbar: some CustomizableToolbarContent {
        #if os(iOS)
            ToolbarItem(id: "pads-actions", placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(accounts.mergeableAccounts) { account in
                            Button(account.name) { creatingForAccount = account }
                                .disabled(account.apiKey.isEmpty)
                        }
                    } label: {
                        Label("New Pad", systemImage: "plus")
                    }
                    .disabled(isReadOnly)
                    .help("Create a new pad in one of your accounts")
                    .accessibilityLabel("New Pad")

                    Menu {
                        Button {
                            clearAllFilters()
                        } label: {
                            Label("All Pads", systemImage: hasActiveFilters ? "tray" : "checkmark")
                        }

                        Button {
                            mineOnly = true
                        } label: {
                            Label("My Pads", systemImage: mineOnly ? "checkmark" : "person.fill")
                        }

                        Button {
                            stateFilter = .active
                        } label: {
                            Label("Active Pads", systemImage: stateFilter == .active ? "checkmark" : "bolt.fill")
                        }
                    } label: {
                        Label("Suggestions", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .help("Apply a suggested pad filter")
                    .accessibilityLabel("Suggested pad filters")

                    Menu {
                        PadSortMenuContent(sort: $sort)
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .help("Sort pads")
                    .accessibilityLabel("Sort pads")
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
            // trailing region with the detail pane's actions, so selecting a pad would
            // shove this button leftward. Anchoring it left keeps it put.
            ToolbarItem(id: "new-pad", placement: .automatic) {
                Menu {
                    ForEach(accounts.mergeableAccounts) { account in
                        Button(account.name) { creatingForAccount = account }
                            .disabled(account.apiKey.isEmpty)
                    }
                } label: {
                    Label("New Pad", systemImage: "plus")
                }
                .disabled(isReadOnly)
                .help("Create a new pad in one of your accounts")
                .accessibilityLabel("New Pad")
            }
            ToolbarItem(id: "sort", placement: .automatic) {
                Menu {
                    PadSortMenuContent(sort: $sort)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort pads")
                .accessibilityLabel("Sort pads")
            }
            // Opt-in detail-pane toggle, hidden by default (#404).
            DetailPaneToggleToolbarContent()
        #endif
    }
}
