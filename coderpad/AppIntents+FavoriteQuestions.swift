//
//  AppIntents+FavoriteQuestions.swift
//  coderpad
//
//  The favourite-question Shortcuts entity and its query, split from AppIntents.swift
//  to keep both files under the file-length limit.
//

import AppIntents
import Foundation

struct FavoriteQuestionEntity: AppEntity {
    let id: String
    let accountID: String
    let questionID: Int
    let title: String
    let legacyID: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Favorite Question"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    static let defaultQuery = FavoriteQuestionQuery()
}

struct FavoriteQuestionQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FavoriteQuestionEntity] {
        await MainActor.run {
            // Indexed by every identity an entity answers to, then looked up in the
            // order asked for. Filtering `all()` instead returned them in account
            // order, so an App Intents caller got its entities shuffled relative to
            // the identifiers it passed (#2361).
            // Built only for the favourites actually asked for. Resolving a single
            // configured entity used to construct one for every favourite of every
            // account and then throw nearly all of them away (#2140).
            let wanted = Self.wantedIdentifiers(for: identifiers)
            var byIdentifier: [String: FavoriteQuestionEntity] = [:]
            for entity in all(matching: wanted) {
                byIdentifier[entity.id] = entity
                byIdentifier[entity.legacyID] = entity
                // A re-key used to change `syncID`, which folded in the API-key
                // fingerprint, orphaning every Shortcut configured before the
                // rotation even though the account and question were unchanged. The
                // key-independent form is accepted as an alias so those keep
                // resolving (#2359) — the ids issued now are already in that form
                // (#2141), but Shortcuts still holds the fingerprint-bearing ones it
                // was configured with, and they must go on resolving.
                byIdentifier[Self.keyIndependentID(entity.id)] = entity
            }
            var seen = Set<String>()
            return identifiers.compactMap { identifier -> FavoriteQuestionEntity? in
                let entity = byIdentifier[identifier]
                    ?? byIdentifier[Self.keyIndependentID(identifier)]
                guard let entity, seen.insert(entity.id).inserted else { return nil }

                return entity
            }
        }
    }

    /// A `sync|<endpoint>|<email>|<fingerprint>|<question>` id with the key
    /// fingerprint dropped, so the same account and question match across a key
    /// rotation. Anything not in that exact shape is returned unchanged — including
    /// an id issued since #2141, whose `syncID` no longer carries a fingerprint and
    /// which is therefore already in this form.
    ///
    /// The component count is checked rather than assumed. A legacy `syncID` was
    /// `endpoint|email|fingerprint`, so such an entity id has exactly five
    /// components — but an endpoint containing a `|` would produce more, and blindly
    /// dropping the second-to-last one would then strip part of the endpoint and
    /// alias two genuinely different accounts onto one identifier (#2699). Such an id
    /// gets no alias and simply resolves by exact match.
    static func keyIndependentID(_ identifier: String) -> String {
        let parts = identifier.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0] == "sync" else { return identifier }

        // Drop the fingerprint: the component between the email and the question id.
        return (parts[0 ... 2] + parts[4...]).joined(separator: "|")
    }

    /// Every identifier a requested entity could answer to, so membership can be
    /// tested without building the entity first. Each requested identifier is stored
    /// alongside its key-independent alias, matching the aliases `entities(for:)`
    /// accepts.
    static func wantedIdentifiers(for identifiers: [String]) -> Set<String> {
        var wanted = Set(identifiers)
        for identifier in identifiers {
            wanted.insert(keyIndependentID(identifier))
        }
        return wanted
    }

    /// Whether an entity with these identities was asked for. Both the sync id and
    /// the legacy id are checked, and the sync id also in its key-independent form,
    /// because a caller may have stored any of the three.
    static func isWanted(id: String, legacyID: String, in wanted: Set<String>) -> Bool {
        wanted.contains(id) || wanted.contains(keyIndependentID(id)) || wanted.contains(legacyID)
    }

    /// How many favourites Shortcuts is offered at once. Enumerating every
    /// favourite of every account made configuration slow on a large collection,
    /// and a picker that long isn't usable anyway (#2362).
    static let suggestedLimit = 100

    func suggestedEntities() async throws -> [FavoriteQuestionEntity] {
        await MainActor.run {
            Array(all().prefix(Self.suggestedLimit))
        }
    }

    /// Every favourite as an entity, or — when `wanted` is given — only those
    /// answering to one of those identifiers.
    @MainActor
    private func all(matching wanted: Set<String>? = nil) -> [FavoriteQuestionEntity] {
        // De-duplicated by sync identity: two records for the same endpoint and owner
        // are the same account, and they produced entities sharing one id (#2360).
        // Accounts with no resolvable sync id keep their own local entry.
        var seenIdentities = Set<String>()
        let accounts = AccountsStore.shared.accounts.filter {
            $0.syncID.isEmpty || seenIdentities.insert($0.syncID).inserted
        }
        let qualify = accounts.count > 1
        // Emitted ids must be unique: `AppEntity` identity is the contract Shortcuts
        // stores, and a corrupt favourites list with a repeated question id produced
        // two entities sharing one id (#2702). De-duplicated across accounts too, so a
        // repeat can't slip in from the account loop either.
        var emitted = Set<String>()
        return accounts.flatMap { account in
            FavoriteQuestionsStore.shared.titledFavorites(account: account.id).compactMap { favorite in
                let id = entityID(account: account, questionID: favorite.id)
                guard emitted.insert(id).inserted else { return nil }

                let legacyID = legacyEntityID(account: account, questionID: favorite.id)
                // Filtered before any of the title work below, which is the part worth
                // skipping for a favourite nobody asked about (#2140).
                if let wanted, !Self.isWanted(id: id, legacyID: legacyID, in: wanted) { return nil }

                // Trimmed before the check: a whitespace-only cloud title produced a
                // blank Shortcuts choice rather than the "#id" fallback (#2363).
                let stored = favorite.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = stored.isEmpty ? "#\(favorite.id)" : stored
                // The account name is read live here, so a rename shows up the next
                // time Shortcuts queries rather than persisting a stale label (#2701).
                let accountName = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = qualify && !accountName.isEmpty ? "\(title) · \(accountName)" : title
                return FavoriteQuestionEntity(id: id,
                                              accountID: account.id.uuidString,
                                              questionID: favorite.id,
                                              title: label,
                                              legacyID: legacyID)
            }
        }
    }

    @MainActor
    private func entityID(account: Account, questionID: Int) -> String {
        let syncID = account.syncID
        guard !syncID.isEmpty else { return legacyEntityID(account: account, questionID: questionID) }

        return "sync|\(syncID)|\(questionID)"
    }

    @MainActor
    private func legacyEntityID(account: Account, questionID: Int) -> String {
        "\(account.id.uuidString):\(questionID)"
    }
}
