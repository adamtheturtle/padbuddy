//
//  AppDelegate+NewPad.swift
//  coderpad
//
//  The widget / Control Center "New Pad" path: create a pad through the API and open
//  it in the browser without surfacing the app window, falling back to the in-app
//  create flow when that isn't possible (#456, #485). Split out of the main app file
//  so it stays under the file-length budget.
//

import AppKit

extension AppDelegate {
    /// Creates a pad through the API and opens it in the browser — the same behavior as
    /// the menu-bar extra's New Pad — so the widget and Control Center buttons make a pad
    /// without surfacing the app's window (#485). The work runs here, in the app, rather
    /// than in the extension's `CreatePadIntent`, because only the app has the API client,
    /// the account's keychained key, and the network entitlement. When there's no usable
    /// account or the request fails, it falls back to opening the in-app create flow so a
    /// tap is never silently lost.
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
                    BrowserSettings.openExternally(url)
                }
            } catch {
                // Offline or a transient API error: surface the in-app create flow so the
                // user can retry, rather than failing silently.
                routeNewPadViaDeepLink(account: accountID.uuidString, question: question)
            }
        }
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

    /// Switches to the requested account (if any) and opens the Pads create sheet — the
    /// shared destination of the `coderpad://new-pad` deep link and the widget/Control
    /// Center New Pad button. An account is honoured only when it still exists; the
    /// seeded question id is only unique within its owning org, so the account switch
    /// must happen first.
    @MainActor
    static func routeNewPad(account: String?, question: Int?) {
        if let account, let uuid = UUID(uuidString: account),
           AccountsStore.shared.accounts.contains(where: { $0.id == uuid }) {
            AccountsStore.shared.showAllAccounts = false
            AccountsStore.shared.currentAccountID = uuid
        }
        AppNavigation.shared.showPads(PadsRequest(startCreating: true, seedQuestionID: question))
    }
}
