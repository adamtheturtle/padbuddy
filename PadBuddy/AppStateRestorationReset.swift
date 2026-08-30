//
//  AppStateRestorationReset.swift
//  coderpad
//

import SwiftUI

@MainActor
enum AppStateRestorationReset {
    private(set) static var generation = 0
    private static let prefixes = [
        "selection.", "section.", "pads.liveFilter.", "pads.selectedPad.", "pads.topRow.",
        "questions.liveFilter.", "questions.selectedQuestion.", "questions.topRow.",
        "pads.merged.", "questions.merged.", "screen.selected"
    ]

    @discardableResult
    static func reset() -> Int {
        generation &+= 1
        LiveFilterPersistence.shared.cancelAll()
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys.filter { key in
            prefixes.contains { key.hasPrefix($0) }
        }
        keys.forEach(defaults.removeObject(forKey:))
        return keys.count
    }
}

extension SettingsView {
    var restoredStateSection: some View {
        Section {
            Button("Reset Restored App State…", role: .destructive) {
                confirmResetRestoredState = true
            }
            if let restoredStateResetMessage {
                Text(restoredStateResetMessage).foregroundStyle(.secondary)
            }
        } footer: {
            Text("Clears restored navigation, selections, list positions, and filters. "
                + "Accounts and unfinished drafts remain.")
                .foregroundStyle(.secondary)
        }
    }
}

struct RestoredStateConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Reset restored app state?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Reset Restored State", role: .destructive) {
                let count = AppStateRestorationReset.reset()
                message = String(localized: """
                Reset ^[\(count) saved state values](inflect: true). Reopen windows to start fresh.
                """)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This does not remove accounts, credentials, cached content, favorites, "
                + "or unfinished creation drafts.")
        }
    }
}
