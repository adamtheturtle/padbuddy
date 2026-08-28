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

@Suite("Interrupted preference mirroring (#4644)", .serialized)
@MainActor
struct InterruptedPreferenceMirrorTests {
    private let key = "general.notifyOnPadUpdates"

    private func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: PreferenceCloudSync.localRevisionKey(key))
    }

    @Test func `a value matching the cloud is not treated as unmirrored`() {
        defer { clear() }
        UserDefaults.standard.set(false, forKey: key)
        UserDefaults.standard.removeObject(forKey: PreferenceCloudSync.localRevisionKey(key))

        // Nothing stamped locally, nothing in the cloud: no pending upload.
        #expect(!PreferenceCloudSync.hasUnmirroredLocalEdit(key: key))
    }

    @Test func `a local value stamped newer than the cloud is pending upload`() {
        defer { clear() }
        // Exactly the state a crash between stamping the revision and writing the value
        // leaves behind: local differs, and its revision is newer.
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.set(
            Date.timeIntervalSinceReferenceDate, forKey: PreferenceCloudSync.localRevisionKey(key)
        )

        #expect(PreferenceCloudSync.hasUnmirroredLocalEdit(key: key))
    }

    @Test func `an unstamped local value is not mistaken for a pending upload`() {
        defer { clear() }
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.set(0.0, forKey: PreferenceCloudSync.localRevisionKey(key))

        // No local revision means this device never wrote it, so there is nothing to
        // retry — mirroring it would push an unpulled cloud value back.
        #expect(!PreferenceCloudSync.hasUnmirroredLocalEdit(key: key))
    }
}
