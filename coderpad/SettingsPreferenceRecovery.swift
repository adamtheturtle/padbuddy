//
//  SettingsPreferenceRecovery.swift
//  coderpad
//

import CoreFoundation
import Foundation

/// Repairs related settings as one launch-time transaction before any subsystem
/// consumes them. `@AppStorage` persists fields independently, so a crash or an
/// external defaults write can otherwise leave an impossible combination behind.
nonisolated enum SettingsPreferenceRecovery {
    static let menuBarTopNKey = "menuBarTopN"
    static let menuBarTopNRange = 0 ... 30

    static func reconcile(_ defaults: UserDefaults) {
        if let rawPresence = defaults.string(forKey: GeneralSettings.Key.presence),
           AppPresence(rawValue: rawPresence) == nil {
            defaults.set(AppPresence.dockAndMenuBar.rawValue, forKey: GeneralSettings.Key.presence)
        }

        if let storedTopN = integer(defaults.object(forKey: menuBarTopNKey)) {
            defaults.set(min(max(storedTopN, menuBarTopNRange.lowerBound), menuBarTopNRange.upperBound),
                         forKey: menuBarTopNKey)
        } else if defaults.object(forKey: menuBarTopNKey) != nil {
            defaults.set(3, forKey: menuBarTopNKey)
        }

        let enabled = boolean(defaults.object(forKey: MCPServer.enabledDefaultsKey)) ?? false
        let writes = boolean(defaults.object(forKey: MCPServer.writeEnabledDefaultsKey)) ?? false
        defaults.set(enabled, forKey: MCPServer.enabledDefaultsKey)
        defaults.set(enabled && writes, forKey: MCPServer.writeEnabledDefaultsKey)
        if !enabled {
            defaults.removeObject(forKey: MCPServer.writableAccountIDsDefaultsKey)
        } else if let identifiers = defaults.stringArray(forKey: MCPServer.writableAccountIDsDefaultsKey) {
            defaults.set(identifiers.compactMap(UUID.init(uuidString:)).map(\.uuidString),
                         forKey: MCPServer.writableAccountIDsDefaultsKey)
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        // UserDefaults bridges every stored plist number through NSNumber; the
        // CoreFoundation type id is how Bool is distinguished from an integer.
        // swiftlint:disable:next legacy_objc_type
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }

        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double,
              double >= Double(Int.min), double <= Double(Int.max) else { return nil }

        return Int(double)
    }

    private static func boolean(_ value: Any?) -> Bool? {
        // See `integer(_:)`: exact CFBoolean identity rejects strings and numbers.
        // swiftlint:disable:next legacy_objc_type
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }

        return number.boolValue
    }
}
