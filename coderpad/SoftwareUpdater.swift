//
//  SoftwareUpdater.swift
//  coderpad
//

import SwiftUI

// The whole file compiles to nothing until the Sparkle Swift Package is added to
// the app target (#28), so `main` keeps building before that manual step:
//
//   Xcode ▸ File ▸ Add Package Dependencies… ▸
//   https://github.com/sparkle-project/Sparkle (pin to "Up to Next Major").
//
// Once the package is linked, `canImport(Sparkle)` flips true and this provides
// in-app updates from the appcast published alongside each GitHub Release. The
// feed URL and the EdDSA public key are read from Info.plist (SUFeedURL /
// SUPublicEDKey). See docs/sparkle-setup.md for the remaining one-time setup
// (key generation, sandbox entitlements, the release appcast secret).
#if canImport(Sparkle)
    import Sparkle

    /// Thin wrapper over Sparkle's standard updater so the rest of the app touches
    /// only this type, never Sparkle directly — keeping the dependency contained to
    /// one file and behind the `canImport` gate above.
    @MainActor
    final class SoftwareUpdater {
        static let shared = SoftwareUpdater()

        private let controller: SPUStandardUpdaterController

        private init() {
            // `startingUpdater: true` schedules Sparkle's automatic background checks,
            // governed by the user's "automatically check for updates" choice (Sparkle
            // adds its own preference UI on first run). Default delegates are fine — the
            // feed URL and EdDSA public key come from Info.plist.
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }

        /// Referencing `shared` lazily instantiates the controller (and starts the
        /// updater); call this at launch so background update checks begin even before
        /// the user ever opens the menu.
        func start() {}

        /// Backs the app menu's "Check for Updates…" command — runs Sparkle's
        /// user-initiated check, showing the update prompt or a "you're up to date"
        /// sheet as appropriate.
        func checkForUpdates() {
            controller.checkForUpdates(nil)
        }
    }

    /// The "Check for Updates…" menu item, surfaced only when Sparkle is linked.
    struct CheckForUpdatesButton: View {
        var body: some View {
            Button("Check for Updates…") {
                SoftwareUpdater.shared.checkForUpdates()
            }
        }
    }
#endif
