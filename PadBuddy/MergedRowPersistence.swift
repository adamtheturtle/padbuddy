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

/// Resolves the merged lists' cross-account filter across devices.
///
/// The filter is held in memory as the account's local `UUID`, which is random
/// per device. Persisting only that meant a snapshot arriving on another Mac
/// through preference sync — or surviving a reinstall — named an account that
/// does not exist there, so the filter was dropped and the list silently widened
/// to every account (#2557). Pairing it with `Account.syncID`, which is derived
/// from the endpoint, owner email, and key fingerprint and so matches across
/// devices, lets the restore recover the intended account.
@MainActor
enum MergedAccountFilter {
    /// The cross-device identity of the filtered account, or nil when nothing is
    /// filtered or the account has no resolvable sync id (a draft with no key yet).
    static func syncID(for accountFilter: UUID?) -> String? {
        guard let accountFilter,
              let account = AccountsStore.shared.accounts.first(where: { $0.id == accountFilter })
        else { return nil }

        let syncID = account.syncID
        return syncID.isEmpty ? nil : syncID
    }

    /// The local account id a restored snapshot's filter refers to, or nil to
    /// restore unfiltered.
    ///
    /// The local id is tried first — on the device that wrote the snapshot it is
    /// exact and cheapest — then the sync id. Only an account that is still
    /// mergeable qualifies: a removed account's filter would show an empty list,
    /// so restoring unfiltered is the better failure (#1656).
    static func resolve(_ snapshot: MergedFilterSnapshot) -> UUID? {
        let mergeable = AccountsStore.shared.mergeableAccounts
        if let id = snapshot.accountFilter, mergeable.contains(where: { $0.id == id }) {
            return id
        }
        guard let syncID = snapshot.accountFilterSyncID, !syncID.isEmpty else { return nil }

        return mergeable.first { $0.syncID == syncID }?.id
    }
}
