//
//  PadBuddyTests+BrowserPreference.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

#if os(macOS)
    @Suite("Chosen browser preference")
    @MainActor
    struct BrowserPreferenceTests {
        /// A read-path validator used to delete the stored choice. It answers from a
        /// browser cache invalidated only by the Settings pane, so one stale or
        /// incomplete scan erased a preference the user had to notice was gone before
        /// they could restore it (#4789).
        @Test func `an unrecognized browser is not resolved but is not erased`() {
            let key = BrowserSettings.Key.defaultBrowserBundleID
            let saved = UserDefaults.standard.string(forKey: key)
            defer {
                if let saved {
                    UserDefaults.standard.set(saved, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            let chosen = "com.example.not-installed-\(UUID().uuidString)"
            UserDefaults.standard.set(chosen, forKey: key)

            #expect(BrowserSettings.validatedBrowserBundleID() == nil)
            #expect(UserDefaults.standard.string(forKey: key) == chosen)
        }

        @Test func `no stored choice resolves to the system default`() {
            let key = BrowserSettings.Key.defaultBrowserBundleID
            let saved = UserDefaults.standard.string(forKey: key)
            defer {
                if let saved {
                    UserDefaults.standard.set(saved, forKey: key)
                }
            }
            UserDefaults.standard.removeObject(forKey: key)

            #expect(BrowserSettings.validatedBrowserBundleID() == nil)
        }

        @Test func `an unavailable synced choice remains selectable in settings`() {
            let installed = [InstalledBrowser(bundleID: "com.example.available", name: "Available")]
            let chosen = "com.example.other-mac"

            let options = BrowserSettings.pickerBrowsers(
                installed: installed,
                chosenBundleID: chosen
            )

            #expect(options.map(\.bundleID) == ["com.example.available", chosen])
            #expect(options.last?.name == "Unavailable on this Mac")
        }

        @Test func `an installed synced choice is not duplicated in settings`() {
            let installed = [InstalledBrowser(bundleID: "com.example.available", name: "Available")]

            #expect(BrowserSettings.pickerBrowsers(
                installed: installed,
                chosenBundleID: "com.example.available"
            ) == installed)
        }
    }
#endif
