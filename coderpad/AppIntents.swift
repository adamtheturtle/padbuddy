//
//  AppIntents.swift
//  coderpad
//

import AppIntents
import Foundation

struct CoderPadShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewPadIntent(),
            phrases: ["New pad in \(.applicationName)", "Create pad in \(.applicationName)"],
            shortTitle: "New Pad",
            systemImageName: "plus.square.on.square"
        )
        AppShortcut(
            intent: OpenPadsIntent(),
            phrases: ["Open my pads in \(.applicationName)", "Show pads in \(.applicationName)"],
            shortTitle: "Open Pads",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: OpenRecentPadsIntent(),
            phrases: ["Open recent pads in \(.applicationName)", "Show recent pads in \(.applicationName)"],
            shortTitle: "Recent Pads",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: OpenActivePadsIntent(),
            phrases: ["Open active pads in \(.applicationName)", "Show active interviews in \(.applicationName)"],
            shortTitle: "Active Pads",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: NewPadFromFavoriteQuestionIntent(),
            phrases: [
                "New pad from favorite question in \(.applicationName)",
                "Create pad from favorite question in \(.applicationName)"
            ],
            shortTitle: "Favorite Question Pad",
            systemImageName: "star.square.on.square"
        )
        AppShortcut(
            intent: SearchPadsIntent(),
            phrases: ["Search \(.applicationName)", "Find pads in \(.applicationName)"],
            shortTitle: "Search Pads",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenPadByIDIntent(),
            phrases: ["Open pad in \(.applicationName)", "Show pad in \(.applicationName)"],
            shortTitle: "Open Pad by ID",
            systemImageName: "doc.text.image"
        )
    }
}

/// Validates the free-text pad identifier the "Open Pad by ID" intent accepts. Pad ids
/// are short ASCII-alphanumeric tokens; anything else (slashes, `?`, `#`, spaces) would
/// change the structure of the browser URL it's interpolated into rather than name a
/// pad (#778). Pure so it's unit-testable.
nonisolated enum PadIDValidation {
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1 ... 64).contains(trimmed.count),
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { return nil }

        return trimmed
    }
}

struct OpenPadByIDIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Pad by ID"
    // Read by the AppIntents framework (Shortcuts metadata), not Swift.
    // periphery:ignore
    static let description = IntentDescription("Open a specific CoderPad pad in your browser.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Pad ID", description: "The 8-character pad identifier.")
    var padID: String

    /// Optional: which account the id belongs to. Pad ids are only unique within an
    /// organization, so on a multi-account setup — especially with custom servers,
    /// where the same slug can genuinely exist twice — a bare id let whichever account
    /// happened to be current claim the pad (#2353). Left unset it keeps the previous
    /// behaviour and resolves globally, which is what a single-account user wants.
    @Parameter(title: "Account", description: "Which account the pad belongs to. Optional.")
    var account: AccountFocusEntity?

    func perform() async throws -> some IntentResult {
        // Reject anything that isn't a plain pad identifier instead of letting it
        // rewrite the opened URL's path, query, or fragment (#778).
        guard let id = PadIDValidation.normalize(padID) else {
            throw $padID.needsValueError("Enter the pad's identifier - letters and numbers only.")
        }

        // A named account has to still exist: routing under one that has been removed
        // would silently fall back to the global resolution the parameter exists to
        // avoid.
        let owner: UUID? = if let account {
            try await MainActor.run {
                guard let uuid = UUID(uuidString: account.id),
                      AccountsStore.shared.accounts.contains(where: { $0.id == uuid }) else {
                    throw $account.needsValueError("That account is no longer set up in PadBuddy.")
                }

                return uuid
            }
        } else {
            nil
        }

        // Mirror the other intents: wait for a scene to be on screen, then route
        // through durable AppNavigation state (consumed on appear) so the request isn't
        // lost if it fires before any view is listening. The wait throws when
        // Shortcuts/Siri cancels the intent; propagating that exits before routing
        // (#844).
        try await AppReadiness.waitUntilReady()
        await MainActor.run {
            AppNavigation.shared.openPad(id: id, account: owner)
        }
        return .result()
    }
}

struct SearchPadsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Pads"
    // Read by the AppIntents framework (Shortcuts metadata), not Swift.
    // periphery:ignore
    static let description = IntentDescription("Open PadBuddy and search pads matching a query.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Query", description: "Text to search pad titles, owners, and participants for.")
    var query: String

    /// The longest query worth routing. Pad titles, owners, and participants are all
    /// short; anything beyond this can only fail to match, and the search text is
    /// durable navigation state that persists in the list until the user clears it,
    /// so an accidental paste of a whole document used to stick (#2354).
    static let maxQueryLength = 200

    func perform() async throws -> some IntentResult {
        // Normalized before it becomes durable state, not after: a whitespace-only
        // query is an empty search, not a search for spaces (#2354).
        let searchText = String(query.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Self.maxQueryLength))
        // Cancellation during the wait throws and exits before routing (#844).
        try await AppReadiness.waitUntilReady()
        await MainActor.run {
            AppNavigation.shared.showPads(PadsRequest(search: searchText))
        }
        return .result()
    }
}

struct NewPadIntent: AppIntent {
    static let title: LocalizedStringResource = "New Pad"
    // Read by the AppIntents framework (Shortcuts metadata), not Swift.
    // periphery:ignore
    static let description = IntentDescription("Open PadBuddy and start creating a new pad.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Cancellation during the wait throws and exits before routing (#844).
        try await AppReadiness.waitUntilReady()
        // A create sheet with no credentialled account behind it cannot submit, and
        // presenting one told the user nothing about why — the shortcut appeared to
        // work and then dead-ended (#2355). Say so as an intent error instead, which
        // Shortcuts surfaces properly and which a shortcut can branch on.
        try await MainActor.run {
            guard AccountsStore.shared.accounts.contains(where: { $0.isMock || !$0.apiKey.isEmpty })
            else { throw IntentAccountError.noUsableAccount }

            AppNavigation.shared.showPads(PadsRequest(startCreating: true))
        }
        return .result()
    }
}

/// Why an intent that needs an account to act on couldn't run.
enum IntentAccountError: LocalizedError {
    case noUsableAccount

    var errorDescription: String? {
        String(localized: "Add a CoderPad account with an API key in PadBuddy first.")
    }
}

struct NewPadFromFavoriteQuestionIntent: AppIntent {
    static let title: LocalizedStringResource = "New Pad from Favorite Question"
    // Read by the AppIntents framework (Shortcuts metadata), not Swift.
    // periphery:ignore
    static let description = IntentDescription("Open PadBuddy and create a new pad from a favorite question.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Question")
    var question: FavoriteQuestionEntity

    func perform() async throws -> some IntentResult {
        // Cancellation during the wait throws and exits before routing (#844).
        try await AppReadiness.waitUntilReady()
        let accountID = question.accountID
        let questionID = question.questionID
        await MainActor.run {
            AppNavigation.shared.routeNewPad(account: accountID, seedQuestionID: questionID)
        }
        return .result()
    }
}

struct OpenPadsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Pads"
    // Read by the AppIntents framework (Shortcuts metadata), not Swift.
    // periphery:ignore
    static let description = IntentDescription("Open the Pads list in PadBuddy.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Cancellation during the wait throws and exits before routing (#844).
        try await AppReadiness.waitUntilReady()
        await MainActor.run {
            AppNavigation.shared.show(.pads)
        }
        return .result()
    }
}

struct OpenRecentPadsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Recent Pads"
    // Read by the AppIntents framework (Shortcuts metadata), not Swift.
    // periphery:ignore
    static let description = IntentDescription("Open PadBuddy to your recent pads.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Cancellation during the wait throws and exits before routing (#844).
        try await AppReadiness.waitUntilReady()
        await MainActor.run {
            // The user's chosen sort is left alone. Writing `updatedDesc` here changed
            // it in every window and account, permanently, as a side effect of running
            // a shortcut — and "recent" is what the list already shows by default
            // (#2357). The intent's job is to open the pads list, not to re-sort it.
            if AccountsStore.shared.isMergedView {
                AppNavigation.shared.showMergedRoot(kind: .pads)
            } else {
                AppNavigation.shared.showPads(PadsRequest(applySearch: NamedSearch(name: "")))
            }
        }
        return .result()
    }
}

struct OpenActivePadsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Active Pads"
    // Read by the AppIntents framework (Shortcuts metadata), not Swift.
    // periphery:ignore
    static let description = IntentDescription("Open PadBuddy to active interview pads.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Cancellation during the wait throws and exits before routing (#844).
        try await AppReadiness.waitUntilReady()
        await MainActor.run {
            if AccountsStore.shared.isMergedView {
                // Through the root reset, so a search, owner, or Mine filter left on
                // screen can't hide the very pads this shortcut exists to show (#2358).
                AppNavigation.shared.showMergedRoot(kind: .pads, activeOnly: true)
            } else {
                let active = NamedSearch(name: String(localized: "Active Pads"), stateFilter: .active)
                AppNavigation.shared.showPads(PadsRequest(applySearch: active))
            }
        }
        return .result()
    }
}

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
            var byIdentifier: [String: FavoriteQuestionEntity] = [:]
            for entity in all() {
                byIdentifier[entity.id] = entity
                byIdentifier[entity.legacyID] = entity
                // A re-key changes `syncID` — it folds in the API-key fingerprint —
                // which would otherwise orphan every Shortcut configured before the
                // rotation even though the account and question are unchanged. The
                // key-independent form is accepted as an alias so those keep
                // resolving (#2359).
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
    /// rotation. Anything not in that shape is returned unchanged.
    static func keyIndependentID(_ identifier: String) -> String {
        let parts = identifier.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0] == "sync" else { return identifier }

        // The sync id itself is `endpoint|email|fingerprint`; drop the fingerprint,
        // which is the second-to-last component before the question id.
        var kept = Array(parts)
        kept.remove(at: kept.count - 2)
        return kept.joined(separator: "|")
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

    @MainActor
    private func all() -> [FavoriteQuestionEntity] {
        // De-duplicated by sync identity: two records for the same endpoint, owner,
        // and key are the same account, and they produced entities sharing one id
        // (#2360). Accounts with no resolvable sync id keep their own local entry.
        var seenIdentities = Set<String>()
        let accounts = AccountsStore.shared.accounts.filter {
            $0.syncID.isEmpty || seenIdentities.insert($0.syncID).inserted
        }
        let qualify = accounts.count > 1
        return accounts.flatMap { account in
            FavoriteQuestionsStore.shared.titledFavorites(account: account.id).map { favorite in
                // Trimmed before the check: a whitespace-only cloud title produced a
                // blank Shortcuts choice rather than the "#id" fallback (#2363).
                let stored = favorite.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = stored.isEmpty ? "#\(favorite.id)" : stored
                let label = qualify ? "\(title) · \(account.name)" : title
                return FavoriteQuestionEntity(id: entityID(account: account, questionID: favorite.id),
                                              accountID: account.id.uuidString,
                                              questionID: favorite.id,
                                              title: label,
                                              legacyID: legacyEntityID(account: account, questionID: favorite.id))
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
