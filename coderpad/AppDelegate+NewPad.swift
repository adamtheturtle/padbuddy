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
    /// Observes the Darwin notification `WidgetSharedStore.requestNewPad` posts, so a
    /// widget / Control Center New Pad tap is drained even when the app is already
    /// frontmost — a case where no activation transition fires
    /// `applicationDidBecomeActive` (#485). Registered once for the app's lifetime. The C
    /// callback can't capture context, so it just hops to the main actor and calls the
    /// shared drain; `takePendingNewPad` deletes the file, so a double fire with
    /// `applicationDidBecomeActive` is harmless (whichever loses gets nil).
    func registerNewPadRequestObserver() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, _, _, _, _ in
                // `Self` here would capture the dynamic Self type, which a C function
                // pointer can't form from — name the type explicitly.
                // swiftlint:disable:next prefer_self_in_static_references
                Task { @MainActor in AppDelegate.drainPendingNewPad() }
            },
            WidgetSharedStore.newPadRequestNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// Performs any pending widget / Control Center New Pad request and clears it. Shared
    /// by `applicationDidBecomeActive` (cold launch / background→foreground) and the Darwin
    /// observer (already-frontmost taps, #485). Idempotent: `takePendingNewPad` removes the
    /// request file, so whichever path runs first wins and the other no-ops.
    @MainActor
    static func drainPendingNewPad() {
        guard let request = WidgetSharedStore.takePendingNewPad() else { return }

        createPadInBrowser(account: request.account, question: request.question)
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
        let resolved: Account? = {
            if let account, let uuid = UUID(uuidString: account),
               let match = store.accounts.first(where: { $0.id == uuid }) {
                return match
            }
            return store.currentAccount
        }()

        guard let account = resolved else {
            // No account configured yet — open the app so the user can add one.
            routeNewPadViaDeepLink(account: nil, question: question)
            return
        }

        // `question_id` alone seeds the pad from the favourite question; a nil id makes a
        // blank pad. Mirrors `MenuBarView`'s `createPad`.
        var body = PadCreate()
        body.questionID = question

        let client = account.makeClient()
        let accountID = account.id
        Task { @MainActor in
            do {
                let pad = try await client.createPad(body)
                if let url = pad.webURL {
                    openCreatedPad(url)
                }
            } catch {
                // Offline or a transient API error: surface the in-app create flow so the
                // user can retry, rather than failing silently.
                routeNewPadViaDeepLink(account: accountID.uuidString, question: question)
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
