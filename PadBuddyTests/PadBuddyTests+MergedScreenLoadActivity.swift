//
//  PadBuddyTests+MergedScreenLoadActivity.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Merged Screen load activity")
struct MergedScreenLoadActivityTests {
    @Test func `loading remains active until every overlapping load finishes`() {
        var activity = MergedScreenLoadActivity()
        activity.begin()
        activity.begin()

        activity.finish()
        #expect(activity.isLoading)
        #expect(activity.count == 1)

        activity.finish()
        #expect(!activity.isLoading)
    }
}
