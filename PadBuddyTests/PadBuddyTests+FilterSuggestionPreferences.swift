//
//  PadBuddyTests+FilterSuggestionPreferences.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Dismissed filter suggestions (#4576)", .serialized)
@MainActor
struct FilterSuggestionPreferencesTests {
    private var preferences: FilterSuggestionPreferences {
        .shared
    }

    @Test func `a known suggestion can be dismissed`() {
        let account = UUID()
        defer { preferences.removeDismissals(account: account) }

        preferences.dismiss("my-pads", kind: .pads, account: account)

        #expect(!preferences.isVisible("my-pads", kind: .pads, account: account))
        #expect(preferences.isVisible("active", kind: .pads, account: account))
    }

    @Test func `an unknown suggestion id is not remembered`() {
        let account = UUID()
        defer { preferences.removeDismissals(account: account) }

        preferences.dismiss("made-up-\(UUID().uuidString)", kind: .pads, account: account)

        #expect(UserDefaults.standard.stringArray(
            forKey: "dismissedFilterSuggestions.v1.pads.\(account.uuidString)"
        ) == nil)
    }

    @Test func `stored ids that name nothing are pruned on read`() {
        let account = UUID()
        defer { preferences.removeDismissals(account: account) }
        let key = "dismissedFilterSuggestions.v1.pads.\(account.uuidString)"
        UserDefaults.standard.set(["my-pads", "junk-1", "junk-2"], forKey: key)

        #expect(!preferences.isVisible("my-pads", kind: .pads, account: account))

        #expect(UserDefaults.standard.stringArray(forKey: key) == ["my-pads"])
    }

    @Test func `dismissals are scoped to their kind`() {
        let account = UUID()
        defer { preferences.removeDismissals(account: account) }

        preferences.dismiss("my-questions", kind: .pads, account: account)

        #expect(preferences.isVisible("my-questions", kind: .questions, account: account))
    }

    @Test func `removing an account clears its dismissals`() {
        let account = UUID()
        preferences.dismiss("drafts", kind: .questions, account: account)

        preferences.removeDismissals(account: account)

        #expect(preferences.isVisible("drafts", kind: .questions, account: account))
    }

    @Test func `every built-in suggestion id is dismissable`() {
        // The known-id list and the suggestions that render must not drift apart, or a
        // dismiss button would silently do nothing.
        #expect(FilterSuggestionPreferences.knownIDs(kind: .pads)
            .isSuperset(of: Set(DefaultSearch.padDefaults(me: "me@acme.com").map(\.id))))
        #expect(FilterSuggestionPreferences.knownIDs(kind: .questions)
            .isSuperset(of: Set(DefaultSearch.questionDefaults(me: "me@acme.com").map(\.id))))
    }
}
