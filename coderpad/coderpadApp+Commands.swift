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

/// Adds "Customize Toolbar…" to the View menu, matching Mail, Finder, and other
/// system apps. SwiftUI makes the section toolbars user-customizable (via
/// `.toolbar(id:)`) and offers customization through the toolbar's right-click
/// menu, but provides no menu command for it — so this bridges to AppKit's
/// `runCustomizationPalette(_:)` on the frontmost window's `NSToolbar`.
///
/// The item enables only while `canCustomizeToolbar` is published — i.e. a main
/// window is key. Settings and the Pad Browser don't have a customizable
/// `NSToolbar`, so it stays disabled there rather than presenting nothing.
/// Placed `after: .toolbar` so it sits just below "Show/Hide Toolbar", the same
/// spot system apps use.
struct ViewCommands: Commands {
    @FocusedValue(\.canCustomizeToolbar) private var canCustomizeToolbar

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Customize Toolbar…") {
                NSApp.keyWindow?.toolbar?.runCustomizationPalette(nil)
            }
            .disabled(canCustomizeToolbar != true)
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
    @Environment(\.openWindow) private var openWindow

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
                NotificationCenter.default.post(name: .openPadInBrowserRequested, object: url)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(pad == nil)

            Button("Open Pad in New Window") {
                guard let pad, let url = pad.webURL else { return }
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "pad-browser", value: url)
            }
            .keyboardShortcut(.return, modifiers: [.command, .option])
            .disabled(pad == nil)

            Divider()

            Button("Edit Pad…") {
                guard let pad else { return }
                AppNavigation.shared.editPadID = pad.id
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(pad == nil)

            Divider()

            Button("Copy Pad ID") {
                guard let pad else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pad.id, forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(pad == nil)

            Button("Copy Pad URL") {
                guard let pad else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pad.url, forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(pad == nil)

            Button("Copy Pad Title") {
                guard let pad else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pad.title.isEmpty ? pad.id : pad.title, forType: .string)
            }
            .disabled(pad == nil)

            Divider()

            Button("End Interview…") {
                guard let pad else { return }
                AppNavigation.shared.endPadID = pad.id
            }
            .disabled(pad == nil || isEnded)

            Button("Delete Pad…") {
                guard let pad else { return }
                AppNavigation.shared.deletePadID = pad.id
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(pad == nil)
        }
    }
}

/// Top-level "Question" menu: the Questions-pane counterpart to `PadCommands`,
/// acting on the question selected in the frontmost window (`focusedQuestion`).
/// New Pad / Edit / Delete route through `AppNavigation` so the mounted
/// `QuestionDetailView` performs them with its existing sheets and delete
/// confirmation — the same path the Questions list's context menu uses.
///
/// `⌘↩` mirrors the Pad menu's primary action: with a pad selected it opens the
/// pad, with a question selected it creates a pad from that question — each the
/// headline action of the corresponding detail view. See `PadCommands` for why
/// sharing shortcuts across the two menus is unambiguous.
struct QuestionCommands: Commands {
    @FocusedValue(\.focusedQuestion) private var question

    var body: some Commands {
        CommandMenu("Question") {
            Button("New Pad from Question") {
                guard let question else { return }
                AppNavigation.shared.createPadForQuestionID = question.id
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(question == nil)

            Divider()

            Button("Edit Question…") {
                guard let question else { return }
                AppNavigation.shared.editQuestionID = question.id
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(question == nil)

            Divider()

            Button("Copy Question ID") {
                guard let question else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(question.id), forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(question == nil)

            Button("Copy Question Title") {
                guard let question else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(question.displayTitle, forType: .string)
            }
            .disabled(question == nil)

            Divider()

            Button("Delete Question…") {
                guard let question else { return }
                AppNavigation.shared.deleteQuestionID = question.id
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(question == nil)
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
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut("0", modifiers: [.command])
        }
    }
}
