//
//  PadBuddyTests+SettingsPreferenceRecovery.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Settings preference recovery")
struct SettingsPreferenceRecoveryTests {
    private func defaults() throws -> UserDefaults {
        let name = "SettingsPreferenceRecoveryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test
    func `invalid independent values recover together`() throws {
        let defaults = try defaults()
        defaults.set("invalid", forKey: GeneralSettings.Key.presence)
        defaults.set("many", forKey: SettingsPreferenceRecovery.menuBarTopNKey)
        defaults.set("yes", forKey: MCPServer.enabledDefaultsKey)
        defaults.set(true, forKey: MCPServer.writeEnabledDefaultsKey)

        SettingsPreferenceRecovery.reconcile(defaults)

        #expect(defaults.string(forKey: GeneralSettings.Key.presence) == AppPresence.dockAndMenuBar.rawValue)
        #expect(defaults.integer(forKey: SettingsPreferenceRecovery.menuBarTopNKey) == 3)
        #expect(!defaults.bool(forKey: MCPServer.enabledDefaultsKey))
        #expect(!defaults.bool(forKey: MCPServer.writeEnabledDefaultsKey))
    }

    @Test(arguments: [(-4, 0), (12, 12), (80, 30)])
    func `menu count is clamped to its settings range`(stored: Int, expected: Int) throws {
        let defaults = try defaults()
        defaults.set(stored, forKey: SettingsPreferenceRecovery.menuBarTopNKey)

        SettingsPreferenceRecovery.reconcile(defaults)

        #expect(defaults.integer(forKey: SettingsPreferenceRecovery.menuBarTopNKey) == expected)
    }

    @Test
    func `disabled MCP server cannot retain write authority`() throws {
        let defaults = try defaults()
        defaults.set(false, forKey: MCPServer.enabledDefaultsKey)
        defaults.set(true, forKey: MCPServer.writeEnabledDefaultsKey)

        SettingsPreferenceRecovery.reconcile(defaults)

        #expect(!defaults.bool(forKey: MCPServer.writeEnabledDefaultsKey))
    }

    @Test
    func `valid configuration is preserved`() throws {
        let defaults = try defaults()
        defaults.set(AppPresence.menuBarOnly.rawValue, forKey: GeneralSettings.Key.presence)
        defaults.set(7, forKey: SettingsPreferenceRecovery.menuBarTopNKey)
        defaults.set(true, forKey: MCPServer.enabledDefaultsKey)
        defaults.set(true, forKey: MCPServer.writeEnabledDefaultsKey)

        SettingsPreferenceRecovery.reconcile(defaults)

        #expect(defaults.string(forKey: GeneralSettings.Key.presence) == AppPresence.menuBarOnly.rawValue)
        #expect(defaults.integer(forKey: SettingsPreferenceRecovery.menuBarTopNKey) == 7)
        #expect(defaults.bool(forKey: MCPServer.enabledDefaultsKey))
        #expect(defaults.bool(forKey: MCPServer.writeEnabledDefaultsKey))
    }
}
