//
//  coderpadApp+iOSScenes.swift
//  coderpad
//
//  The iPad scene graph for `CoderpadApp`, split out of coderpadApp.swift (#580) so
//  the `@main` file keeps only the entry point, `App` conformance, `init()`, `body`,
//  and the shared helpers. `iOSScenes` stays internal so `body` (in the main file)
//  can reach it; the Settings sheet it composes stays private to this file.
//

#if !os(macOS)
    import CoreSpotlight
    import SwiftUI

    extension CoderpadApp {
        /// The iPad scene graph. A single primary `WindowGroup` hosting the same
        /// three-column `ContentView`; the macOS-only menu-bar extra, Dock menu,
        /// per-window `Window`/`WindowGroup` scenes, and `Settings` scene have no iPad
        /// analog, so iPad reaches Settings in-app and opens pads/questions inline. The
        /// Spotlight continuation and `coderpad://` deep-link handling are shared with
        /// macOS so widget taps and search results route the same way.
        @SceneBuilder var iOSScenes: some Scene {
            WindowGroup {
                ContentView()
                    .modifier(ScreenshotTextSize(size: Self.screenshotTextSize))
                    .modifier(IPadWidgetIntentDrain())
                    .preferredColorScheme(appearance.colorScheme)
                    .onContinueUserActivity(CSSearchableItemActionType) { activity in
                        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }

                        if let padID = SpotlightIndexer.padID(fromItemIdentifier: id) {
                            AppNavigation.shared.openPad(id: padID)
                        } else if let ref = SpotlightIndexer.questionRef(fromItemIdentifier: id) {
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
                    .onOpenURL { url in
                        handleDeepLink(url)
                    }
                    .provideAppSettingsAction()
                    // A full-screen cover, not a `.sheet`: on iPad a sheet is a centered form
                    // sheet whose faint scrim let the parent's empty-state text and window
                    // chrome bleed around the card edges and read as broken (#577/#578). A
                    // full cover hides the background entirely; the Done button dismisses it.
                    .fullScreenCover(isPresented: Binding(
                        get: { SettingsPresentation.shared.isPresented },
                        set: { SettingsPresentation.shared.isPresented = $0 }
                    )) {
                        iPadSettingsSheet
                    }
            }
            .commands {
                IPadCommands()
                PadCommands()
                QuestionCommands()
                ScreenCommands()
            }
        }

        /// The iPad in-app Settings sheet (there is no macOS-style `Settings` scene on iOS).
        /// Reached via the shared `\.openAppSettings` action, which raises
        /// `SettingsPresentation.shared.isPresented`.
        private var iPadSettingsSheet: some View {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { SettingsPresentation.shared.isPresented = false }
                        }
                    }
            }
        }
    }

    /// Drains pending widget intents on iPad. Widget buttons cannot rely on the app's
    /// custom URL scheme there, so intents write requests into the App Group and open
    /// the app; this consumes those requests once the scene is active.
    private struct IPadWidgetIntentDrain: ViewModifier {
        @Environment(\.scenePhase) private var scenePhase

        func body(content: Content) -> some View {
            content
                .task {
                    drainPendingWidgetRequests()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }

                    drainPendingWidgetRequests()
                }
        }

        @MainActor
        private func drainPendingWidgetRequests() {
            if let request = WidgetSharedStore.takePendingOpenPad() {
                if let account = request.account,
                   let uuid = UUID(uuidString: account),
                   AccountsStore.shared.accounts.contains(where: { $0.id == uuid }) {
                    AccountsStore.shared.showAllAccounts = false
                    AccountsStore.shared.currentAccountID = uuid
                }
                AppNavigation.shared.showPads(PadsRequest(selectPadID: request.id))
            }
            if let request = WidgetSharedStore.takePendingNewPad() {
                AppNavigation.shared.routeNewPad(account: request.account, seedQuestionID: request.question)
            }
        }
    }
#endif
