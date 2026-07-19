//
//  MergedAccountToken.swift
//  coderpad
//
//  The change token for a merged view's account set.
//

import CryptoKit
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
    let apiKeyDigest: Data
    let baseURL: URL

    @MainActor
    init(account: Account) {
        id = account.id
        let key = account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKeyDigest = Data(SHA256.hash(data: Data(key.utf8)))
        baseURL = account.resolvedBaseURL
    }
}

struct MergedScreenAccountToken: Hashable {
    let id: UUID
    let apiKeyDigest: Data
    let baseURL: URL

    @MainActor
    init(account: Account) {
        id = account.id
        let key = (account.screenApiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        apiKeyDigest = Data(SHA256.hash(data: Data(key.utf8)))
        baseURL = account.screenRegion.baseURL
    }
}
