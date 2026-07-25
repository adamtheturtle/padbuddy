#if os(macOS)
//
    //  MenuBarView+Logic.swift
    //  coderpad
//

    import AppKit
    import CryptoKit
    import SwiftUI

    extension MenuBarView {
        static func canCreatePad(account: Account, isOffline: Bool) -> Bool {
            AppCreationAvailability.canCreate(account: account, isOffline: isOffline)
        }

        static func createPadKey(_ body: PadCreate, account: Account) -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let encoded = (try? encoder.encode(body)) ?? Data()
            let digest = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
            return "\(account.id.uuidString):\(digest)"
        }

        /// Sort cached pads/questions into `listCache`. Mirrors the list views' memo
        /// pattern; called at the top of `accountMenu` before any reader touches menu
        /// data (#370/#674).
        ///
        /// Keyed to a cheap signature rather than "once per render": `body` re-runs on
        /// every state change while the menu is open, and the O(n log n) sorts fan in
        /// every account's full cache when merged, so they rebuilt from scratch each
        /// pass even though the caches had not been written (#2112).
        func refreshLists() {
            let accounts = store.isMergedView ? store.mergeableAccounts : store.currentAccount.map { [$0] } ?? []
            let signature = listSignature(accounts: accounts)
            guard listCache.signature != signature else { return }

            listCache.signature = signature
            guard !accounts.isEmpty else {
                listCache.padRows = []
                listCache.questionRows = []
                listCache.myOwnedPads = []
                return
            }

            let padRows = accounts.flatMap { account in
                padsCache.get(account.id).map { MenuBarPadRow(account: account, pad: $0) }
            }
            listCache.padRows = padRows.sorted {
                ($0.pad.updatedAt ?? .distantPast) > ($1.pad.updatedAt ?? .distantPast)
            }

            let questionRows = accounts.flatMap { account in
                questionsCache.get(account.id).map { MenuBarQuestionRow(account: account, question: $0) }
            }
            listCache.questionRows = questionRows
                .sorted { ($0.question.updatedAt ?? .distantPast) > ($1.question.updatedAt ?? .distantPast) }
            listCache.myOwnedPads = computeMyOwnedPads()
        }

        /// A signature of everything the memoized rows depend on: which accounts are in
        /// view, the name and user email each row renders and resolves ownership
        /// against (so a rename or a newly configured email rebuilds), and each cache's
        /// write generation. The generation stands in for the cached items themselves,
        /// so the check stays O(accounts) rather than hashing every pad and question —
        /// the same trade the merged list views make (#1234). The counts cover the one
        /// population that doesn't bump a generation: `get`'s synchronous disk fallback.
        func listSignature(accounts: [Account]) -> Int {
            var hasher = Hasher()
            hasher.combine(store.isMergedView)
            for account in accounts {
                hasher.combine(account.id)
                hasher.combine(account.name)
                hasher.combine(account.userEmail)
                hasher.combine(padsCache.writeGeneration[account.id] ?? 0)
                hasher.combine(questionsCache.writeGeneration[account.id] ?? 0)
                hasher.combine(padsCache.cached(account.id).count)
                hasher.combine(questionsCache.cached(account.id).count)
            }
            return hasher.finalize()
        }

        func padLabel(_ pad: Pad) -> String {
            let title = pad.title.isEmpty ? pad.id : pad.title
            let language = pad.language.flatMap { $0.isEmpty ? nil : " · \($0.coderPadLanguageDisplayName)" } ?? ""
            return Self.safeMenuLabel("\(title)\(language)", fallback: pad.id)
        }

        func padRowLabel(_ row: MenuBarPadRow) -> String {
            let label = padLabel(row.pad)
            let combined = store.isMergedView ? "\(label) · \(row.account.name)" : label
            return Self.safeMenuLabel(combined, fallback: row.pad.id)
        }

        func questionRowLabel(_ row: MenuBarQuestionRow) -> String {
            let title = row.question.title.isEmpty ? "#\(row.question.id)" : row.question.title
            let combined = store.isMergedView ? "\(title) · \(row.account.name)" : title
            return Self.safeMenuLabel(combined, fallback: "#\(row.question.id)")
        }

        static func safeMenuLabel(_ value: String, fallback: String) -> String {
            let normalized = value
                .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.controlCharacters))
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return String((normalized.isEmpty ? fallback : normalized).prefix(160))
        }

        static func menuErrorMessage(_ value: String) -> String {
            let maxLines = 2
            let maxLineLength = 82
            let lines = value
                .components(separatedBy: .newlines)
                .map { safeMenuLabel($0, fallback: "Refresh failed") }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { return "Refresh failed" }

            var visible = Array(lines.prefix(maxLines))
            if lines.count > maxLines {
                let suffix = " (+\(lines.count - maxLines) more)"
                visible[maxLines - 1] = String(visible[maxLines - 1].prefix(max(0, maxLineLength - suffix.count))) + suffix
            }

            return visible.map { line in
                line.count > maxLineLength ? String(line.prefix(maxLineLength - 1)) + "…" : line
            }.joined(separator: "\n")
        }

        /// Pads owned by each row's source account. In merged mode ownership is resolved
        /// per account, matching `MergedPadsView.isMine`. An account without a configured
        /// identity cannot safely identify any pad as the user's (#1493).
        private var myOwnedPads: [MenuBarPadRow] {
            listCache.myOwnedPads
        }

        /// Resolves the ownership filter. Called once per render by `refreshLists()`;
        /// readers go through `myOwnedPads` (#2465).
        func computeMyOwnedPads() -> [MenuBarPadRow] {
            if store.isMergedView {
                return padRows.filter { $0.account.owns($0.pad.ownerEmail) }
            }
            guard let account = store.currentAccount, Self.hasConfiguredOwnershipIdentity(account) else { return [] }

            return padRows.filter { $0.account.owns($0.pad.ownerEmail) }
        }

        static func hasConfiguredOwnershipIdentity(_ account: Account) -> Bool {
            !account.userEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        func openPadURL(_ url: URL?) {
            guard let url else { return }

            BrowserSettings.openExternally(url)
        }

        /// Questions for the "New Pad from Question" submenu, with favorites floated to
        /// the top (keeping the underlying most-recently-updated order within each
        /// group) so the user's starred questions lead the one-click pad list.
        func questionsForMenu() -> [MenuBarQuestionRow] {
            let starred = favoriteQuestionIDs()
            var favored: [MenuBarQuestionRow] = []
            var rest: [MenuBarQuestionRow] = []
            // One pass, and each membership test is an O(1) Set lookup. Two filters,
            // each calling `favorites.favorites(account:)` per row, rebuilt a fresh
            // array and scanned it for every row — twice (#2472).
            for row in questionRows {
                if starred[row.account.id]?.contains(row.question.id) == true {
                    favored.append(row)
                } else {
                    rest.append(row)
                }
            }
            return favored + rest
        }

        /// The starred question ids per account, built once so the menu's rows can test
        /// membership without rebuilding an array each time (#2472, #2473).
        func favoriteQuestionIDs() -> [UUID: Set<Int>] {
            var starred: [UUID: Set<Int>] = [:]
            for row in questionRows where starred[row.account.id] == nil {
                starred[row.account.id] = Set(favorites.favorites(account: row.account.id))
            }
            return starred
        }

        func isCreatingPad(_ body: PadCreate, account: Account) -> Bool {
            creatingPadKeys.contains(Self.createPadKey(body, account: account))
        }

        /// Clears state whose meaning is scoped to the current account set. Bumping
        /// both generations also prevents an older load/create task from publishing
        /// after an account switch (#1496).
        func resetTransientState() {
            transientGeneration += 1
            loadGeneration += 1
            creatingPadKeys.removeAll()
            errorMessage = nil
            isLoading = false
            freshPadAccounts.removeAll()
            listCache = MenuBarListCache()
        }

        func createPad(_ body: PadCreate, account: Account) async {
            let createKey = Self.createPadKey(body, account: account)
            guard !creatingPadKeys.contains(createKey) else { return }

            let generation = transientGeneration
            creatingPadKeys.insert(createKey)
            defer {
                if generation == transientGeneration { creatingPadKeys.remove(createKey) }
            }

            do {
                let context = MenuBarCreateContext(account: account)
                guard let current = context.resolve(in: store.accounts) else {
                    throw MenuBarCreateError.accountChanged
                }

                try await performCreate(body, account: current, context: context)
            } catch {
                if generation == transientGeneration { errorMessage = error.localizedDescription }
            }
        }

        /// Re-fetches a cache-backed question immediately before using it as a pad
        /// seed, so menu-bar actions cannot create from a deleted or stale record.
        func createPad(from row: MenuBarQuestionRow) async {
            let staleBody = PadCreate.fromQuestion(row.question)
            let createKey = Self.createPadKey(staleBody, account: row.account)
            guard !creatingPadKeys.contains(createKey) else { return }

            let generation = transientGeneration
            creatingPadKeys.insert(createKey)
            defer {
                if generation == transientGeneration { creatingPadKeys.remove(createKey) }
            }
            do {
                let context = MenuBarCreateContext(account: row.account)
                guard let current = context.resolve(in: store.accounts) else {
                    throw MenuBarCreateError.accountChanged
                }

                let client = current.makeClient()
                let fetched = try await client.getQuestion(id: row.question.id)
                guard context.resolve(in: store.accounts) != nil else {
                    throw MenuBarCreateError.accountChanged
                }
                guard let fresh = NewPadFromQuestionValidation.accept(requestedID: row.question.id,
                                                                      fetched: fetched) else {
                    throw CoderPadError.decode("The selected question is no longer available.")
                }

                QuestionsCacheStore.shared.updateQuestion(fresh, account: current.id, via: client)
                try await performCreate(.fromQuestion(fresh), account: current, context: context, client: client)
            } catch {
                if generation == transientGeneration { errorMessage = error.localizedDescription }
            }
        }

        private func performCreate(_ body: PadCreate, account: Account, context: MenuBarCreateContext,
                                   client: CoderPadClient? = nil) async throws {
            let client = client ?? account.makeClient()
            guard context.resolve(in: store.accounts) != nil else { throw MenuBarCreateError.accountChanged }

            let pad = try await client.createPad(body)
            guard context.resolve(in: store.accounts) != nil else { throw MenuBarCreateError.accountChanged }

            // Publish the created pad to the shared cache (Spotlight, widget,
            // Dock badge) and to every mounted list (#1251).
            PadsCacheStore.shared.insertPad(pad, account: account.id, via: client)
            AppRouter.padCreated(pad, account: account.id)
            openPadURL(pad.webURL(fallbackBase: account.resolvedBaseURL))
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
            let padLoad = PadsCacheStore.shared.beginLoad(account.id, via: client)
            let questionLoad = QuestionsCacheStore.shared.beginLoad(account.id, via: client)
            // Use the same "updated_at,desc" sort as every other loader writing into
            // these shared caches (background refresher, list views): a different sort
            // would re-order the shared cache and make a subsequent list view re-sort
            // or refetch (#370).
            async let padsTask = capture {
                try await APIReadCoordinator.shared.pads(accountID: account.id, client: client)
            }
            async let questionsTask = capture {
                try await APIReadCoordinator.shared.questions(accountID: account.id, client: client)
            }
            let (padsResult, questionsResult) = await (padsTask, questionsTask)
            guard generation == loadGeneration else { return nil }

            var errors: [String] = []
            switch padsResult {
            case let .success(pads):
                if let padLoad {
                    PadsCacheStore.shared.set(account.id, pads: pads, via: client, accepting: padLoad)
                    freshPadAccounts.insert(account.id)
                }

            case let .failure(error):
                errors.append("Pads: \(error.localizedDescription)")
            }
            switch questionsResult {
            case let .success(questions):
                if let questionLoad {
                    QuestionsCacheStore.shared.set(
                        account.id, questions: questions, via: client, accepting: questionLoad
                    )
                }

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
