//
//  WelcomePresentationPolicy.swift
//  coderpad
//

import Foundation

/// Decides whether a window displays first-run content without coupling previews or
/// development schemes to the Keychain-backed account store.
nonisolated enum WelcomePresentationPolicy {
    static let launchArgument = "-showWelcome"

    static func shouldShow(
        hasAccounts: Bool,
        arguments: [String],
        isDebugBuild: Bool = debugBuild
    ) -> Bool {
        !hasAccounts || (isDebugBuild && arguments.contains(launchArgument))
    }

    private static var debugBuild: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }
}
