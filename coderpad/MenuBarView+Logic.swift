#if os(macOS)
//
//  MenuBarView+Logic.swift
//  coderpad
//

import AppKit
import SwiftUI

extension MenuBarView {
    func padLabel(_ pad: Pad) -> String {
        let title = pad.title.isEmpty ? pad.id : pad.title
        let language = pad.language.flatMap { $0.isEmpty ? nil : " · \($0.coderPadLanguageDisplayName)" } ?? ""
        return "\(title)\(language)"
    }

    func padRowLabel(_ row: MenuBarPadRow) -> String {
        let label = padLabel(row.pad)
        return store.isMergedView ? "\(label) · \(row.account.name)" : label
    }

    func questionRowLabel(_ row: MenuBarQuestionRow) -> String {
        let title = row.question.title.isEmpty ? "#\(row.question.id)" : row.question.title
        return store.isMergedView ? "\(title) · \(row.account.name)" : title
    }

    /// Pads owned by each row's source account. In merged mode ownership is resolved
    /// per account, matching `MergedPadsView.isMine`; single-account mode keeps the
    /// previous fallback for accounts without a configured user email (#674).
    private var myOwnedPads: [MenuBarPadRow] {
        if store.isMergedView {
            return padRows.filter { $0.account.owns($0.pad.ownerEmail) }
        }
        guard let account = store.currentAccount else { return [] }
        if !account.userEmail.isEmpty {
            return padRows.filter { $0.account.owns($0.pad.ownerEmail) }
        }
        let owners = padRows
            .map(\.pad.ownerEmail)
            .filter { !$0.isEmpty }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        if let mine = owners.max(by: { $0.value < $1.value })?.key {
            return padRows.filter { $0.pad.ownerEmail == mine }
        }
        return padRows
    }

    /// The user's pads, optionally narrowed to active interviews when the user enables
    /// it in Settings.
    var myPads: [MenuBarPadRow] {
        startedOnly ? myOwnedPads.filter { $0.pad.status == .active } : myOwnedPads
    }

    /// The user's pads with a live session in progress right now (#593), newest first.
    /// Drawn from the same cached list the rest of the menu reads, so it costs nothing
    /// extra, and scoped to the signed-in user so the section surfaces the user's own
    /// in-progress interviews.
    var activePads: [MenuBarPadRow] {
        myOwnedPads.filter { $0.pad.status == .active }
    }

    /// Opens `pad` in the user's configured browser.
    func openPad(_ pad: Pad) {
        guard let url = pad.webURL else { return }

        openPadURL(url)
    }

    /// Opens a pad URL from the menu bar in the user's configured browser.
    func openPadURL(_ url: URL) {
        BrowserSettings.openExternally(url)
    }

    /// Questions for the "New Pad from Question" submenu, with favorites floated to
    /// the top (keeping the underlying most-recently-updated order within each
    /// group) so the user's starred questions lead the one-click pad list.
    func questionsForMenu() -> [MenuBarQuestionRow] {
        questionRows.filter { favorites.favorites(account: $0.account.id).contains($0.question.id) }
            + questionRows.filter { !favorites.favorites(account: $0.account.id).contains($0.question.id) }
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

    /// Opens the Settings window directly, without also opening the main window — a
    /// menu-bar "Settings…" click should surface only Settings, not the app window
    /// (#463). Activates the app first so the panel comes forward even when no
    /// window is currently visible.
    func openSettingsPanel() {
        AppActivator.bringToFront()
        openSettings()
    }

    func loadMenu(activeAccount: Account) async {
        if store.isMergedView {
            await loadMergedAccounts()
        } else {
            await load(account: activeAccount)
        }
    }

    func load(account: Account) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        errorMessage = await loadData(for: account)
    }

    private func loadMergedAccounts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var errors: [String] = []
        for account in store.mergeableAccounts {
            if let error = await loadData(for: account) {
                errors.append(error)
            }
        }
        if !errors.isEmpty {
            errorMessage = errors.joined(separator: "\n")
        }
    }

    @discardableResult
    private func loadData(for account: Account) async -> String? {
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
            return nil
        } catch {
            return "\(account.name): \(error.localizedDescription)"
        }
    }
}
#endif
