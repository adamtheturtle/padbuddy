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

        static func createPadKey(_ body: PadCreate, account: Account) -> String {
            let seed = body.questionID.map { "question:\($0)" } ?? "blank"
            return "\(account.id.uuidString):\(seed)"
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

        /// Opens a row's pad in the user's configured browser, resolving the URL via
        /// the row's own account base when the pad's `url` field is absent or
        /// malformed, so self-hosted/regional pads still open (#1010).
        func openPad(_ row: MenuBarPadRow) {
            openPadURL(row.pad.webURL(fallbackBase: row.account.resolvedBaseURL))
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

        func isCreatingPad(_ body: PadCreate, account: Account) -> Bool {
            creatingPadKeys.contains(Self.createPadKey(body, account: account))
        }

        func createPad(_ body: PadCreate, account: Account) async {
            let createKey = Self.createPadKey(body, account: account)
            guard !creatingPadKeys.contains(createKey) else { return }

            creatingPadKeys.insert(createKey)
            defer { creatingPadKeys.remove(createKey) }

            let client = account.makeClient()
            do {
                let pad = try await client.createPad(body)
                // Fall back to the canonical {base}/{id} address when the response's
                // url is absent/malformed, so the created pad is never lost (#781).
                openPadURL(pad.webURL(fallbackBase: account.resolvedBaseURL))
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
            // Use the same "updated_at,desc" sort as every other loader writing into
            // these shared caches (background refresher, list views): a different sort
            // would re-order the shared cache and make a subsequent list view re-sort
            // or refetch (#370).
            async let padsTask = capture { try await client.listPads(sort: "updated_at,desc") }
            async let questionsTask = capture { try await client.listQuestions(sort: "updated_at,desc") }
            let (padsResult, questionsResult) = await (padsTask, questionsTask)
            guard generation == loadGeneration else { return nil }

            var errors: [String] = []
            switch padsResult {
            case let .success(pads):
                PadsCacheStore.shared.set(account.id, pads: pads, via: client)
            case let .failure(error):
                errors.append("Pads: \(error.localizedDescription)")
            }
            switch questionsResult {
            case let .success(questions):
                QuestionsCacheStore.shared.set(account.id, questions: questions, via: client)
            case let .failure(error):
                errors.append("Questions: \(error.localizedDescription)")
            }

            guard !errors.isEmpty else { return nil }

            return "\(account.name): \(errors.joined(separator: "; "))"
        }

        private func capture<Value>(_ operation: () async throws -> Value) async -> Result<Value, any Error> {
            do {
                let value = try await operation()
                return .success(value)
            } catch {
                return .failure(error)
            }
        }
    }
#endif
