//
//  QuestionDetailView+CommitQueues.swift
//  coderpad
//
//  Serialization for the question detail view's inline saves: per-field metadata
//  commits are queued so rapid control churn sends one trailing PUT, and
//  whole-array candidate-instruction saves are chained so parallel part edits
//  can't overwrite each other. Split from QuestionDetailView+Edit.
//

import Foundation

enum QuestionInlineCommitField: String {
    case language
    case type
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
        let enqueuedIdentity = AccountsStore.shared.account(matching: client)?.id
        let guarded: @MainActor () async -> Void = {
            guard AccountsStore.shared.account(matching: client)?.id == enqueuedIdentity else { return }

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

/// Serializes whole-array candidate-instruction saves per account + question:
/// each save resends the entire instruction list, so two concurrent part edits
/// would each PUT an array holding the other part's old text and the later one
/// would win (#1188). Chaining them (and building each payload from the latest
/// published question inside the chained block) makes the second save see the
/// first one's result. Entries are removed when a chain drains.
@MainActor
enum QuestionInstructionSaveChain {
    private static var tails: [String: Task<Void, Never>] = [:]

    static func run(key: String, operation: @escaping @MainActor () async -> Bool) async -> Bool {
        let previous = tails[key]
        let task = Task { @MainActor () -> Bool in
            await previous?.value
            return await operation()
        }
        let tail = Task { @MainActor in _ = await task.value }
        tails[key] = tail
        let result = await task.value
        if tails[key] == tail { tails[key] = nil }
        return result
    }
}
