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
    }
#endif
