//
//  coderpadApp+iOSScenes.swift
//  coderpad
//
//  The iPad scene graph for `CoderpadApp`, split out of coderpadApp.swift (#580) so
//  the `@main` file keeps only the entry point, `App` conformance, `init()`, `body`,
//  and the shared helpers. `iOSScenes` stays internal so `body` (in the main file)
//  can reach it; the pad-browser scene and Settings sheet it composes stay private
//  to this file.
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
                    // Resume a pad handed off from another device / Siri Suggestion (#596),
                    // reopening it in the in-app browser window the rest of the app uses.
                    .onContinueUserActivity(PadActivity.type) { activity in
                        if let url = padActivityURL(activity) {
                            AppRouter.requestOpenPadInBrowser(url)
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
            }

            iOSPadBrowserScene
        }

        /// A pad opened in its own window on iPad — the multi-window counterpart to the
        /// detail browser's "Open in separate window" button. With Stage Manager or Split
        /// View this places the pad's live web view in a second window beside the main one;
        /// it is keyed by URL so the system can restore it. Mirrors the macOS
        /// ``padBrowserScene`` (#292/#354) within iPad's single-`WindowGroup` model.
        private var iOSPadBrowserScene: some Scene {
            // swiftformat:disable:next unusedArguments
            WindowGroup("Pad", id: "pad-browser", for: URL.self) { $url in
                if let url {
                    NavigationStack {
                        PadBrowserView(url: url)
                            .navigationTitle(url.host ?? "Pad")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .preferredColorScheme(appearance.colorScheme)
                } else {
                    // A restored window can arrive without its URL; show a placeholder
                    // rather than a blank window.
                    ContentUnavailableView("No Pad", systemImage: "rectangle.on.rectangle",
                                           description: Text("Open a pad to view it here."))
                        .preferredColorScheme(appearance.colorScheme)
                }
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
#endif
