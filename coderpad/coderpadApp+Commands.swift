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
    /// Shares the Organization view's persisted period key, mirroring its toolbar
    /// Period picker as a menu command.
    @AppStorage(StatsPeriod.storageKey) private var statsPeriod: StatsPeriod = .days7
    /// Shares the main split's detail-pane visibility (#394), so this menu item and the
    /// layout stay in lockstep. Toggling it lets Pads/Questions drop the third column so
    /// the window can be made very thin — just the sidebar and the list.
    @AppStorage(MainSplit.detailPaneHiddenKey) private var detailPaneHidden = false
    /// Published by the main split (#396); flips the sidebar through the same
    /// `columnVisibility` state the toolbar toggle drives. Nil when the main window
    /// isn't frontmost, which disables the item.
    @FocusedValue(\.sidebarToggleAction) private var sidebarToggle

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button(sidebarToggle?.collapsed == true ? "Show Sidebar" : "Hide Sidebar") {
                sidebarToggle?.perform()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(sidebarToggle == nil)

            Button(detailPaneHidden ? "Show Detail Pane" : "Hide Detail Pane") {
                // Animate the layout swap so the detail pane eases in/out like the
                // sidebar's toggle does, rather than snapping (#403). NavigationSplitView
                // exposes no detail-column visibility to animate natively, so the smooth
                // transition wraps the two/three-column swap instead.
                withAnimation(.smooth) { detailPaneHidden.toggle() }
            }
            .keyboardShortcut("d", modifiers: [.command, .control])

            // Inline rather than a nested `Menu`: the picker mirrors `@AppStorage`, so
            // it rebuilds on every selection, and as a submenu AppKit re-indexed it
            // mid-insert of an adjacent auto-separator and logged a benign but noisy
            // "didChangeSubmenu: …wrong item" warning (#407). An inline picker has no
            // submenu to re-index, so the warning can't fire; its label renders as a
            // "Stats Period" section header in the View menu.
            Picker("Stats Period", selection: $statsPeriod) {
                ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
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
    @FocusedValue(\.focusedPad) private var pad
    /// Mirrors the window's read-only state (offline) so the mutating items disable
    /// to match the in-window controls (#321). `nil`/`false` means editable.
    @FocusedValue(\.isReadOnly) private var isReadOnly
    /// Whether the focused pad has any code to save yet, so "Save Code…" disables
    /// until its environments (or legacy inline contents) have loaded. `nil` when
    /// no pad detail is frontmost.
    @FocusedValue(\.padHasSavableCode) private var padHasSavableCode
    /// Shares the Pads list's persisted sort key, so the menu's "Sort By" submenu
    /// and the list toolbar's Sort picker stay in lockstep (#415).
    @AppStorage(PadSort.storageKey) private var sort: PadSort = .updatedDesc
    /// Mirrors `PadDetailView.isEnded`, so "End Interview" disables once the pad
    /// is already ended instead of routing a no-op confirmation.
    private var isEnded: Bool {
        guard let pad else { return false }

        return pad.isEnded
    }

    var body: some Commands {
        CommandMenu("Pad") {
            Button("Open Pad in Browser") {
                guard let pad, let url = pad.webURL else { return }

                BrowserSettings.openExternally(url)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(pad == nil)

            Button("Watch Playback") {
                guard let pad else { return }

                AppNavigation.shared.watchPlaybackPadID = pad.id
            }
            .keyboardShortcut("y", modifiers: [.command])
            .disabled(pad?.playbackURL == nil)

            Divider()

            Button("Edit Pad…") {
                guard let pad else { return }

                AppNavigation.shared.editPadID = pad.id
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(pad == nil || isReadOnly == true)

            Menu("Sort By") {
                PadSortMenuContent(sort: $sort)
            }

            Divider()

            Button("Copy Pad ID") {
                guard let pad else { return }

                Clipboard.copy(pad.id)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(pad == nil)

            Button("Copy Pad URL") {
                guard let pad else { return }

                Clipboard.copy(pad.url)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(pad == nil)

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
            // `webURL` is available right here. Falls back to a disabled button
            // (so the item still appears) when no pad is selected.
            if let url = pad?.webURL {
                ShareLink("Share Pad…", item: url)
            } else {
                Button("Share Pad…") {}.disabled(true)
            }

            Divider()

            Button("Save Code…") {
                guard let pad else { return }

                AppNavigation.shared.saveCodePadID = pad.id
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(pad == nil || padHasSavableCode != true)

            Divider()

            Button("End Interview…") {
                guard let pad else { return }

                AppNavigation.shared.endPadID = pad.id
            }
            .disabled(pad == nil || isEnded || isReadOnly == true)

            Button("Delete Pad…") {
                guard let pad else { return }

                AppNavigation.shared.deletePadID = pad.id
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(pad == nil || isReadOnly == true)
        }
    }
}

/// Top-level "Question" menu: the Questions-pane counterpart to `PadCommands`,
/// acting on the question selected in the frontmost window (`focusedQuestion`).
/// New Pad / Delete route through `AppNavigation` so the mounted
/// `QuestionDetailView` performs them with its existing delete confirmation —
/// the same path the Questions list's context menu uses. (The long-form content
/// is edited in place in the detail view, so there's no Edit command here.)
///
/// `⌘↩` mirrors the Pad menu's primary action: with a pad selected it opens the
/// pad, with a question selected it creates a pad from that question — each the
/// headline action of the corresponding detail view. See `PadCommands` for why
/// sharing shortcuts across the two menus is unambiguous.
struct QuestionCommands: Commands {
    @FocusedValue(\.focusedQuestion) private var question
    @FocusedValue(\.focusedQuestionIsFavorite) private var isFavorite
    @FocusedValue(\.focusedQuestionURL) private var questionURL
    /// Mirrors the window's read-only state (offline) so the mutating items disable
    /// to match the in-window controls (#321). `nil`/`false` means editable.
    @FocusedValue(\.isReadOnly) private var isReadOnly
    /// Shares the Questions list's persisted sort key, so the menu's "Sort By"
    /// submenu and the list toolbar's Sort picker stay in lockstep.
    @AppStorage(QuestionSort.storageKey) private var sort: QuestionSort = .lastUsedDesc

    var body: some Commands {
        CommandMenu("Question") {
            Button("New Pad from Question") {
                guard let question else { return }

                AppNavigation.shared.createPadForQuestionID = question.id
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(question == nil || isReadOnly == true)

            Divider()

            Button(isFavorite == true ? "Remove from Favorites" : "Add to Favorites") {
                guard let question else { return }

                AppNavigation.shared.toggleFavoriteQuestionID = question.id
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(question == nil)

            Menu("Sort By") {
                QuestionSortMenuContent(sort: $sort)
            }

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
            // `focusedQuestionURL`. Falls back to a disabled button (so the item
            // still appears) when no question is selected.
            if let questionURL {
                ShareLink("Share Question…", item: questionURL)
            } else {
                Button("Share Question…") {}.disabled(true)
            }

            Divider()

            Button("Delete Question…") {
                guard let question else { return }

                AppNavigation.shared.deleteQuestionID = question.id
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(question == nil || isReadOnly == true)
        }
    }
}

/// Top-level "Screen" menu: acts on the selected Screen campaign or test session
/// in the frontmost window. The Screen views publish focused action wrappers so
/// command routing stays with the current selection and shares the same handlers
/// as row context menus and toolbar buttons.
struct ScreenCommands: Commands {
    @FocusedValue(\.focusedScreenCampaignAction) private var campaignAction
    @FocusedValue(\.focusedScreenTestAction) private var testAction
    @FocusedValue(\.focusedScreenInviteAction) private var inviteAction
    @FocusedValue(\.isReadOnly) private var isReadOnly

    var body: some Commands {
        CommandMenu("Screen") {
            Button("Show Test Sessions") {
                campaignAction?.showTests()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(campaignAction == nil)

            Button("Invite Candidate…") {
                inviteAction?.perform()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(inviteAction == nil || isReadOnly == true)

            Divider()

            Button("Open Test Session in New Window") {
                testAction?.openWindow()
            }
            .keyboardShortcut(.return, modifiers: [.command, .option])
            .disabled(testAction == nil)

            Button("Resend Invitation") {
                testAction?.resend()
            }
            .disabled(testAction?.canResendOrCancel != true || isReadOnly == true)

            Button("Cancel Invitation") {
                testAction?.cancel()
            }
            .disabled(testAction?.canResendOrCancel != true || isReadOnly == true)

            Divider()

            Button("Copy Campaign Name") {
                campaignAction?.copyName()
            }
            .disabled(campaignAction == nil)

            Button("Copy Test Session") {
                testAction?.copySummary()
            }
            .disabled(testAction == nil)

            Divider()

            Button("Delete Test Session…") {
                testAction?.delete()
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(testAction == nil || isReadOnly == true)
        }
    }
}

/// Adds an "Open Main Window" item to the Window menu so the main window can be
/// reopened after it's closed — the app keeps running with no windows (see
/// `AppDelegate.applicationShouldTerminateAfterLastWindowClosed`).
struct WindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Open Main Window") {
                AppActivator.bringToFront()
                openWindow(id: "main")
            }
            .keyboardShortcut("0", modifiers: [.command])
        }
    }
}
#endif
