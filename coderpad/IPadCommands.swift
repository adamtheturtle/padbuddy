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
        /// Observed, not read once: the Go items' availability and the creation
        /// commands' gating depend on the live account, quota, and network state, and
        /// a `Commands` body that reads the shared stores without observing them keeps
        /// whatever was true when the command set was first built (#2366, #2367).
        @State private var accounts = AccountsStore.shared
        @State private var quotas = QuotaCacheStore.shared
        @State private var network = NetworkMonitor.shared
        @FocusedValue(\.findAction) private var findAction
        @FocusedValue(\.printAction) private var printAction
        @FocusedValue(\.exportMarkdownAction) private var exportMarkdownAction

        var body: some Commands {
            CommandGroup(replacing: .newItem) {
                // Creation needs an account to create in and a network to create over.
                // Ungated, a hardware-keyboard user could open a create sheet the app
                // had no way to complete, and only find out on submit (#2366) — the
                // menu-bar extra and the macOS New Pad from Question submenu already
                // disable themselves on the same conditions.
                Button("New Pad") {
                    AppNavigation.shared.showPads(PadsRequest(startCreating: true))
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(!canCreate)

                Button("New Question") {
                    AppNavigation.shared.showQuestions(QuestionsRequest(startCreating: true))
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!canCreate)

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

        /// Whether a create command can actually complete: there has to be an account
        /// with credentials to create under, and a network to reach it over.
        private var canCreate: Bool {
            guard !network.isOffline else { return false }

            return accounts.accounts.contains { $0.isMock || !$0.apiKey.isEmpty }
        }

        private func postIfNavigable(_ section: AppSection) {
            guard AppSection.navigable.contains(section) else { return }

            AppNavigation.shared.show(section)
        }

        private func cycleSection(by delta: Int) {
            // Queued as a request the focused window resolves against its own
            // section, which is per-window since #907.
            AppNavigation.shared.cycleSection(by: delta)
        }
    }
#endif
