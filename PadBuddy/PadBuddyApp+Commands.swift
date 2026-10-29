#if os(macOS)
//
    //  coderpadApp+Commands.swift
    //  coderpad
//

    import AppKit
    import SwiftUI

    /// Wires ⌘F to the search field of whichever pane is on screen. The pane
    /// publishes a `findAction`; here we surface it as a standard Find menu item in
    /// the Edit menu, disabled in sections (like Quota) that have nothing to search.
    struct FindCommands: Commands {
        @FocusedValue(\.findAction) private var findAction

        var body: some Commands {
            CommandGroup(after: .textEditing) {
                Button("Find") { findAction?.perform() }
                    .keyboardShortcut("f", modifiers: [.command])
                    .disabled(findAction == nil)
            }
        }
    }

    /// Wires ⌘P to the print-friendly rendering of whichever detail pane is on
    /// screen. The pane publishes a `printAction`; here it surfaces as the standard
    /// File ▸ Print item, disabled in sections (lists, Quota) that publish nothing
    /// printable. "Save as PDF" comes free from the print panel it opens.
    struct PrintCommands: Commands {
        @FocusedValue(\.printAction) private var printAction
        @FocusedValue(\.exportMarkdownAction) private var exportMarkdownAction

        var body: some Commands {
            CommandGroup(replacing: .printItem) {
                Button("Print…") { printAction?.perform() }
                    .keyboardShortcut("p", modifiers: [.command])
                    .disabled(printAction == nil)

                // "Save as PDF" comes free from the print panel; this adds the Markdown half
                // of #524. ⇧⌘E, the common "export" shortcut, with no system conflict here.
                Button("Export as Markdown…") { exportMarkdownAction?.perform() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(exportMarkdownAction == nil)
            }
        }
    }

    /// Adds a "Stats Period" submenu to the View menu, mirroring the Organization
    /// view's toolbar Period picker as a menu command. "Show/Hide Toolbar" and
    /// "Customize Toolbar…" themselves come from SwiftUI's `ToolbarCommands()`
    /// (wired up in the scene), so no AppKit bridge is needed for them.
    struct ViewCommands: Commands {
        @FocusedValue(\.statsPeriodSelection) private var statsPeriodSelection
        /// Published by the main split (#396); flips the sidebar through the same
        /// `columnVisibility` state the toolbar toggle drives. Nil when the main window
        /// isn't frontmost, which disables the item.
        @FocusedValue(\.sidebarToggleAction) private var sidebarToggle

        var body: some Commands {
            CommandGroup(after: .toolbar) {
                Button(sidebarToggle?.collapsed == true
                    ? String(localized: "Show Sidebar")
                    : String(localized: "Hide Sidebar")) {
                        sidebarToggle?.perform()
                    }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                    .disabled(sidebarToggle == nil)

                // Inline rather than a nested `Menu`: the picker follows the focused
                // window, and as a submenu AppKit re-indexed it
                // mid-insert of an adjacent auto-separator and logged a benign but noisy
                // "didChangeSubmenu: …wrong item" warning (#407). An inline picker has no
                // submenu to re-index, so the warning can't fire; its label renders as a
                // "Stats Period" section header in the View menu.
                Picker("Stats Period", selection: statsPeriodSelection ?? .constant(.days7)) {
                    ForEach(StatsPeriod.allCases) { Text($0.displayLabel).tag($0) }
                }
                .pickerStyle(.inline)
                .disabled(statsPeriodSelection == nil)
            }
        }
    }

    /// Top-level "Pad" menu: every action for the pad selected in the frontmost
    /// window (published as `focusedPad`). Open and copy act directly; Edit, End
    /// Interview, and Delete route through `AppNavigation` so the mounted
    /// `PadDetailView` runs them with its existing sheet and confirmations — the same
    /// pattern the Questions side uses — rather than duplicating that machinery here.
    ///
    /// Several shortcuts (⌘↩ primary action, ⌘E edit, ⇧⌘C copy id, ⌘⌫ delete) are
    /// shared with the Question menu. Only one of `focusedPad`/`focusedQuestion` is
    /// ever set — the visible section publishes one and the other reverts to nil — so
    /// at any moment exactly one menu's item is enabled and the shortcut is
    /// unambiguous, while the muscle memory carries across both sections.
    struct PadCommands: Commands {
        @State private var accounts = AccountsStore.shared
        @FocusedValue(\.focusedPad) private var pad
        @FocusedValue(\.focusedPadAccountID) private var padAccountID
        @FocusedValue(\.focusedPadFavoriteState) private var favoriteState
        /// Mirrors the window's read-only state (offline) so the mutating items disable
        /// to match the in-window controls (#321). `nil`/`false` means editable.
        @FocusedValue(\.isReadOnly) private var isReadOnly
        /// Whether the focused pad has any code to save yet, so "Save All Code…" disables
        /// until its environments (or legacy inline contents) have loaded. `nil` when
        /// no pad detail is frontmost.
        @FocusedValue(\.padHasSavableCode) private var padHasSavableCode
        @FocusedValue(\.padSortSelection) private var sortSelection
        /// Mirrors `PadDetailView.isEnded`, so "End Interview" disables once the pad
        /// is already ended instead of routing a no-op confirmation.
        private var isEnded: Bool {
            guard let pad else { return false }

            return pad.isEnded
        }

        private var isFavorite: Bool? {
            guard let pad else { return nil }

            return favoriteState?.value(for: pad.id, accountID: padAccountID)
        }

        private var canonicalURL: URL? {
            guard let pad, let padAccountID else { return nil }

            let owners = accounts.accounts.filter { $0.id == padAccountID }
            guard owners.count == 1, let owner = owners.first else { return nil }

            return pad.webURL(fallbackBase: owner.resolvedBaseURL)
        }

        private var playbackURL: URL? {
            guard let pad, let padAccountID else { return nil }

            let owners = accounts.accounts.filter { $0.id == padAccountID }
            guard owners.count == 1, let owner = owners.first else { return nil }

            return pad.playbackURL(fallbackBase: owner.resolvedBaseURL)
        }

        var body: some Commands {
            CommandMenu("Pad") {
                Button("Open Pad in Browser") {
                    guard let url = canonicalURL else { return }

                    BrowserSettings.openExternally(url)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(canonicalURL == nil)

                Button("Watch Playback") {
                    guard let pad else { return }

                    AppNavigation.shared.watchPlaybackPadID = .init(id: pad.id, account: padAccountID)
                }
                .keyboardShortcut("y", modifiers: [.command])
                .disabled(playbackURL == nil)

                Divider()

                Button("Edit Pad…") {
                    guard let pad else { return }

                    AppNavigation.shared.editPadID = .init(id: pad.id, account: padAccountID)
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(pad == nil || isReadOnly == true)

                Button(isFavorite == true
                    ? String(localized: "Remove from Favorites")
                    : String(localized: "Add to Favorites")) {
                        guard let pad else { return }

                        AppNavigation.shared.toggleFavoritePadID = .init(id: pad.id, account: padAccountID)
                    }
                    .keyboardShortcut("d", modifiers: [.command])
                    .disabled(pad == nil || isFavorite == nil)

                Menu("Sort By") {
                    PadSortMenuContent(sort: sortSelection ?? .constant(.updatedDesc))
                }
                .disabled(sortSelection == nil)

                Divider()

                Button("Copy Pad ID") {
                    guard let pad else { return }

                    Clipboard.copy(pad.id)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(pad == nil)

                Button("Copy Pad URL") {
                    guard let url = canonicalURL else { return }

                    Clipboard.copy(url.absoluteString)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(canonicalURL == nil)

                Button("Copy Pad Title") {
                    guard let pad else { return }

                    Clipboard.copy(pad.title.isEmpty ? pad.id : pad.title)
                }
                .disabled(pad == nil)

                Button("Copy as Markdown") {
                    guard let pad else { return }

                    let title = pad.title.isEmpty ? pad.id : pad.title
                    Clipboard.copy("[\(title)](\(pad.url))")
                }
                .disabled(pad == nil)

                // A live `ShareLink` rather than a routed command: it must hand the
                // system share picker a concrete URL at build time, and the pad's
                // canonical URL is available right here. Falls back to a disabled button
                // (so the item still appears) when no pad is selected.
                if let url = canonicalURL {
                    ShareLink("Share Pad…", item: url)
                } else {
                    Button("Share Pad…") {}.disabled(true)
                }

                Divider()

                Button("Save All Code…") {
                    guard let pad else { return }

                    AppNavigation.shared.saveCodePadID = .init(id: pad.id, account: padAccountID)
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(pad == nil || padHasSavableCode != true)

                Divider()

                Button("End Interview…") {
                    guard let pad else { return }

                    AppNavigation.shared.endPadID = .init(id: pad.id, account: padAccountID)
                }
                .disabled(pad == nil || isEnded || isReadOnly == true)

                Button("Delete Pad…") {
                    guard let pad else { return }

                    AppNavigation.shared.deletePadID = .init(id: pad.id, account: padAccountID)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(pad == nil || isReadOnly == true)
            }
        }
    }

    /// Top-level "Question" menu: the Questions-pane counterpart to `PadCommands`,
    /// acting on the question selected in the frontmost window (`focusedQuestion`).
    /// New Pad / Edit / Delete route through `AppNavigation` so the mounted
    /// `QuestionDetailView` performs them with its existing inline editor and
    /// delete confirmation — the same path the Questions list's context menu uses.
    ///
    /// `⌘↩` mirrors the Pad menu's primary action: with a pad selected it opens the
    /// pad, with a question selected it creates a pad from that question — each the
    /// headline action of the corresponding detail view. See `PadCommands` for why
    /// sharing shortcuts across the two menus is unambiguous.
    struct QuestionCommands: Commands {
        @FocusedValue(\.focusedQuestion) private var question
        @FocusedValue(\.focusedQuestionAccountID) private var questionAccountID
        @FocusedValue(\.focusedQuestionFavoriteState) private var favoriteState
        @FocusedValue(\.focusedQuestionLink) private var questionLink
        /// Mirrors the window's read-only state (offline) so the mutating items disable
        /// to match the in-window controls (#321). `nil`/`false` means editable.
        @FocusedValue(\.isReadOnly) private var isReadOnly
        @FocusedValue(\.questionSortSelection) private var sortSelection

        private var isFavorite: Bool? {
            guard let question else { return nil }

            return favoriteState?.value(for: question.id, accountID: questionAccountID)
        }

        private var questionURL: URL? {
            guard let question else { return nil }

            return questionLink?.value(for: question.id, accountID: questionAccountID)
        }

        var body: some Commands {
            CommandMenu("Question") {
                Button("Open Question in Browser") {
                    guard let questionURL else { return }

                    BrowserSettings.openExternally(questionURL)
                }
                .disabled(questionURL == nil)

                Button("New Pad from Question") {
                    guard let question else { return }

                    AppNavigation.shared.createPadForQuestionID = .init(id: question.id, account: questionAccountID)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(question == nil || isReadOnly == true)

                Divider()

                Button("Edit Question…") {
                    guard let question else { return }

                    AppNavigation.shared.editQuestionID = .init(id: question.id, account: questionAccountID)
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(question == nil || isReadOnly == true)

                Button(isFavorite == true
                    ? String(localized: "Remove from Favorites")
                    : String(localized: "Add to Favorites")) {
                        guard let question else { return }

                        AppNavigation.shared.toggleFavoriteQuestionID = .init(
                            id: question.id,
                            account: questionAccountID
                        )
                    }
                    .keyboardShortcut("d", modifiers: [.command])
                    .disabled(question == nil || isFavorite == nil)

                Menu("Sort By") {
                    QuestionSortMenuContent(sort: sortSelection ?? .constant(.lastUsedDesc))
                }
                .disabled(sortSelection == nil)

                Divider()

                Button("Copy Question ID") {
                    guard let question else { return }

                    Clipboard.copy(String(question.id))
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(question == nil)

                Button("Copy Question URL") {
                    guard let questionURL else { return }

                    Clipboard.copy(questionURL.absoluteString)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(questionURL == nil)

                Button("Copy Question Title") {
                    guard let question else { return }

                    Clipboard.copy(question.displayTitle)
                }
                .disabled(question == nil)

                // A live `ShareLink` rather than a routed command, mirroring the Pad
                // menu: it needs a concrete URL at build time, published here as
                // the focused question link. Falls back to a disabled button (so the item
                // still appears) when no question is selected.
                if let questionURL {
                    ShareLink("Share Question…", item: questionURL)
                } else {
                    Button("Share Question…") {}.disabled(true)
                }

                Divider()

                Button("Delete Question…") {
                    guard let question else { return }

                    AppNavigation.shared.deleteQuestionID = .init(id: question.id, account: questionAccountID)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(question == nil || isReadOnly == true)
            }
        }
    }

    // ScreenCommands and WindowCommands live in coderpadApp+Commands+Screen.swift
    // (split out for file length).
#endif
