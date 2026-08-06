//
//  AccountEditDrafts.swift
//  coderpad
//

import Foundation

/// Process-local recovery for saved-account edits that cannot autosave yet. API
/// keys stay in memory (never UserDefaults), and a draft is restored only while
/// the persisted account it was based on is unchanged (#1392).
@MainActor
final class AccountEditDrafts {
    static let shared = AccountEditDrafts()

    private struct Entry {
        let draft: Account
        let persisted: Account
    }

    private var entries: [UUID: Entry] = [:]

    func stash(_ draft: Account, persisted: Account) {
        entries[draft.id] = Entry(draft: draft, persisted: persisted.normalizedForStorage)
    }

    func resume(for account: Account) -> Account? {
        guard let entry = entries[account.id] else { return nil }
        guard Self.hasSameEditableFields(entry.persisted, account.normalizedForStorage) else {
            entries[account.id] = nil
            return nil
        }

        entries[account.id] = nil
        return entry.draft
    }

    func clear(account: UUID) {
        entries[account] = nil
    }

    private static func hasSameEditableFields(_ lhs: Account, _ rhs: Account) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.apiKey == rhs.apiKey
            && lhs.userEmail == rhs.userEmail
            && lhs.baseURL == rhs.baseURL
            && lhs.screenApiKey == rhs.screenApiKey
            && lhs.screenRegion == rhs.screenRegion
    }
}
