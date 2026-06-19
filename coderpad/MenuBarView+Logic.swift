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
    var myPads: [Pad] {
        let mineOnly: [Pad]
        if let mine = store.currentAccount?.userEmail, !mine.isEmpty {
            mineOnly = pads.filter { $0.ownerEmail == mine }
        } else {
            let owners = pads
                .map(\.ownerEmail)
                .filter { !$0.isEmpty }
                .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            if let mine = owners.max(by: { $0.value < $1.value })?.key {
                mineOnly = pads.filter { $0.ownerEmail == mine }
            } else {
                mineOnly = pads
            }
        }
        // Optionally narrow to active interviews when the user enables it in Settings.
        return startedOnly ? mineOnly.filter { $0.status == .active } : mineOnly
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
                BrowserSettings.openExternally(url)
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
