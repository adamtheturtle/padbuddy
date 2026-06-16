//
//  coderpadTests+Settings.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import SwiftUI
import Testing

@Suite("What's New gating", .serialized)
struct WhatsNewTests {
    private static let key = "lastSeenWhatsNewVersion"

    private func withCleanDefault<T>(_ block: () throws -> T) rethrows -> T {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        UserDefaults.standard.removeObject(forKey: Self.key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: Self.key)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.key)
            }
        }
        return try block()
    }

    @Test
    func `shouldShow returns true on clean install`() {
        withCleanDefault {
            #expect(WhatsNew.shouldShow() == true)
        }
    }

    @Test
    func `markSeen suppresses future prompts for the same version`() {
        withCleanDefault {
            WhatsNew.markSeen()
            #expect(WhatsNew.shouldShow() == false)
        }
    }

    @Test
    func `an older recorded version still triggers the prompt`() {
        withCleanDefault {
            UserDefaults.standard.set("0.1", forKey: Self.key)
            #expect(WhatsNew.shouldShow() == true)
        }
    }

    @Test
    func `the gate is keyed on the live app version, not a hardcoded constant`() {
        withCleanDefault {
            // markSeen must record exactly the version the gate compares against, so
            // a MARKETING_VERSION bump (which changes WhatsNew.version) re-shows the
            // sheet without anyone editing a second constant.
            #expect(!WhatsNew.version.isEmpty)
            #expect(WhatsNew.current.version == WhatsNew.version)
            WhatsNew.markSeen()
            #expect(UserDefaults.standard.string(forKey: Self.key) == WhatsNew.version)

            // Recording any other version re-arms the prompt.
            UserDefaults.standard.set(WhatsNew.version + "-old", forKey: Self.key)
            #expect(WhatsNew.shouldShow() == true)
        }
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
        GeneralSettings.Key.refreshSeconds
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
    func `refreshSeconds falls back to the default when unset`() {
        withCleanDefaults {
            #expect(GeneralSettings.refreshSeconds == GeneralSettings.defaultRefreshSeconds)
            #expect(GeneralSettings.refreshInterval == .seconds(GeneralSettings.defaultRefreshSeconds))
        }
    }

    @Test
    func `refreshSeconds passes a valid stored value through`() {
        withCleanDefaults {
            UserDefaults.standard.set(120, forKey: GeneralSettings.Key.refreshSeconds)
            #expect(GeneralSettings.refreshSeconds == 120)
            #expect(GeneralSettings.refreshInterval == .seconds(120))
        }
    }

    @Test
    func `refreshSeconds clamps below the minimum and above the maximum`() {
        withCleanDefaults {
            UserDefaults.standard.set(1, forKey: GeneralSettings.Key.refreshSeconds)
            #expect(GeneralSettings.refreshSeconds == GeneralSettings.minRefreshSeconds)

            UserDefaults.standard.set(99999, forKey: GeneralSettings.Key.refreshSeconds)
            #expect(GeneralSettings.refreshSeconds == GeneralSettings.maxRefreshSeconds)
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
