//
//  PadBuddyTests+ScreenTestStatus.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Screen test status")
struct ScreenTestStatusTests {
    @Test(arguments: ["waiting", "WAITING", "Waiting", " waiting \n"])
    func `waiting variants permit invitation actions`(status: String) {
        #expect(ScreenTestStatusPolicy.isWaiting(status))
    }

    @Test(arguments: [nil, "", "started", "awaiting"] as [String?])
    func `other statuses do not permit invitation actions`(status: String?) {
        #expect(!ScreenTestStatusPolicy.isWaiting(status))
    }
}
