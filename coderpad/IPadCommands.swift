//
//  IPadCommands.swift
//  coderpad
//
//  Hardware-keyboard shortcuts for iPad (Magic Keyboard / Smart Keyboard). macOS gets
//  the full menu-bar command set (see `coderpadApp+Commands.swift`); iPad has no menu
//  bar, but `.commands` still registers these as discoverable key commands (hold Cmd to
//  see them). A curated mirror of the most-used macOS shortcuts, built only from the
//  cross-platform `AppNavigation` / `AppRouter` routes and the shared `findAction`.
//

#if !os(macOS)
    import SwiftUI

    struct IPadCommands: Commands {
        @FocusedValue(\.findAction) private var findAction
        @FocusedValue(\.printAction) private var printAction
        @FocusedValue(\.exportMarkdownAction) private var exportMarkdownAction

        var body: some Commands {
            CommandGroup(replacing: .newItem) {
                Button("New Pad") {
                    AppNavigation.shared.showPads(PadsRequest(startCreating: true))
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("New Question") {
                    AppNavigation.shared.showQuestions(QuestionsRequest(startCreating: true))
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(after: .textEditing) {
                Button("Find") { findAction?.perform() }
                    .keyboardShortcut("f", modifiers: [.command])
                    .disabled(findAction == nil)
            }

            // The focused pad detail's document actions, mirroring the on-screen
            // "Document Actions" toolbar menu so hardware-keyboard users get ⌘P / ⇧⌘E
            // (and can discover them by holding ⌘). Both disable when no pad is frontmost.
            CommandGroup(replacing: .printItem) {
                Button("Print…") { printAction?.perform() }
                    .keyboardShortcut("p", modifiers: [.command])
                    .disabled(printAction == nil)

                Button("Export as Markdown…") { exportMarkdownAction?.perform() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(exportMarkdownAction == nil)
            }

            CommandMenu("Go") {
                Button("Go to Anything…") { AppRouter.requestCommandPalette() }
                    .keyboardShortcut("k", modifiers: [.command])

                Divider()

                Button("Pads") { AppNavigation.shared.show(.pads) }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Questions") { AppNavigation.shared.show(.questions) }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Organization") { AppNavigation.shared.show(.organization) }
                    .keyboardShortcut("3", modifiers: [.command])
            }
        }
    }
#endif
