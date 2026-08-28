//
//  PadBuddyTests+PreferenceValidationIssues.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Preference validation issues")
@MainActor
struct PreferenceValidationIssueTests {
    private let sync = PreferenceCloudSync.shared

    private func withCleanIssues(_ body: () -> Void) {
        let saved = sync.validationIssues
        defer { sync.validationIssues = saved }
        sync.validationIssues = []
        body()
    }

    /// A single slot was overwritten unconditionally, and both callers loop over
    /// `syncedKeys`, so only the last invalid key was ever visible (#4808).
    @Test func `every invalid key is retained, in the order raised`() {
        withCleanIssues {
            sync.reportValidationIssue(for: "general.appearance")
            sync.reportValidationIssue(for: "browser.defaultBrowserBundleID")

            #expect(sync.validationIssues.map(\.key)
                == ["general.appearance", "browser.defaultBrowserBundleID"])
            #expect(sync.validationIssue?.key == "general.appearance")
        }
    }

    @Test func `re-reporting one key does not duplicate it`() {
        withCleanIssues {
            sync.reportValidationIssue(for: "general.appearance")
            sync.reportValidationIssue(for: "general.appearance")

            #expect(sync.validationIssues.count == 1)
        }
    }

    @Test func `dismissing presents the next issue rather than discarding it`() {
        withCleanIssues {
            sync.reportValidationIssue(for: "general.appearance")
            sync.reportValidationIssue(for: "browser.openInBackground")

            sync.dismissValidationIssue()

            #expect(sync.validationIssue?.key == "browser.openInBackground")
        }
    }

    @Test func `clearing one key leaves the others`() {
        withCleanIssues {
            sync.reportValidationIssue(for: "general.appearance")
            sync.reportValidationIssue(for: "browser.openInBackground")

            sync.clearValidationIssue(for: "general.appearance")

            #expect(sync.validationIssues.map(\.key) == ["browser.openInBackground"])
        }
    }

    /// Sort orders and merged live filters have no Settings control, so an alert
    /// sending the user to a tab had no remedy behind it (#4807).
    @Test func `keys with no settings control raise no user-facing issue`() {
        withCleanIssues {
            for key in PreferenceCloudSync.silentlyDiscardedKeys {
                sync.reportValidationIssue(for: key)
            }

            #expect(sync.validationIssues.isEmpty)
        }
    }

    /// Every remaining key that can raise an issue must reach a tab that actually
    /// owns it, which is what the discard list is protecting.
    @Test func `every reportable synced key is either named or discarded`() {
        withCleanIssues {
            for key in PreferenceCloudSync.syncedKeys {
                sync.reportValidationIssue(for: key)
            }

            let raised = Set(sync.validationIssues.map(\.key))
            #expect(raised.isDisjoint(with: PreferenceCloudSync.silentlyDiscardedKeys))
            // A key with no label would be shown to the user as its raw defaults key.
            #expect(sync.validationIssues.allSatisfy { $0.settingName != $0.key })
        }
    }
}
