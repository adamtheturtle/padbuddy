#if os(macOS)
//
    //  MenuBarView+Loading.swift
    //  coderpad
//
    //  Fetching the menu bar's pads and questions, for one account or across all.
//

    import SwiftUI

    extension MenuBarView {
        func load(account: Account, generation: Int) async {
            isLoading = true
            errorMessage = nil
            let failure = await loadData(for: account, generation: generation)
            guard generation == loadGeneration else { return }

            errorMessage = failure.map(\.displayText)
            isLoading = false
        }

        /// How many accounts the menu fetches at once. Matches the background refresher's
        /// bound so opening the menu cannot swamp the API any harder than a refresh does.
        static let maximumConcurrentMenuFetches = 3

        func loadMergedAccounts(generation: Int) async {
            isLoading = true
            errorMessage = nil

            // Concurrent across accounts, bounded. Awaiting each account in turn made
            // opening the menu in All Accounts mode take the *sum* of every account's
            // round trip rather than the maximum, with the loading state showing
            // throughout — and one slow or timing-out account blocked every later one
            // (#4750). `PadsBackgroundRefresher.refreshAllAccounts` already works this way.
            let accounts = store.mergeableAccounts
            var failures: [MenuLoadFailure] = []
            await withTaskGroup(of: MenuLoadFailure?.self) { group in
                var next = 0
                func addTask() {
                    guard next < accounts.count else { return }

                    let account = accounts[next]
                    next += 1
                    group.addTask { await loadData(for: account, generation: generation) }
                }
                for _ in 0 ..< min(Self.maximumConcurrentMenuFetches, accounts.count) {
                    addTask()
                }
                while let failure = await group.next() {
                    if let failure {
                        failures.append(failure)
                    }
                    addTask()
                }
            }
            guard generation == loadGeneration else { return }

            // Reported in the accounts' configured order, so the message does not depend
            // on which request happened to finish first.
            let order = Dictionary(
                accounts.enumerated().map { ($0.element.name, $0.offset) }
            ) { first, _ in first }
            failures.sort {
                (order[$0.accountName] ?? 0, $0.accountName) < (order[$1.accountName] ?? 0, $1.accountName)
            }

            errorMessage = Self.menuLoadFailureMessage(failures)
            isLoading = false
        }

        private func loadData(for account: Account, generation: Int) async -> MenuLoadFailure? {
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

            var reasons: [String] = []
            switch padsResult {
            case let .success(pads):
                if let padLoad {
                    PadsCacheStore.shared.set(account.id, pads: pads, via: client, accepting: padLoad)
                    freshPadAccounts.insert(account.id)
                }

            case let .failure(error):
                reasons.append(Self.menuLoadFailureReason(for: error))
            }
            switch questionsResult {
            case let .success(questions):
                if let questionLoad {
                    QuestionsCacheStore.shared.set(
                        account.id, questions: questions, via: client, accepting: questionLoad
                    )
                }

            case let .failure(error):
                reasons.append(Self.menuLoadFailureReason(for: error))
            }

            let uniqueReasons = Array(Set(reasons)).sorted()
            guard !uniqueReasons.isEmpty else { return nil }

            return MenuLoadFailure(accountName: account.name, reason: uniqueReasons.joined(separator: ", "))
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
