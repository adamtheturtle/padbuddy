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

    func perform() async throws -> some IntentResult {
        // Reject anything that isn't a plain pad identifier instead of letting it
        // rewrite the opened URL's path, query, or fragment (#778).
        guard let id = PadIDValidation.normalize(padID) else {
            throw $padID.needsValueError("Enter the pad's identifier - letters and numbers only.")
        }

        // Mirror the other intents: warm up briefly on cold launch, then route through
        // durable AppNavigation state (consumed on appear) so the request isn't lost if
        // it fires before any view is listening. The sleep throws when Shortcuts/Siri
        // cancels the intent; propagating that exits before routing (#844).
        try await Task.sleep(for: .milliseconds(300))
        await MainActor.run {
            AppNavigation.shared.openPad(id: id)
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

    func perform() async throws -> some IntentResult {
        // Cancellation during the warm-up throws and exits before routing (#844).
        try await Task.sleep(for: .milliseconds(300))
        let searchText = query
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
        // Cancellation during the warm-up throws and exits before routing (#844).
        try await Task.sleep(for: .milliseconds(400))
        await MainActor.run {
            AppNavigation.shared.showPads(PadsRequest(startCreating: true))
        }
        return .result()
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
        // Cancellation during the warm-up throws and exits before routing (#844).
        try await Task.sleep(for: .milliseconds(400))
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
        // Cancellation during the warm-up throws and exits before routing (#844).
        try await Task.sleep(for: .milliseconds(200))
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
        // Cancellation during the warm-up throws and exits before routing (#844).
        try await Task.sleep(for: .milliseconds(200))
        await MainActor.run {
            UserDefaults.standard.set(PadSort.updatedDesc.rawValue, forKey: PadSort.storageKey)
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
        // Cancellation during the warm-up throws and exits before routing (#844).
        try await Task.sleep(for: .milliseconds(200))
        await MainActor.run {
            if AccountsStore.shared.isMergedView {
                AppNavigation.shared.sectionRequest = .pads
                AppNavigation.shared.mergedPadsActiveRequest = true
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
            let identifiers = Set(identifiers)
            return all().filter { identifiers.contains($0.id) || identifiers.contains($0.legacyID) }
        }
    }

    func suggestedEntities() async throws -> [FavoriteQuestionEntity] {
        await MainActor.run {
            all()
        }
    }

    @MainActor
    private func all() -> [FavoriteQuestionEntity] {
        let accounts = AccountsStore.shared.accounts
        let qualify = accounts.count > 1
        return accounts.flatMap { account in
            FavoriteQuestionsStore.shared.titledFavorites(account: account.id).map { favorite in
                let title = favorite.title.isEmpty ? "#\(favorite.id)" : favorite.title
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
