import AppGroupMailbox
import Foundation
import os

extension DeletionCleanup {
    private static let outboxLogger = Logger(subsystem: "com.coderpad.app", category: "deletion-outbox")
    private static var drainTask: Task<Void, Never>?
    private static let outbox: DeletionOutbox? = {
        let root = padBuddyUsesInMemoryAccounts
            ? FileManager.default.temporaryDirectory.appending(path: "PadBuddy-deletions-\(UUID())")
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "com.coderpad.app")
        return root.flatMap { try? DeletionOutbox(root: $0) }
    }()

    static func enqueue(_ deletion: PadDeletion) {
        let work = DeletionWork(kind: .pad, recordID: deletion.id,
                                account: deletion.account, identity: deletion.clientIdentity)
        persist(work) { cleanUpDeletedPad(deletion) }
    }

    static func enqueue(_ deletion: QuestionDeletion) {
        let work = DeletionWork(kind: .question, recordID: String(deletion.id),
                                account: deletion.account, identity: deletion.clientIdentity)
        persist(work) { cleanUpDeletedQuestion(deletion) }
    }

    private static func persist(_ work: DeletionWork, fallback: () -> Void) {
        do {
            guard let outbox else { throw CocoaError(.fileWriteUnknown) }

            try outbox.enqueue(work)
            start()
        } catch {
            // Capacity or disk failure applies cleanup inline, providing backpressure
            // without dropping an older durable record or growing a fallback queue.
            outboxLogger.error("Deletion outbox unavailable; applying cleanup inline")
            fallback()
        }
    }

    static func start() {
        guard drainTask == nil, let outbox else { return }

        drainTask = Task {
            defer { drainTask = nil }
            while !Task.isCancelled {
                do {
                    guard let claim = try outbox.mailbox.claimPending(limit: 1).first else { return }

                    let lease = Task {
                        while !Task.isCancelled {
                            do {
                                try await Task.sleep(for: .seconds(20))
                                try claim.renew()
                            } catch { return }
                        }
                    }
                    await apply(claim.message)
                    lease.cancel()
                    do {
                        try claim.acknowledge()
                    } catch {
                        try? claim.release()
                        throw error
                    }
                } catch {
                    outboxLogger.error("Deletion cleanup will retry its durable record")
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
        }
    }

    private static func apply(_ work: DeletionWork) async {
        let accounts = AccountsStore.shared.accounts
        let identity: ClientTaskIdentity
        if let owner = work.account {
            if let account = accounts.first(where: { $0.id == owner }) {
                identity = account.makeClient().taskIdentity
                guard DeletionWork.fingerprint(identity) == work.clientFingerprint else { return }
            } else {
                // Account teardown owns all of its old client-scoped detail state.
                identity = ClientTaskIdentity(apiKey: "", baseURL: work.baseURL)
            }
        } else {
            guard let matching = accounts.first(where: {
                DeletionWork.fingerprint($0.makeClient().taskIdentity) == work.clientFingerprint
            }) else { return }

            identity = matching.makeClient().taskIdentity
            await waitForCaches(work, accounts: accounts)
        }
        switch work.kind {
        case .pad:
            guard let id = PadIDValidation.normalize(work.recordID) else { return }

            cleanUpDeletedPad(PadDeletion(id: id, account: work.account, clientIdentity: identity))
            await PadsCacheStore.shared.waitForPersistence()

        case .question:
            guard let id = Int(work.recordID), id > 0 else { return }

            cleanUpDeletedQuestion(QuestionDeletion(id: id, account: work.account, clientIdentity: identity))
            await QuestionsCacheStore.shared.waitForPersistence()
        }
    }

    private static func waitForCaches(_ work: DeletionWork, accounts: [Account]) async {
        for account in accounts {
            if work.kind == .pad {
                PadsCacheStore.shared.prewarm(account.id)
            } else {
                QuestionsCacheStore.shared.prewarm(account.id)
            }
        }
        while accounts.contains(where: {
            work.kind == .pad ? PadsCacheStore.shared.isPrewarming($0.id)
                : QuestionsCacheStore.shared.isPrewarming($0.id)
        }) {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
    }
}
