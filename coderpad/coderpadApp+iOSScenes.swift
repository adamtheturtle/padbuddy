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
                    .windowScoped()
                    .modifier(ScreenshotTextSize(size: Self.screenshotTextSize))
                    .modifier(IPadWidgetIntentDrain())
                    .preferredColorScheme(appearance.colorScheme)
                    .onContinueUserActivity(CSSearchableItemActionType) { activity in
                        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }

                        if let pad = SpotlightIndexer.padRef(fromItemIdentifier: id) {
                            AppNavigation.shared.openPad(id: pad.id, account: pad.account)
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
                    .windowScoped()
                    .preferredColorScheme(appearance.colorScheme)
            }
        }

        private var padScene: some Scene {
            WindowGroup("Pad", id: "pad", for: PadWindowID.self) { $value in
                PadWindow(value: value)
                    .windowScoped()
                    .preferredColorScheme(appearance.colorScheme)
            }
        }

        private var screenTestScene: some Scene {
            WindowGroup("Test Session", id: "screen-test", for: ScreenTestWindowID.self) { $value in
                ScreenTestWindow(value: value)
                    .windowScoped()
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

        /// Replays every queued request in the order the user issued it, so the most
        /// recent action ends up on top. Draining each kind in its own loop always ran
        /// New Pad last, letting an older New Pad tap beat a newer Open Pad tap (#1045).
        @MainActor
        static func drainPendingWidgetRequests() {
            for pending in WidgetSharedStore.takePendingRequestsInOrder() {
                switch pending {
                case let .openPad(request):
                    // The request file is cross-process App Group data: a malformed
                    // id must not become a pending selection request (#1809).
                    guard let padID = PadIDValidation.normalize(request.id) else { continue }

                    // The validated account travels with the navigation request: it
                    // can outlive further view/account switches, and a bare pad id
                    // must not resolve under a different account (#1255). A named
                    // account that no longer resolves drops the request - a bare-slug
                    // fallback could select a same-slug pad in the wrong org (#2306).
                    var owner: UUID?
                    if let account = request.account, !account.isEmpty {
                        guard let uuid = WidgetAccountIdentity.localID(
                            for: account, accounts: AccountsStore.shared.accounts
                        ) else { continue }

                        AccountsStore.shared.showAllAccounts = false
                        AccountsStore.shared.currentAccountID = uuid
                        owner = uuid
                    }
                    AppNavigation.shared.showPads(
                        PadsRequest(selectPadID: padID, selectPadAccountID: owner)
                    )

                case let .newPad(request):
                    AppNavigation.shared.routeNewPad(account: request.account, seedQuestionID: request.question)
                }
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
