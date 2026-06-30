#if os(macOS)
//
//  MenuBarView+Logic.swift
//  coderpad
//

import AppKit
import SwiftUI

extension MenuBarView {
    /// Opens the main window and switches it to `section`. The section is durable
    /// navigation state, so this works whether or not the window is already open.
    func go(_ section: AppSection) {
        AppNavigation.shared.show(section)
        openMain()
    }

    func padLabel(_ pad: Pad) -> String {
        let title = pad.title.isEmpty ? pad.id : pad.title
        let language = pad.language.flatMap { $0.isEmpty ? nil : " · \($0.languageDisplayName)" } ?? ""
        return "\(title)\(language)"
    }

    /// Pads owned by the account's configured email, if the user set one in Settings.
    /// Otherwise falls back to the most-frequent owner email in the fetched list, since
    /// the CoderPad API doesn't tell us which user the key belongs to.
    private var myOwnedPads: [Pad] {
        if let mine = store.currentAccount?.userEmail, !mine.isEmpty {
            return pads.filter { $0.ownerEmail == mine }
        }
        let owners = pads
            .map(\.ownerEmail)
            .filter { !$0.isEmpty }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        if let mine = owners.max(by: { $0.value < $1.value })?.key {
            return pads.filter { $0.ownerEmail == mine }
        }
        return pads
    }

    /// The user's pads, optionally narrowed to active interviews when the user enables
    /// it in Settings.
    var myPads: [Pad] {
        startedOnly ? myOwnedPads.filter { $0.status == .active } : myOwnedPads
    }

    /// The user's pads with a live session in progress right now (#593), newest first.
    /// Drawn from the same cached list the rest of the menu reads, so it costs nothing
    /// extra, and scoped to the signed-in user so the section surfaces the user's own
    /// in-progress interviews.
    var activePads: [Pad] {
        myOwnedPads.filter { $0.status == .active }
    }

    /// Opens `pad` in the in-app browser window, bringing the app forward first so the
    /// window appears even from a windowless menu-bar-only state.
    func openPadBrowser(_ pad: Pad) {
        guard let url = pad.webURL else { return }

        openPadURL(url)
    }

    /// Opens a pad URL from the menu bar, honoring the app-wide browser preference.
    /// The in-app default avoids handing a newly-created pad to an unrelated system
    /// browser session, which may be signed into a different CoderPad account (#602).
    func openPadURL(_ url: URL) {
        if BrowserSettings.openLinksIn == .external {
            BrowserSettings.openExternally(url)
        } else {
            AppActivator.bringToFront()
            openWindow(id: "pad-browser", value: url)
        }
    }

    /// Questions for the "New Pad from Question" submenu, with favorites floated to
    /// the top (keeping the underlying most-recently-updated order within each
    /// group) so the user's starred questions lead the one-click pad list.
    func questionsForMenu(favoriteIDs: Set<Int>) -> [Question] {
        guard !favoriteIDs.isEmpty else { return questions }

        return questions.filter { favoriteIDs.contains($0.id) }
            + questions.filter { !favoriteIDs.contains($0.id) }
    }

    func createPad(_ body: PadCreate, account: Account) async {
        let client = account.makeClient()
        do {
            let pad = try await client.createPad(body)
            if let url = pad.webURL {
                openPadURL(url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openMain() {
        AppActivator.bringToFront()
        openWindow(id: "main")
    }

    /// Opens the Settings window directly, without also opening the main window — a
    /// menu-bar "Settings…" click should surface only Settings, not the app window
    /// (#463). Activates the app first so the panel comes forward even when no
    /// window is currently visible.
    func openSettingsPanel() {
        AppActivator.bringToFront()
        openSettings()
    }

    func load(account: Account) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let client = account.makeClient()
        do {
            // Use the same "updated_at,desc" sort as every other loader writing into
            // these shared caches (background refresher, list views): a different sort
            // would re-order the shared cache and make a subsequent list view re-sort
            // or refetch (#370).
            async let padsTask = client.listPads(sort: "updated_at,desc")
            async let qsTask = client.listQuestions(sort: "updated_at,desc")
            // Write fetched results straight into the shared caches (no clearing
            // first): the menu — and every other view reading these stores — keeps
            // showing the previous data until the fresh data lands, so switching
            // accounts shows the new account's cache rather than a blank "Loading…".
            let fetched = try await padsTask
            PadsCacheStore.shared.set(account.id, pads: fetched)
            if let fetchedQuestions = try? await qsTask {
                QuestionsCacheStore.shared.set(account.id, questions: fetchedQuestions)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
