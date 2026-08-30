//
//  QuestionDetailView+CommitQueues.swift
//  coderpad
//
//  Serialization for the question detail view's inline saves: per-field metadata
//  commits are queued so rapid control churn sends one trailing PUT, and every
//  long-form content save — description, solution, and the whole-array
//  candidate-instruction writes — is chained per question so parallel edits can't
//  interleave their read-modify-publish steps. Split from QuestionDetailView+Edit.
//

import Foundation

enum QuestionInlineCommitField: String {
    case language
    case type
}

@MainActor
enum QuestionCommitIdentity {
    static func isCurrent(
        accountID: UUID?, clientIdentity: ClientTaskIdentity, accounts: [Account]
    ) -> Bool {
        // Standalone previews and tests intentionally have no stored account. A real
        // question route carries its account ID, which must still resolve to the same
        // credentials before queued work may start.
        guard let accountID else { return true }

        return accounts.first(where: { $0.id == accountID })?.makeClient().taskIdentity == clientIdentity
    }
}

@MainActor
enum QuestionInlineCommitQueue {
    private static var running: [String: Task<Void, Never>] = [:]
    private static var pending: [String: @MainActor () async -> Void] = [:]

    /// Serializes saves per account + question + field. The key carries the owning
    /// account: per-org question ids collide across accounts, so a process-global
    /// numeric key made unrelated accounts' saves wait on each other and retained
    /// the other window's state (#1183). While a save is in flight only the newest
    /// queued value is kept, so rapid Picker churn sends at most one trailing PUT
    /// with the final choice instead of replaying every intermediate value (#1185).
    /// Entries are removed as their work drains, so completed tasks and their
    /// captured views aren't retained for the life of the process (#1184).
    static func enqueue(account: UUID?,
                        client: CoderPadClient,
                        questionID: Int,
                        field: QuestionInlineCommitField,
                        operation: @escaping @MainActor () async -> Void) {
        let key = "\(account?.uuidString ?? "current"):\(questionID):\(field.rawValue)"
        // Bind the queued work to the credentials it was created under: a save
        // queued behind an in-flight one can start after its account is removed
        // or re-keyed, and firing it then would PUT through retired credentials
        // and publish the result into stale state (#2652). Mock/test clients
        // match no stored account (nil) and stay allowed while that holds.
        let enqueuedIdentity = client.taskIdentity
        let guarded: @MainActor () async -> Void = {
            guard QuestionCommitIdentity.isCurrent(
                accountID: account, clientIdentity: enqueuedIdentity,
                accounts: AccountsStore.shared.accounts
            ) else { return }

            await operation()
        }
        guard running[key] == nil else {
            pending[key] = guarded
            return
        }

        run(key: key, operation: guarded)
    }

    private static func run(key: String, operation: @escaping @MainActor () async -> Void) {
        running[key] = Task { @MainActor in
            await operation()
            running[key] = nil
            if let next = pending.removeValue(forKey: key) {
                run(key: key, operation: next)
            }
        }
    }
}

/// Serializes long-form content saves per account + question.
///
/// Candidate-instruction saves resend the entire instruction list, so two
/// concurrent part edits would each PUT an array holding the other part's old
/// text and the later one would win (#1188). Description and solution saves are
/// single-field, but they share the same read-modify-publish shape — read the
/// question, build a payload, publish the result — and interleaving those let a
/// later publish drop an earlier edit from the merge base (#2649). One chain per
/// question makes each save atomic with respect to the others. Entries are
/// removed when a chain drains.
@MainActor
enum QuestionContentSaveChain {
    private static var tails: [String: Task<Void, Never>] = [:]

    static func run(key: String, operation: @escaping @MainActor () async -> Bool) async -> Bool {
        let previous = tails[key]
        let task = Task { @MainActor () -> Bool in
            await previous?.value
            // The caller can go away while this waits its turn behind an earlier save —
            // the view disappears, the question changes. Running the save anyway wrote a
            // change nobody was waiting for and reported its result to nothing (#4596).
            guard !Task.isCancelled else { return false }

            return await operation()
        }
        let tail = Task { @MainActor in _ = await task.value }
        tails[key] = tail
        // Unstructured tasks do not inherit the caller's cancellation, so it is forwarded
        // explicitly. The chain itself keeps draining: later entries still run in order.
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if tails[key] == tail {
            tails[key] = nil
        }
        return result
    }
}
