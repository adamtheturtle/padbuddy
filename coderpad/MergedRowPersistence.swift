//
//  MergedRowPersistence.swift
//  coderpad
//
//  Endpoint stamping for persisted merged row ids, shared by the merged pad and
//  question lists. Split out of MergedPadsView+Persistence so that file stays
//  under the project's file-length lint.
//

import Foundation

/// Endpoint stamping for persisted merged row ids (#1236): a saved value is an
/// account-namespaced row id, but an account re-pointed at a different server
/// keeps its UUID, so the id alone could reopen an unrelated same-slug resource
/// on the new server. Each persisted row id is stamped with its account's
/// endpoint; a restore drops the value when the endpoint no longer matches.
@MainActor
enum MergedRowPersistence {
    /// The endpoint stamp to store alongside `rowID`, or `""` when there is
    /// nothing to stamp (no row, or an account that no longer resolves).
    ///
    /// Callers hold this in scene storage next to the row id itself rather than
    /// in a sibling `UserDefaults` key, so the pair is restored to the window it
    /// belongs to (#2560-#2563).
    static func endpoint(forRowID rowID: String?) -> String {
        guard let rowID, let uuid = accountUUID(fromRowID: rowID),
              let account = AccountsStore.shared.accounts.first(where: { $0.id == uuid })
        else { return "" }

        return account.resolvedBaseURL.absoluteString
    }

    /// `saved` unless its account now points at a different endpoint than when it
    /// was stamped. A value with no stamp (legacy, or a bare pre-#758 slug) passes
    /// through untouched.
    static func validatedRowID(_ saved: String, endpoint stamped: String) -> String? {
        guard !saved.isEmpty else { return nil }
        guard let uuid = accountUUID(fromRowID: saved), !stamped.isEmpty else { return saved }
        guard let account = AccountsStore.shared.accounts.first(where: { $0.id == uuid }),
              account.resolvedBaseURL.absoluteString == stamped else { return nil }

        return saved
    }

    private static func accountUUID(fromRowID id: String) -> UUID? {
        guard let separator = id.firstIndex(of: ":") else { return nil }

        return UUID(uuidString: String(id[..<separator]))
    }
}
