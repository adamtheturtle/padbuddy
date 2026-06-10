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
