//
//  PadBuddyApp+iOSScenes.swift
//  coderpad
//
//  The iPad scene graph for `PadBuddyApp`, split out of PadBuddyApp.swift (#580) so
//  the `@main` file keeps only the entry point, `App` conformance, `init()`, `body`,
//  and the shared helpers. `iOSScenes` stays internal so `body` (in the main file)
//  can reach it; the scene-local Settings cover lives in `provideAppSettingsAction()`.
//

#if !os(macOS)
    import CoreSpotlight
    import os
    import SwiftUI

    extension PadBuddyApp {
        /// The iPad scene graph. A single primary `WindowGroup` hosting the same
        /// three-column `ContentView`; the macOS-only menu-bar extra, Dock menu,
        /// per-window `Window`/`WindowGroup` scenes, and `Settings` scene have no iPad
        /// analog, so iPad reaches Settings in-app. Pads/questions still open inline on
        /// compact layouts, with optional separate scenes registered below for iPad
        /// multi-window workflows. The Spotlight continuation and `com.adamdangoor.padbuddy://` deep-link
        /// handling are shared with macOS so widget taps and search results route the same way.
        @SceneBuilder var iOSScenes: some Scene {
            #if os(visionOS)
                WindowGroup {
                    iOSMainContent
                }
                .defaultSize(
                    width: Self.visionDefaultWindowSize.width,
                    height: Self.visionDefaultWindowSize.height
                )
                .commands {
                    IPadCommands()
                    FilterCommands()
                    PadCommands()
                    QuestionCommands()
                    ScreenCommands()
                }
            #else
                WindowGroup {
                    iOSMainContent
                }
                .commands {
                    IPadCommands()
                    FilterCommands()
                    PadCommands()
                    QuestionCommands()
                    ScreenCommands()
                }
            #endif

            questionScene
            padScene
            screenTestScene
        }

        #if os(visionOS)
            /// A deterministic initial spatial-window size for opt-in UI smoke
            /// captures. Production launches retain the normal 1040×720 default.
            private static var visionDefaultWindowSize: CGSize {
                let arguments = ProcessInfo.processInfo.arguments
                guard arguments.contains("-uiTesting"),
                      let flag = arguments.firstIndex(of: "-uiTestingWindowSize"),
                      arguments.indices.contains(flag + 1)
                else { return CGSize(width: 1040, height: 720) }

                let parts = arguments[flag + 1].split(separator: "x")
                guard parts.count == 2,
                      let width = Double(parts[0]),
                      let height = Double(parts[1]),
                      width >= 480,
                      height >= 400
                else { return CGSize(width: 1040, height: 720) }

                return CGSize(width: width, height: height)
            }
        #endif

        private var iOSMainContent: some View {
            iOSBaseContent
                .modifier(IOSContinuationHandlers(
                    handleSpotlightContinuation: handleSpotlightContinuation,
                    handlePadContinuation: handlePadContinuation,
                    handleDeepLink: handleDeepLink
                ))
                // Also owns the scene-local Settings cover, so opening Settings
                // covers only this window (#838).
                .provideAppSettingsAction()
        }

        private var iOSBaseContent: some View {
            ContentView()
                .windowScoped()
                .modifier(ScreenshotTextSize(size: Self.screenshotTextSize))
                .modifier(IPadWidgetIntentDrain())
                .preferredColorScheme(appearance.colorScheme)
        }

        private func handleSpotlightContinuation(_ activity: NSUserActivity) {
            guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }

            if let pad = SpotlightIndexer.padRef(fromItemIdentifier: id) {
                let owner = pad.account
                guard let padID = PadIDValidation.normalize(pad.id),
                      owner.map({ id in AccountsStore.shared.accounts.contains { $0.id == id } }) ?? true
                else {
                    if let owner {
                        SpotlightIndexer.removePad(id: pad.id, account: owner)
                    }
                    return
                }

                AppNavigation.shared.openPad(id: padID, account: owner)
            } else if let ref = SpotlightIndexer.questionRef(fromItemIdentifier: id) {
                guard AppNavigation.shared.showQuestion(id: ref.id, account: ref.account) else {
                    SpotlightIndexer.removeQuestion(id: ref.id, account: ref.account)
                    return
                }
            }
        }

        private func handlePadContinuation(_ activity: NSUserActivity) {
            guard let url = padActivityURL(activity) else { return }

            if let route = PadActivity.padRoute(for: url), route.account != nil {
                AppNavigation.shared.openPad(id: route.id, account: route.account)
            } else {
                BrowserSettings.openExternally(url)
            }
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

    private struct IOSContinuationHandlers: ViewModifier {
        let handleSpotlightContinuation: (NSUserActivity) -> Void
        let handlePadContinuation: (NSUserActivity) -> Void
        let handleDeepLink: (URL) -> Void

        func body(content: Content) -> some View {
            content
                .onContinueUserActivity(CSSearchableItemActionType, perform: handleSpotlightContinuation)
                .onContinueUserActivity(PadActivity.type, perform: handlePadContinuation)
                .onOpenURL(perform: handleDeepLink)
        }
    }

    /// Drains pending widget intents on iPad. Widget buttons cannot rely on the app's
    /// custom URL scheme there, so intents write requests into the App Group and open
    /// the app; this consumes those requests once the scene is active.
    private struct IPadWidgetIntentDrain: ViewModifier {
        @Environment(\.scenePhase) private var scenePhase

        func body(content: Content) -> some View {
            #if os(iOS)
                content
                    .task {
                        IPadWidgetIntentObserver.shared.start()
                        Self.drainPendingWidgetRequests()
                    }
                    .onChange(of: scenePhase) { _, phase in
                        guard phase == .active else { return }

                        Self.drainPendingWidgetRequests()
                    }
            #else
                content
            #endif
        }

        /// Replays every queued request in the order the user issued it, so the most
        /// recent action ends up on top. Draining each kind in its own loop always ran
        /// New Pad last, letting an older New Pad tap beat a newer Open Pad tap (#1045).
        @MainActor
        static func drainPendingWidgetRequests() {
            for pending in WidgetSharedStore.takePendingRequestsInOrder() {
                defer { acknowledge(pending) }
                switch pending.request {
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

        private static func acknowledge(_ pending: WidgetClaimedRequest) {
            do {
                try pending.acknowledge()
            } catch {
                persistenceLogger.error(
                    "Could not acknowledge a handled iPad widget request: \(error.localizedDescription)"
                )
            }
        }
    }

    #if os(iOS)
        @MainActor
        private final class IPadWidgetIntentObserver {
            static let shared = IPadWidgetIntentObserver()

            private var isRegistered = false

            func start() {
                guard !isRegistered else { return }

                isRegistered = true
                register(notification: WidgetSharedStore.handoffRequestNotification)
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
#endif
