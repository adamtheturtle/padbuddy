#if os(macOS)
//
    //  MenuBarView+Logic.swift
    //  coderpad
//

    import AppKit
    import SwiftUI

    extension MenuBarView {
        static func canCreatePad(account: Account, isOffline: Bool) -> Bool {
            !isOffline && (account.isMock || !account.apiKey.isEmpty)
        }

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
            // Claim a fresh generation: any refresh still in flight becomes stale and
            // stops publishing (#775).
            loadGeneration += 1
            let generation = loadGeneration
            if store.isMergedView {
                await loadMergedAccounts(generation: generation)
            } else {
                await load(account: activeAccount, generation: generation)
            }
        }

        private func load(account: Account, generation: Int) async {
            isLoading = true
            errorMessage = nil
            let error = await loadData(for: account, generation: generation)
            guard generation == loadGeneration else { return }

            errorMessage = error
            isLoading = false
        }

        private func loadMergedAccounts(generation: Int) async {
            isLoading = true
            errorMessage = nil

            var errors: [String] = []
            for account in store.mergeableAccounts {
                if let error = await loadData(for: account, generation: generation) {
                    errors.append(error)
                }
            }
            guard generation == loadGeneration else { return }

            if !errors.isEmpty {
                errorMessage = errors.joined(separator: "\n")
            }
            isLoading = false
        }

        private func loadData(for account: Account, generation: Int) async -> String? {
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
                // accounts shows the new account's cache rather than an initial fetch status.
                // A stale generation stops before each write so it can't overwrite a
                // newer refresh's data (#775).
                let fetched = try await padsTask
                guard generation == loadGeneration else { return nil }

                PadsCacheStore.shared.set(account.id, pads: fetched)
                // A Questions failure is a real partial failure, not something to
                // swallow: fall through to the shared catch so the menu reports it
                // instead of silently serving stale question actions (#774).
                let fetchedQuestions = try await qsTask
                guard generation == loadGeneration else { return nil }

                QuestionsCacheStore.shared.set(account.id, questions: fetchedQuestions)
                return nil
            } catch {
                return "\(account.name): \(error.localizedDescription)"
            }
        }
    }
#endif
