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
/// pad (#778). Pure so it's unit-testable.
/// pad (#778). Pure so it is unit-testable.
nonisolated enum PadIDValidation {
    /// Characters allowed beyond ASCII letters and digits.
    ///
    /// Hyphen and underscore are accepted because a self-hosted server can issue
    /// slugs containing them and the shortcut refused those outright (#2694). Neither
    /// can change the structure of the URL the id is interpolated into — unlike `/`,
    /// `?`, `#`, `:`, `@`, `.`, or whitespace, which stay rejected. That is the
    /// property #778 was protecting, and it is unchanged.
    private static let extraAllowed: Set<Character> = ["-", "_"]

    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1 ... 64).contains(trimmed.count),
              trimmed.allSatisfy({ character in
                  extraAllowed.contains(character)
                      || (character.isASCII && (character.isLetter || character.isNumber))
              })
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
        let searchText = ExternalText.singleLine(query, limit: Self.maxQueryLength)
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
            // The same policy the menu bar and iPad key commands use to enable or
            // disable New Pad, so the shortcut can't succeed where the equivalent UI
            // command is disabled (#4569) — including offline, where a create flow can
            // never submit.
            guard AccountsStore.shared.accounts.contains(
                where: AppCreationAvailability.hasUsableCredentials
            ) else { throw IntentAccountError.noUsableAccount }
            guard !NetworkMonitor.shared.isOffline else { throw IntentAccountError.offline }

            AppNavigation.shared.showPads(PadsRequest(startCreating: true))
        }
        return .result()
    }
}

/// Why an intent that needs an account to act on couldn't run.
enum IntentAccountError: LocalizedError {
    case noUsableAccount
    case offline

    var errorDescription: String? {
        switch self {
        case .noUsableAccount:
            String(localized: "Add a CoderPad account with an API key in PadBuddy first.")

        case .offline:
            String(localized: "PadBuddy is offline, so it cannot create a pad. Try again once you're connected.")
        }
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
        // Shortcuts persists entity parameters. Resolve the stored identity through
        // the live query immediately before routing so a removed account/favourite,
        // or a stale reused question id, cannot seed a create flow (#1291).
        guard let resolved = try await FavoriteQuestionQuery().entities(for: [question.id]).first else {
            throw IntentFavoriteQuestionError.noLongerAvailable
        }

        let accountID = resolved.accountID
        let questionID = resolved.questionID
        await MainActor.run {
            AppNavigation.shared.routeNewPad(account: accountID, seedQuestionID: questionID)
        }
        return .result()
    }
}

enum IntentFavoriteQuestionError: LocalizedError {
    case noLongerAvailable

    var errorDescription: String? {
        String(localized: "That favorite question is no longer available. Choose another one in Shortcuts.")
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
