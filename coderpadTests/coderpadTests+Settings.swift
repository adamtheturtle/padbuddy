//
//  coderpadTests+Settings.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import SwiftUI
import Testing

#if os(macOS)
    @Suite("Menu bar preferences")
    struct MenuBarPreferenceTests {
        @Test
        func `menu labels normalize remote text and remain bounded`() {
            let label = MenuBarView.safeMenuLabel(
                "  Remote\n\tTitle\0  " + String(repeating: "x", count: 200),
                fallback: "Fallback"
            )

            #expect(!label.contains("\n"))
            #expect(!label.contains("\t"))
            #expect(!label.contains("\0"))
            #expect(label.hasPrefix("Remote Title "))
            #expect(label.count == 160)
            #expect(MenuBarView.safeMenuLabel(" \n ", fallback: "Fallback") == "Fallback")
        }

        @Test(arguments: [(-1, 0), (0, 0), (3, 3), (30, 30), (31, 30), (Int.max, 30)])
        func `top row count is bounded at every read`(stored: Int, expected: Int) {
            #expect(MenuBarView.normalizedTopCount(stored) == expected)
        }
    }
#endif

@Suite("Settings account selection")
struct SettingsAccountSelectionTests {
    @Test
    func `missing selections recover to current then first available account`() {
        let removed = UUID()
        let first = UUID()
        let current = UUID()

        #expect(SettingsView.recoveredAccountSelection(
            selected: removed, current: current, available: [first, current]
        ) == current)
        #expect(SettingsView.recoveredAccountSelection(
            selected: removed, current: removed, available: [first]
        ) == first)
        #expect(SettingsView.recoveredAccountSelection(
            selected: removed, current: current, available: []
        ) == nil)
    }

    @Test
    func `an available selection remains stable`() {
        let selected = UUID()
        #expect(SettingsView.recoveredAccountSelection(
            selected: selected, current: UUID(), available: [selected]
        ) == selected)
    }
}

@Suite("Account owner email validation")
struct AccountOwnerEmailValidationTests {
    @Test(arguments: ["", "not-an-email", "a@localhost", "a\u{200D}@example.com"])
    func `malformed API owner emails are rejected`(email: String) {
        #expect(AccountEditor.validatedOwnerEmail(email) == nil)
        #expect(AccountEditor.validatedOwnerEmail(nil) == nil)
    }

    @Test
    func `valid API owner emails are trimmed and normalize their domain`() {
        #expect(AccountEditor.validatedOwnerEmail("  Owner@EXAMPLE.COM \n") == "Owner@example.com")
    }
}

@Suite("Account validation name autofill")
struct AccountValidationNameAutofillTests {
    @Test
    func `unchanged blank description accepts the organization name`() {
        #expect(AccountEditor.shouldAutofillValidatedName(
            "  ", currentGeneration: 2, validatedGeneration: 2
        ))
    }

    @Test
    func `an edit during validation preserves the current description`() {
        #expect(!AccountEditor.shouldAutofillValidatedName(
            "", currentGeneration: 3, validatedGeneration: 2
        ))
    }

    @Test
    func `an existing description is never replaced`() {
        #expect(!AccountEditor.shouldAutofillValidatedName(
            "Personal", currentGeneration: 2, validatedGeneration: 2
        ))
    }
}

@Suite("Account save name policy")
struct AccountSaveNamePolicyTests {
    @Test
    func `live save preserves an intentionally blank description`() {
        let draft = Account(name: "  ", apiKey: " key ", userEmail: "owner@example.com")

        let saved = AccountEditor.preparedAccountForSave(draft, fallbackName: nil)

        #expect(saved.name == "  ")
        #expect(saved.apiKey == "key")
    }

    @Test
    func `explicit save still derives a name for a blank description`() {
        let draft = Account(name: "", apiKey: "key", userEmail: "owner@example.com")

        let saved = AccountEditor.preparedAccountForSave(draft, fallbackName: "Acme")

        #expect(saved.name == "Acme")
    }
}

@Suite("App appearance")
struct AppAppearanceTests {
    @Test(arguments: [
        (AppAppearance.system, "system"),
        (AppAppearance.light, "light"),
        (AppAppearance.dark, "dark")
    ])
    func `raw values are stable (they back the stored preference)`(appearance: AppAppearance, rawValue: String) {
        #expect(appearance.rawValue == rawValue)
    }

    @Test(arguments: [
        (AppAppearance.system, ColorScheme?.none),
        (AppAppearance.light, .light),
        (AppAppearance.dark, .dark)
    ])
    func `maps to the color scheme it forces, nil for system`(appearance: AppAppearance, scheme: ColorScheme?) {
        #expect(appearance.colorScheme == scheme)
    }

    @Test
    func `every case has a non-empty label`() {
        #expect(AppAppearance.allCases.allSatisfy { !$0.label.isEmpty })
    }
}

@Suite("App presence")
struct AppPresenceTests {
    @Test(arguments: [
        (AppPresence.dockAndMenuBar, "dockAndMenuBar"),
        (AppPresence.menuBarOnly, "menuBarOnly"),
        (AppPresence.dockOnly, "dockOnly")
    ])
    func `raw values are stable (they back the stored preference)`(presence: AppPresence, rawValue: String) {
        #expect(presence.rawValue == rawValue)
    }

    @Test(arguments: [
        (AppPresence.dockAndMenuBar, true, true),
        (AppPresence.menuBarOnly, false, true),
        (AppPresence.dockOnly, true, false)
    ])
    func `visibility flags match each mode`(presence: AppPresence, dock: Bool, menuBar: Bool) {
        #expect(presence.showsDockIcon == dock)
        #expect(presence.showsMenuBarIcon == menuBar)
    }

    @Test
    func `every case is visible somewhere and has a non-empty label`() {
        for presence in AppPresence.allCases {
            #expect(!presence.label.isEmpty)
            // "Neither" is not a valid mode: every case shows at least one affordance.
            #expect(presence.showsDockIcon || presence.showsMenuBarIcon)
        }
    }
}

// Serialized: these read and mutate process-wide UserDefaults under the
// `general.*` keys, so concurrent runs would clobber each other's values.
@Suite("General settings", .serialized)
struct GeneralSettingsTests {
    private static let keys = [
        GeneralSettings.Key.appearance,
        GeneralSettings.Key.presence,
        GeneralSettings.Key.hideDockIcon,
        "general.refreshSeconds"
    ]

    /// Snapshots the `general.*` defaults, clears them, runs the block, then restores
    /// whatever was there before so the test leaves no trace.
    private func withCleanDefaults<T>(_ block: () throws -> T) rethrows -> T {
        let saved = Self.keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        for key in Self.keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        defer {
            for (key, value) in saved {
                if let value {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        return try block()
    }

    @Test
    func `refreshInterval uses the fixed default cadence`() {
        withCleanDefaults {
            UserDefaults.standard.set(120, forKey: "general.refreshSeconds")
            #expect(GeneralSettings.refreshInterval == .seconds(GeneralSettings.defaultRefreshSeconds))
        }
    }

    @Test
    func `appearance defaults to system and reads back a stored choice`() {
        withCleanDefaults {
            #expect(GeneralSettings.appearance == .system)

            UserDefaults.standard.set("dark", forKey: GeneralSettings.Key.appearance)
            #expect(GeneralSettings.appearance == .dark)

            // An unrecognized stored value falls back to system rather than crashing.
            UserDefaults.standard.set("chartreuse", forKey: GeneralSettings.Key.appearance)
            #expect(GeneralSettings.appearance == .system)
        }
    }

    @Test
    func `presence defaults to dock and menu bar and reads back a stored choice`() {
        withCleanDefaults {
            #expect(GeneralSettings.presence == .dockAndMenuBar)

            UserDefaults.standard.set(AppPresence.dockOnly.rawValue, forKey: GeneralSettings.Key.presence)
            #expect(GeneralSettings.presence == .dockOnly)

            // An unrecognized stored value falls back to the default rather than crashing.
            UserDefaults.standard.set("bogus", forKey: GeneralSettings.Key.presence)
            #expect(GeneralSettings.presence == .dockAndMenuBar)
        }
    }

    @Test
    func `migration maps a hidden Dock icon to menu bar only`() {
        withCleanDefaults {
            UserDefaults.standard.set(true, forKey: GeneralSettings.Key.hideDockIcon)
            GeneralSettings.migratePresenceIfNeeded()
            #expect(GeneralSettings.presence == .menuBarOnly)
            // The legacy key is cleared so it can't override a later picker change.
            #expect(UserDefaults.standard.object(forKey: GeneralSettings.Key.hideDockIcon) == nil)
        }
    }

    @Test
    func `migration maps a shown Dock icon to dock and menu bar`() {
        withCleanDefaults {
            UserDefaults.standard.set(false, forKey: GeneralSettings.Key.hideDockIcon)
            GeneralSettings.migratePresenceIfNeeded()
            #expect(GeneralSettings.presence == .dockAndMenuBar)
            #expect(UserDefaults.standard.object(forKey: GeneralSettings.Key.hideDockIcon) == nil)
        }
    }

    @Test
    func `migration leaves an explicit presence choice untouched`() {
        withCleanDefaults {
            // A user who already picked "Dock only" then somehow has a stale legacy key:
            // the new preference wins and the legacy key is not consulted.
            UserDefaults.standard.set(AppPresence.dockOnly.rawValue, forKey: GeneralSettings.Key.presence)
            UserDefaults.standard.set(true, forKey: GeneralSettings.Key.hideDockIcon)
            GeneralSettings.migratePresenceIfNeeded()
            #expect(GeneralSettings.presence == .dockOnly)
        }
    }

    @Test
    func `migration is a no-op when nothing was ever set`() {
        withCleanDefaults {
            GeneralSettings.migratePresenceIfNeeded()
            #expect(UserDefaults.standard.string(forKey: GeneralSettings.Key.presence) == nil)
            #expect(GeneralSettings.presence == .dockAndMenuBar)
        }
    }
}
