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

struct OpenPadByIDIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Pad by ID"
    // Read by the AppIntents framework (Shortcuts metadata), not Swift.
    // periphery:ignore
    static let description = IntentDescription("Open a specific CoderPad pad in the in-app browser.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Pad ID", description: "The 8-character pad identifier.")
    var padID: String

    func perform() async -> some IntentResult {
        let trimmed = padID.trimmingCharacters(in: .whitespacesAndNewlines)
        // Mirror the other intents: warm up briefly on cold launch, then route through
        // durable AppNavigation state (consumed on appear) so the request isn't lost if
        // it fires before any view is listening.
        try? await Task.sleep(for: .milliseconds(300))
        await MainActor.run {
            AppNavigation.shared.openPad(id: trimmed)
        }
        return .result()
    }
}

struct SearchPadsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Pads"
    // Read by the AppIntents framework (Shortcuts metadata), not Swift.
    // periphery:ignore
    static let description = IntentDescription("Open CoderPad and search pads matching a query.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Query", description: "Text to search pad titles, owners, and participants for.")
    var query: String

    func perform() async -> some IntentResult {
        try? await Task.sleep(for: .milliseconds(300))
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
    static let description = IntentDescription("Open CoderPad and start creating a new pad.")
    static let openAppWhenRun: Bool = true

    func perform() async -> some IntentResult {
        try? await Task.sleep(for: .milliseconds(400))
        await MainActor.run {
            AppNavigation.shared.showPads(PadsRequest(startCreating: true))
        }
        return .result()
    }
}

struct OpenPadsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Pads"
    // Read by the AppIntents framework (Shortcuts metadata), not Swift.
    // periphery:ignore
    static let description = IntentDescription("Open the Pads list in CoderPad.")
    static let openAppWhenRun: Bool = true

    func perform() async -> some IntentResult {
        try? await Task.sleep(for: .milliseconds(200))
        await MainActor.run {
            AppNavigation.shared.show(.pads)
        }
        return .result()
    }
}
