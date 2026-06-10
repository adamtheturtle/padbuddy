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
    static var title: LocalizedStringResource = "Open Pad by ID"
    static var description = IntentDescription("Open a specific CoderPad pad in the in-app browser.")
    static var openAppWhenRun: Bool = true

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
    static var title: LocalizedStringResource = "Search Pads"
    static var description = IntentDescription("Open CoderPad and search pads matching a query.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Query", description: "Text to search pad titles, owners, and participants for.")
    var query: String

    func perform() async throws -> some IntentResult {
        try? await Task.sleep(for: .milliseconds(300))
        let q = query
        await MainActor.run {
            NotificationCenter.default.post(name: .sectionRequested, object: AppSection.pads)
            NotificationCenter.default.post(name: .padsSearchRequested, object: q)
        }
        return .result()
    }
}

struct NewPadIntent: AppIntent {
    static var title: LocalizedStringResource = "New Pad"
    static var description = IntentDescription("Open CoderPad and start creating a new pad.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        try? await Task.sleep(for: .milliseconds(400))
        await MainActor.run {
            NotificationCenter.default.post(name: .createPadRequested, object: nil)
        }
        return .result()
    }
}

struct OpenPadsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Pads"
    static var description = IntentDescription("Open the Pads list in CoderPad.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        try? await Task.sleep(for: .milliseconds(200))
        await MainActor.run {
            NotificationCenter.default.post(name: .sectionRequested, object: AppSection.pads)
        }
        return .result()
    }
}
