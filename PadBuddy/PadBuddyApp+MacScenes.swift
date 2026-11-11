//
//  PadBuddyApp+MacScenes.swift
//  coderpad
//
//  The macOS scene graph for `PadBuddyApp`, split out of PadBuddyApp.swift to keep
//  each file under the length limit. `macOSScenes` stays internal so `body` (in the
//  main file) can reach it; the per-window scenes and commands it composes stay
//  private to this file. The shared stored properties and helpers they read
//  (`appearance`, `presence`, `network`, `handleDeepLink`, `post`, `cycleSection`)
//  are module-internal in the main file for exactly this cross-file split.
//

#if os(macOS)
    import CoreSpotlight
    import SwiftUI

    extension PadBuddyApp {
        @SceneBuilder var macOSScenes: some Scene {
            mainWindowScene

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

        /// The main window, extracted from `macOSScenes` so each stays inside the
        /// 250ms per-expression type-check budget (warnings-as-errors) — the combined
        /// scene graph plus its commands went over it.
        @SceneBuilder private var mainWindowScene: some Scene {
            // A single, unique main window (`Window`, not `WindowGroup`): opening "main"
            // again - from the menu bar's Add Account, the Dock icon, or "Open Main
            // Window" - focuses the existing window instead of spawning a duplicate (#459).
            // The app still survives closing it (windowless menu-bar mode) because
            // `applicationShouldTerminateAfterLastWindowClosed` returns false.
            Window("PadBuddy", id: "main") {
                ContentView()
                    .windowScoped()
                    // Width floor is owned by `MainSplit`, derived from the live column
                    // minimums (and enforced via the sidebar's auto-collapse) rather
                    // than a hardcoded number here.
                    .frame(minHeight: 420)
                    .provideAppSettingsAction()
                    // Screenshot-only Dynamic Type override (`-uiTestingTextSize <name>`):
                    // captures the marketing shots with larger, more legible UI text. Nil
                    // for real users, so their own accessibility text size is honored.
                    .modifier(ScreenshotTextSize(size: Self.screenshotTextSize))
                    .preferredColorScheme(appearance.colorScheme)
                    // Open the pad/question behind a tapped Spotlight result.
                    .onContinueUserActivity(CSSearchableItemActionType) { activity in
                        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }

                        if let pad = SpotlightIndexer.padRef(fromItemIdentifier: id) {
                            // A stale index entry can name an account that has since been
                            // removed, or a pad id that isn't one. Opening it anyway routed
                            // a same-slug pad under whichever account was current (#2324) —
                            // the question path below has aborted on this since #1256.
                            let owner = pad.account
                            guard let padID = PadIDValidation.normalize(pad.id),
                                  owner.map({ id in
                                      AccountsStore.shared.accounts.contains { $0.id == id }
                                  }) ?? true
                            else {
                                if let owner {
                                    SpotlightIndexer.removePad(id: pad.id, account: owner)
                                }
                                return
                            }

                            AppNavigation.shared.openPad(id: padID, account: owner)
                        } else if let ref = SpotlightIndexer.questionRef(fromItemIdentifier: id) {
                            // If the account was removed but Spotlight still has a stale
                            // result, abort instead of opening another org's colliding id.
                            guard AppNavigation.shared.showQuestion(id: ref.id, account: ref.account) else {
                                SpotlightIndexer.removeQuestion(id: ref.id, account: ref.account)
                                return
                            }
                        }
                    }
                    // Resume a pad handed off from another device / Siri Suggestion (#596)
                    // by opening it in the user's browser.
                    .onContinueUserActivity(PadActivity.type) { activity in
                        guard let url = padActivityURL(activity) else { return }

                        // Resolved to a pad and its owning account first, so a handed-off
                        // pad lands in the app under the right account instead of losing
                        // that context to the browser (#2325). An origin no configured
                        // account serves, or one served by two of them, still opens
                        // externally — the app has no context to route it into.
                        if let route = PadActivity.padRoute(for: url), route.account != nil {
                            AppNavigation.shared.openPad(id: route.id, account: route.account)
                        } else {
                            BrowserSettings.openExternally(url)
                        }
                    }
                    // Open a pad tapped in the Recent Pads widget (com.adamdangoor.padbuddy://pad/<id>).
                    .onOpenURL { url in
                        handleDeepLink(url)
                    }
                    .modifier(WindowRestorationGate())
            }
            .defaultLaunchBehavior(.presented)
            .defaultSize(width: 1100, height: 720)
            .commands {
                appCommands
                FindCommands()
                FilterCommands()
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
            }
        }

        /// Double-clicking a question row opens its detail here, in its own window.
        /// Keyed by a lightweight id so it survives state restoration.
        private var questionScene: some Scene {
            // swiftformat:disable:next unusedArguments
            WindowGroup("Question", id: "question", for: QuestionWindowID.self) { $value in
                QuestionWindow(value: value)
                    .windowScoped()
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
                    .windowScoped()
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
                    .windowScoped()
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

                    let updated: AppPresence = inserted
                        ? (presence.showsDockIcon ? .dockAndMenuBar : .menuBarOnly)
                        : .dockOnly
                    presence = updated
                    // Kept on this Mac. Dragging the icon out is a local, often
                    // transient gesture, and `presence` is cloud-synced between Macs -
                    // so it used to hide the menu-bar icon on every other Mac too,
                    // with nothing to explain why (#2327). Changing it deliberately in
                    // Settings still syncs.
                    PreferenceCloudSync.shared.holdLocal(key: GeneralSettings.Key.presence,
                                                         value: updated.rawValue)
                    GeneralSettings.applyDockVisibility()
                }
            )) {
                MenuBarView()
            } label: {
                MenuBarLabel()
            }
            .menuBarExtraStyle(.menu)
        }

        /// Whether the creation commands can actually complete; see
        /// `AppCreationAvailability`.
        private var canCreate: Bool {
            AppCreationAvailability.canCreate(accounts: accounts, network: network)
        }

        @CommandsBuilder
        private var appCommands: some Commands {
            CommandGroup(replacing: .appInfo) {
                Button("About PadBuddy") { showAbout() }
            }
            // "Check for Updates…" sits just below About, its conventional home. The
            // item only appears once the BuddySparkleUpdater package product is linked
            // (#28). App Store builds must not link or embed Sparkle.
            CommandGroup(after: .appInfo) {
                #if !APP_STORE && canImport(BuddySparkleUpdater)
                    CheckForUpdatesButton()
                #endif
            }
            CommandGroup(replacing: .newItem) {
                Button("New Pad…") {
                    AppNavigation.shared.showPads(PadsRequest(startCreating: true))
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(!canCreate)
                Button("New Question…") {
                    AppNavigation.shared.showQuestions(QuestionsRequest(startCreating: true))
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!canCreate)
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
            CommandGroup(replacing: .help) {
                Link("CoderPad API Documentation", destination: CoderPadLinks.apiDocs)
                Link("Get API Key", destination: CoderPadLinks.apiSettings)
                Divider()
                Link("Send Feedback…", destination: CoderPadLinks.feedbackMailto)
            }
            WindowCommands()
        }

        func showAbout() {
            showAboutPanel()
        }
    }
#endif
