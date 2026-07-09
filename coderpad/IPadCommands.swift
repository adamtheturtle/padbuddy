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

                Button("Open Pad by URL…") {
                    AppRouter.requestOpenPadByURL()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Reload") {
                    AppRouter.requestReload()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            // A `.searchable` field already gives iOS its own ⌘F "Find"; adding ours
            // on top makes two ⌘F commands UIKit rejects as a duplicate
            // (`_UIMenuBuilderError`). So only provide ⌘F for panes whose search is a
            // bespoke field with no system shortcut (e.g. Organization).
            CommandGroup(after: .textEditing) {
                if let findAction, !findAction.hasSystemFindShortcut {
                    Button("Find") { findAction.perform() }
                        .keyboardShortcut("f", modifiers: [.command])
                }
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
                Button("Quota") { postIfNavigable(.quota) }
                    .keyboardShortcut("4", modifiers: [.command])
                    .disabled(!AppSection.navigable.contains(.quota))
                Button("Screen") { postIfNavigable(.screen) }
                    .keyboardShortcut("5", modifiers: [.command])
                    .disabled(!AppSection.navigable.contains(.screen))

                Divider()

                Button("Next Section") { cycleSection(by: 1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Section") { cycleSection(by: -1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
            }
        }

        private func postIfNavigable(_ section: AppSection) {
            guard AppSection.navigable.contains(section) else { return }

            AppNavigation.shared.show(section)
        }

        private func cycleSection(by delta: Int) {
            let order = AppSection.navigable
            guard !order.isEmpty else { return }

            let current = AppNavigation.shared.section
            let index = order.firstIndex(of: current) ?? 0
            let count = order.count
            let next = order[((index + delta) % count + count) % count]
            AppNavigation.shared.show(next)
        }
    }
#endif
