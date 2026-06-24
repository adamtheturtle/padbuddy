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
