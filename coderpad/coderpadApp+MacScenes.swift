//
//  coderpadApp+MacScenes.swift
//  coderpad
//
//  The macOS scene graph for `CoderpadApp`, split out of coderpadApp.swift to keep
//  each file under the length limit. `macOSScenes` stays internal so `body` (in the
//  main file) can reach it; the per-window scenes and commands it composes stay
//  private to this file. The shared stored properties and helpers they read
//  (`appearance`, `presence`, `network`, `handleDeepLink`, `post`, `cycleSection`)
//  are module-internal in the main file for exactly this cross-file split.
//

#if os(macOS)
    import CoreSpotlight
    import SwiftUI

    extension CoderpadApp {
        @SceneBuilder var macOSScenes: some Scene {
            // A single, unique main window (`Window`, not `WindowGroup`): opening "main"
            // again - from the menu bar's Add Account, the Dock icon, or "Open Main
            // Window" - focuses the existing window instead of spawning a duplicate (#459).
            // The app still survives closing it (windowless menu-bar mode) because
            // `applicationShouldTerminateAfterLastWindowClosed` returns false.
            Window("PadBuddy", id: "main") {
                ContentView()
                    // Width floor is owned by `MainSplit`, derived from the live column
                    // minimums (and enforced via the sidebar's auto-collapse) rather
                    // than a hardcoded number here.
                    .frame(minHeight: 540)
                    .provideAppSettingsAction()
                    // Screenshot-only Dynamic Type override (`-uiTestingTextSize <name>`):
                    // captures the marketing shots with larger, more legible UI text. Nil
                    // for real users, so their own accessibility text size is honored.
                    .modifier(ScreenshotTextSize(size: Self.screenshotTextSize))
                    .preferredColorScheme(appearance.colorScheme)
                    // Open the pad/question behind a tapped Spotlight result.
                    .onContinueUserActivity(CSSearchableItemActionType) { activity in
                        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }

                        if let padID = SpotlightIndexer.padID(fromItemIdentifier: id) {
                            AppNavigation.shared.openPad(id: padID)
                        } else if let ref = SpotlightIndexer.questionRef(fromItemIdentifier: id) {
                            // Switch to the owning account first so the right org's
                            // question is selected - per-org ids collide across accounts (#378).
                            // Only if it still exists; a removed account's items are cleared too.
                            if AccountsStore.shared.accounts.contains(where: { $0.id == ref.account }) {
                                AccountsStore.shared.currentAccountID = ref.account
                            }
                            AppNavigation.shared.showFavoriteQuestion(id: ref.id)
                        }
                    }
                    // Resume a pad handed off from another device / Siri Suggestion (#596)
                    // by opening it in the user's browser.
                    .onContinueUserActivity(PadActivity.type) { activity in
                        if let url = padActivityURL(activity) {
                            BrowserSettings.openExternally(url)
                        }
                    }
                    // Open a pad tapped in the Recent Pads widget (coderpad://pad/<id>).
                    .onOpenURL { url in
                        handleDeepLink(url)
                    }
            }
            .defaultLaunchBehavior(.presented)
            .defaultSize(width: 1100, height: 720)
            .commands {
                appCommands
                FindCommands()
                NewPadFromQuestionCommands()
                PrintCommands()
                // The system's Show/Hide and Customize Toolbar commands. Every section
                // and detail toolbar is a customizable `.toolbar(id:)` with stable item
                // ids, so "Customize Toolbar…" is enabled and the whole window toolbar
                // can be rearranged.
                ToolbarCommands()
                ViewCommands()
                PadCommands()
                QuestionCommands()
                ScreenCommands()
                WindowCommands()
            }

            questionScene
            padScene
            screenTestScene
            mcpActivityScene

            Settings {
                SettingsView()
                    .preferredColorScheme(appearance.colorScheme)
            }

            menuBarScene
        }

        /// Double-clicking a question row opens its detail here, in its own window.
        /// Keyed by a lightweight id so it survives state restoration.
        private var questionScene: some Scene {
            // swiftformat:disable:next unusedArguments
            WindowGroup("Question", id: "question", for: QuestionWindowID.self) { $value in
                QuestionWindow(value: value)
                    .frame(minWidth: 600, minHeight: 560)
                    .preferredColorScheme(appearance.colorScheme)
            }
        }

        /// Double-clicking a pad row opens its native detail here, in its own window -
        /// the pad counterpart to ``questionScene`` (#354). Keyed by a lightweight id
        /// so it survives state restoration.
        private var padScene: some Scene {
            // swiftformat:disable:next unusedArguments
            WindowGroup("Pad", id: "pad", for: PadWindowID.self) { $value in
                PadWindow(value: value)
                    .frame(minWidth: 600, minHeight: 560)
                    .preferredColorScheme(appearance.colorScheme)
            }
        }

        /// A Screen test session's report opened in its own window, from the tests list's
        /// "Open in New Window" action / double-click (#474). Keyed by a lightweight id so
        /// it survives state restoration.
        private var screenTestScene: some Scene {
            // swiftformat:disable:next unusedArguments
            WindowGroup("Test Session", id: "screen-test", for: ScreenTestWindowID.self) { $value in
                ScreenTestWindow(value: value)
                    .frame(minWidth: 600, minHeight: 560)
                    .preferredColorScheme(appearance.colorScheme)
            }
        }

        /// The menu-bar extra. The system can flip `isInserted` to false if the user
        /// drags the icon out of the menu bar; mirror that back into the preference so
        /// the change sticks and the Settings picker stays honest. Removing the icon
        /// switches to "Dock only" (revealing the Dock icon if it was hidden, so the app
        /// never ends up with no visible affordance); re-inserting it restores a
        /// menu-bar mode.
        private var menuBarScene: some Scene {
            MenuBarExtra(isInserted: Binding(
                get: { presence.showsMenuBarIcon },
                set: { inserted in
                    guard inserted != presence.showsMenuBarIcon else { return }

                    presence = inserted
                        ? (presence.showsDockIcon ? .dockAndMenuBar : .menuBarOnly)
                        : .dockOnly
                    GeneralSettings.applyDockVisibility()
                }
            )) {
                MenuBarView()
            } label: {
                MenuBarLabel()
            }
            .menuBarExtraStyle(.menu)
        }

        @CommandsBuilder
        private var appCommands: some Commands {
            CommandGroup(replacing: .appInfo) {
                Button("About PadBuddy") { showAbout() }
            }
            // "Check for Updates…" sits just below About, its conventional home. The
            // item only appears once the Sparkle package is linked (#28); without it
            // this group is empty and adds nothing.
            CommandGroup(after: .appInfo) {
                #if canImport(Sparkle)
                    CheckForUpdatesButton()
                #endif
            }
            CommandGroup(replacing: .newItem) {
                Button("New Pad…") {
                    AppNavigation.shared.showPads(PadsRequest(startCreating: true))
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(network.isOffline)
                Button("New Question…") {
                    AppNavigation.shared.showQuestions(QuestionsRequest(startCreating: true))
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(network.isOffline)
                Divider()
                Button("Open Pad by URL…") {
                    AppRouter.requestOpenPadByURL()
                }
                .keyboardShortcut("o", modifiers: [.command])
                Divider()
                Button("Reload") {
                    AppRouter.requestReload()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            CommandMenu("Go") {
                // The command palette lives here, not in File: it's the "go to anything"
                // entry point, so the Go menu is where users look for it (#533).
                Button("Go to Anything…") {
                    AppRouter.requestCommandPalette()
                }
                .keyboardShortcut("k", modifiers: [.command])
                Divider()
                Button("Pads") { post(.pads) }.keyboardShortcut("1", modifiers: [.command])
                Button("Questions") { post(.questions) }.keyboardShortcut("2", modifiers: [.command])
                Button("Organization") { post(.organization) }.keyboardShortcut("3", modifiers: [.command])
                Divider()
                Button("Next Section") { cycleSection(by: 1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Section") { cycleSection(by: -1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Link("CoderPad API Documentation", destination: CoderPadLinks.apiDocs)
                Link("Get API Key", destination: CoderPadLinks.apiSettings)
                Divider()
                Link("Send Feedback…", destination: CoderPadLinks.feedbackMailto)
            }
        }

        func showAbout() {
            showAboutPanel()
        }
    }
#endif
