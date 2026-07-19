//
//  MergedAccountToken.swift
//  coderpad
//
//  The change token for a merged view's account set.
//

import Foundation

/// One account's identity for change detection: which account, which credentials,
/// which server. Encoding only key *presence* missed non-empty rekeys and endpoint
/// edits, leaving a stale or wrong-org card painting as current (#993, #1031).
///
/// A plain `Hashable` value rather than a built string: these feed `.task(id:)` keys
/// that SwiftUI re-evaluates on every body pass, and the string form did real work
/// per account per render purely to detect a change (#2281).
struct MergedAccountToken: Hashable {
    let id: UUID
    let apiKey: String
    let baseURL: URL

    @MainActor
    init(account: Account) {
        id = account.id
        apiKey = account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        baseURL = account.resolvedBaseURL
    }
}
