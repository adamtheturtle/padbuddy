//
//  coderpadApp+iOSScenes.swift
//  coderpad
//
//  The iPad scene graph for `CoderpadApp`, split out of coderpadApp.swift (#580) so
//  the `@main` file keeps only the entry point, `App` conformance, `init()`, `body`,
//  and the shared helpers. `iOSScenes` stays internal so `body` (in the main file)
//  can reach it; the scene-local Settings cover lives in `provideAppSettingsAction()`.
//

#if !os(macOS)
    import CoreSpotlight
    import SwiftUI

    extension CoderpadApp {
        /// The iPad scene graph. A single primary `WindowGroup` hosting the same
        /// three-column `ContentView`; the macOS-only menu-bar extra, Dock menu,
        /// per-window `Window`/`WindowGroup` scenes, and `Settings` scene have no iPad
        /// analog, so iPad reaches Settings in-app. Pads/questions still open inline on
        /// compact layouts, with optional separate scenes registered below for iPad
        /// multi-window workflows. The Spotlight continuation and `coderpad://` deep-link
        /// handling are shared with macOS so widget taps and search results route the same way.
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
                            guard AppNavigation.shared.showQuestion(id: ref.id, account: ref.account) else {
                                SpotlightIndexer.removeQuestion(id: ref.id, account: ref.account)
                                return
                            }
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
                    // Also owns the scene-local Settings cover, so opening Settings
                    // covers only this window (#838).
                    .provideAppSettingsAction()
            }
            .commands {
                IPadCommands()
                PadCommands()
                QuestionCommands()
                ScreenCommands()
            }

            questionScene
            padScene
            screenTestScene
        }

        private var questionScene: some Scene {
            WindowGroup("Question", id: "question", for: QuestionWindowID.self) { $value in
                QuestionWindow(value: value)
                    .preferredColorScheme(appearance.colorScheme)
            }
        }

        private var padScene: some Scene {
            WindowGroup("Pad", id: "pad", for: PadWindowID.self) { $value in
                PadWindow(value: value)
                    .preferredColorScheme(appearance.colorScheme)
            }
        }

        private var screenTestScene: some Scene {
            WindowGroup("Test Session", id: "screen-test", for: ScreenTestWindowID.self) { $value in
                ScreenTestWindow(value: value)
                    .preferredColorScheme(appearance.colorScheme)
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
                    IPadWidgetIntentObserver.shared.start()
                    Self.drainPendingWidgetRequests()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }

                    Self.drainPendingWidgetRequests()
                }
        }

        @MainActor
        static func drainPendingWidgetRequests() {
            while let request = WidgetSharedStore.takePendingOpenPad() {
                if let account = request.account,
                   let uuid = UUID(uuidString: account),
                   AccountsStore.shared.accounts.contains(where: { $0.id == uuid }) {
                    AccountsStore.shared.showAllAccounts = false
                    AccountsStore.shared.currentAccountID = uuid
                }
                AppNavigation.shared.showPads(PadsRequest(selectPadID: request.id))
            }
            while let request = WidgetSharedStore.takePendingNewPad() {
                AppNavigation.shared.routeNewPad(account: request.account, seedQuestionID: request.question)
            }
        }
    }

    @MainActor
    private final class IPadWidgetIntentObserver {
        static let shared = IPadWidgetIntentObserver()

        private var isRegistered = false

        func start() {
            guard !isRegistered else { return }

            isRegistered = true
            register(notification: WidgetSharedStore.newPadRequestNotification)
            register(notification: WidgetSharedStore.openPadRequestNotification)
        }

        private func register(notification: String) {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                { _, _, _, _, _ in
                    Task { @MainActor in
                        IPadWidgetIntentDrain.drainPendingWidgetRequests()
                    }
                },
                notification as CFString,
                nil,
                .deliverImmediately
            )
        }
    }
#endif
