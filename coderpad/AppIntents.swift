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
    static let description = IntentDescription("Open a specific CoderPad pad in the in-app browser.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Pad ID", description: "The 8-character pad identifier.")
    var padID: String

    func perform() async throws -> some IntentResult {
        let trimmed = padID.trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run {
            NotificationCenter.default.post(name: .openPadIDRequested, object: trimmed)
        }
        return .result()
    }
}

struct SearchPadsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Pads"
    static let description = IntentDescription("Open CoderPad and search pads matching a query.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Query", description: "Text to search pad titles, owners, and participants for.")
    var query: String

    func perform() async throws -> some IntentResult {
        try? await Task.sleep(for: .milliseconds(300))
        let q = query
        await MainActor.run {
            AppNavigation.shared.showPads(PadsRequest(search: q))
        }
        return .result()
    }
}

struct NewPadIntent: AppIntent {
    static let title: LocalizedStringResource = "New Pad"
    static let description = IntentDescription("Open CoderPad and start creating a new pad.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        try? await Task.sleep(for: .milliseconds(400))
        await MainActor.run {
            AppNavigation.shared.showPads(PadsRequest(startCreating: true))
        }
        return .result()
    }
}

struct OpenPadsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Pads"
    static let description = IntentDescription("Open the Pads list in CoderPad.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        try? await Task.sleep(for: .milliseconds(200))
        await MainActor.run {
            AppNavigation.shared.show(.pads)
        }
        return .result()
    }
}
