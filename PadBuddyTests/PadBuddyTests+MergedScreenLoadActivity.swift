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

    @Test func `stale completion cannot finish the current generation`() {
        var activity = MergedScreenLoadActivity()
        activity.begin(generation: 1)
        activity.clear(generation: 2)
        activity.begin(generation: 3)

        activity.finish(generation: 1)
        #expect(activity.isLoading)

        activity.finish(generation: 3)
        #expect(!activity.isLoading)
    }
}
