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
    import os

    /// The tail of the serial widget-request drain chain: each drain awaits the one
    /// before it, so queued requests replay strictly in the order the user issued
    /// them and their pad creates run one at a time instead of as a burst of
    /// detached tasks (#1253, #1254).
    @MainActor
    private enum WidgetRequestDrain {
        static var tail: Task<Void, Never>?
    }

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
        /// runs second simply finds the queue empty. Each drain chains onto the previous
        /// one and awaits every create, so queued creates run serially in request order
        /// rather than as concurrent detached tasks (#1253), and a drain that races a
        /// Darwin re-delivery takes the queue only after the prior batch fully finished
        /// (#1254).
        @MainActor
        static func drainPendingWidgetRequests() {
            let previous = WidgetRequestDrain.tail
            WidgetRequestDrain.tail = Task { @MainActor in
                await previous?.value
                // A double-delivered intent can record identical requests back to
                // back; within one batch a repeated identical New Pad request is a
                // duplicate delivery, not a second tap — one tap makes one pad (#1254).
                var startedCreates = Set<String>()
                for pending in WidgetSharedStore.takePendingRequestsInOrder() {
                    switch pending {
                    case let .newPad(request):
                        let key = "\(request.account ?? "")|\(request.question.map(String.init) ?? "")"
                        guard startedCreates.insert(key).inserted else { continue }

                        await createPadInBrowser(account: request.account, question: request.question)

                    case let .openPad(request):
                        showPad(request)
                    }
                }
            }
        }

        /// Routes a Shortcuts "Open Pad" request: switches to the request's account when
        /// it is still configured, then selects the pad in the Pads list: the same
        /// semantics as the iPad drain (`drainPendingWidgetRequests` in
        /// coderpadApp+iOSScenes.swift), so the intent behaves identically everywhere.
        /// The validated account travels with the navigation request: the request can
        /// outlive further view/account switches, and a bare pad id must not resolve
        /// under a different account (#1255).
        @MainActor
        private static func showPad(_ request: WidgetOpenPadRequest) {
            // The request file is cross-process App Group data: a malformed id
            // must not become a misleading pending selection request (#1809).
            guard let padID = PadIDValidation.normalize(request.id) else { return }

            var owner: UUID?
            if let account = request.account,
               let uuid = UUID(uuidString: account),
               AccountsStore.shared.accounts.contains(where: { $0.id == uuid }) {
                AccountsStore.shared.showAllAccounts = false
                AccountsStore.shared.currentAccountID = uuid
                owner = uuid
            }
            AppNavigation.shared.showPads(PadsRequest(selectPadID: padID, selectPadAccountID: owner))
        }

        /// Creates a pad through the API and opens it in the user's browser — the same
        /// behavior as the menu-bar extra's New Pad. The work runs here, in the app,
        /// rather than in the extension's `CreatePadIntent`, because only the app has the
        /// API client, the account's keychained key, and the network entitlement. When
        /// there's no usable account or the request fails, it falls back to opening the
        /// in-app create flow so a tap is never silently lost.
        @MainActor
        static func createPadInBrowser(account: String?, question: Int?) async {
            let store = AccountsStore.shared
            let route = AppNavigation.resolveNewPadRoute(
                account: account,
                seedQuestionID: question,
                availableAccountIDs: store.accounts.map(\.id)
            )
            let resolved: Account?
            if let routedID = route.accountID {
                resolved = store.accounts.first { $0.id == routedID }
            } else if let requested = account, !requested.isEmpty {
                // The widget named an account that is no longer configured:
                // creating in whichever account happens to be current could put
                // the pad in the wrong organization (#1811). Surface the in-app
                // create flow so the user picks the account explicitly.
                routeNewPadViaDeepLink(account: nil, question: nil)
                return
            } else {
                resolved = store.currentAccount
            }

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
            do {
                let pad = try await client.createPad(body)
                // Publish the created pad to the shared cache (Spotlight, widget, Dock
                // badge) and to every mounted list, so it doesn't stay invisible
                // in-app until the next full reload (#1251).
                PadsCacheStore.shared.insertPad(pad, account: accountID, via: client)
                AppRouter.padCreated(pad, account: accountID)
                // Fall back to the canonical {base}/{id} address when the response's
                // url is absent/malformed, so the created pad is never lost (#781).
                openCreatedPad(pad.webURL(fallbackBase: fallbackBase))
            } catch {
                // Offline or a transient API error: surface the in-app create flow so the
                // user can retry, rather than failing silently. Log why (privacy-safe:
                // the account id and error text, never the key) so a repeated fallback
                // - e.g. a revoked key - is diagnosable from Console (#688).
                persistenceLogger.warning(
                    """
                    Widget New Pad API create failed for account \
                    \(accountID.uuidString, privacy: .public); falling back to the in-app \
                    create sheet: \(error.localizedDescription, privacy: .public)
                    """
                )
                routeNewPadViaDeepLink(account: accountID.uuidString, question: route.seedQuestionID)
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
