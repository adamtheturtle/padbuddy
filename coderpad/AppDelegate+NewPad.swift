//
//  AppDelegate+NewPad.swift
//  coderpad
//
//  The widget / Control Center "New Pad" path: create a pad through the API and open
//  it in the user's browser, falling back to the in-app create flow when that isn't
//  possible (#456, #485, #602). Split out of the main app file so it stays under the
//  file-length budget.
//

#if os(macOS)
    import AppKit

    extension AppDelegate {
        /// Observes the Darwin notifications `WidgetSharedStore.requestNewPad` and
        /// `requestOpenPad` post, so a widget / Control Center / Shortcuts request is
        /// drained even when the app is already frontmost, a case where no activation
        /// transition fires `applicationDidBecomeActive` (#485, #1046). Registered once
        /// for the app's lifetime. The C callback can't capture context, so it just hops
        /// to the main actor and calls the shared drain; the drain deletes each file, so
        /// a double fire with `applicationDidBecomeActive` is harmless (whichever loses
        /// finds the queue empty).
        func registerNewPadRequestObserver() {
            let notifications = [
                WidgetSharedStore.newPadRequestNotification,
                WidgetSharedStore.openPadRequestNotification
            ]
            for notification in notifications {
                CFNotificationCenterAddObserver(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    Unmanaged.passUnretained(self).toOpaque(),
                    { _, _, _, _, _ in
                        // `Self` here would capture the dynamic Self type, which a C function
                        // pointer can't form from — name the type explicitly.
                        // swiftlint:disable:next prefer_self_in_static_references
                        Task { @MainActor in AppDelegate.drainPendingWidgetRequests() }
                    },
                    notification as CFString,
                    nil,
                    .deliverImmediately
                )
            }
        }

        /// The `applicationDidBecomeActive` entry point (cold launch and
        /// background→foreground); kept under its historical name for that call site.
        /// Now also drains Shortcuts Open Pad requests, which previously sat orphaned
        /// on disk forever because only iPadOS consumed them (#1046).
        @MainActor
        static func drainPendingNewPad() {
            drainPendingWidgetRequests()
        }

        /// Performs every pending widget / Control Center / Shortcuts request and clears
        /// it, replaying both kinds in the order the user issued them so the most recent
        /// action ends up on top (#1045). Shared by `applicationDidBecomeActive` and the
        /// Darwin observer (already-frontmost requests, #485); whichever activation path
        /// runs second simply finds the queue empty.
        @MainActor
        static func drainPendingWidgetRequests() {
            for pending in WidgetSharedStore.takePendingRequestsInOrder() {
                switch pending {
                case let .newPad(request):
                    createPadInBrowser(account: request.account, question: request.question)

                case let .openPad(request):
                    showPad(request)
                }
            }
        }

        /// Routes a Shortcuts "Open Pad" request: switches to the request's account when
        /// it is still configured, then selects the pad in the Pads list: the same
        /// semantics as the iPad drain (`drainPendingWidgetRequests` in
        /// coderpadApp+iOSScenes.swift), so the intent behaves identically everywhere.
        @MainActor
        private static func showPad(_ request: WidgetOpenPadRequest) {
            if let account = request.account,
               let uuid = UUID(uuidString: account),
               AccountsStore.shared.accounts.contains(where: { $0.id == uuid }) {
                AccountsStore.shared.showAllAccounts = false
                AccountsStore.shared.currentAccountID = uuid
            }
            AppNavigation.shared.showPads(PadsRequest(selectPadID: request.id))
        }

        /// Creates a pad through the API and opens it in the user's browser — the same
        /// behavior as the menu-bar extra's New Pad. The work runs here, in the app,
        /// rather than in the extension's `CreatePadIntent`, because only the app has the
        /// API client, the account's keychained key, and the network entitlement. When
        /// there's no usable account or the request fails, it falls back to opening the
        /// in-app create flow so a tap is never silently lost.
        @MainActor
        static func createPadInBrowser(account: String?, question: Int?) {
            let store = AccountsStore.shared
            let route = AppNavigation.resolveNewPadRoute(
                account: account,
                seedQuestionID: question,
                availableAccountIDs: store.accounts.map(\.id)
            )
            let resolved = route.accountID.flatMap { id in
                store.accounts.first { $0.id == id }
            } ?? store.currentAccount

            guard let account = resolved else {
                // No account configured yet — open the app so the user can add one.
                routeNewPadViaDeepLink(account: nil, question: route.seedQuestionID)
                return
            }

            // `question_id` alone seeds the pad from the favourite question; a nil id makes a
            // blank pad. Mirrors `MenuBarView`'s `createPad`.
            var body = PadCreate()
            body.questionID = route.seedQuestionID

            let client = account.makeClient()
            let accountID = account.id
            let fallbackBase = account.resolvedBaseURL
            Task { @MainActor in
                do {
                    let pad = try await client.createPad(body)
                    // Fall back to the canonical {base}/{id} address when the response's
                    // url is absent/malformed, so the created pad is never lost (#781).
                    openCreatedPad(pad.webURL(fallbackBase: fallbackBase))
                } catch {
                    // Offline or a transient API error: surface the in-app create flow so the
                    // user can retry, rather than failing silently.
                    routeNewPadViaDeepLink(account: accountID.uuidString, question: route.seedQuestionID)
                }
            }
        }

        /// Opens a newly-created pad in the user's configured browser.
        @MainActor
        static func openCreatedPad(_ url: URL) {
            BrowserSettings.openExternally(url)
        }

        /// Recovery path for `createPadInBrowser`: opens the app's own `coderpad://new-pad`
        /// deep link through LaunchServices, which surfaces the main window (the create sheet
        /// can't render windowless) and routes via `handleDeepLink` → `routeNewPad`.
        @MainActor
        static func routeNewPadViaDeepLink(account: String?, question: Int?) {
            var components = URLComponents()
            components.scheme = "coderpad"
            components.host = "new-pad"
            let items = [
                account.map { URLQueryItem(name: "account", value: $0) },
                question.map { URLQueryItem(name: "question", value: String($0)) }
            ].compactMap(\.self)
            if !items.isEmpty { components.queryItems = items }

            AppActivator.bringToFront()
            URLOpener.open(components.url ?? URL.staticURL("coderpad://new-pad"))
        }
    }
#endif
