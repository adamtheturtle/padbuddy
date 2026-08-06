//
//  PadBuddyTests+ScreenDates.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Foundation
import Testing

@Suite("Screen epoch timestamps")
struct ScreenEpochTimestampTests {
    @Test(arguments: [Int.min, -1, 0, 946_684_799_999, 4_102_444_800_001, Int.max])
    func `impossible timestamps do not become dates`(milliseconds: Int) {
        #expect(ScreenEpochMilliseconds.date(from: milliseconds) == nil)
    }

    @Test
    func `session decoding rejects an impossible timestamp`() {
        let json = #"{"id":1,"status":"waiting","send_time":9223372036854775807}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScreenTestSession.self, from: Data(json.utf8))
        }
    }

    @Test
    func `valid boundary timestamps convert`() {
        #expect(ScreenEpochMilliseconds.date(from: ScreenEpochMilliseconds.earliest) != nil)
        #expect(ScreenEpochMilliseconds.date(from: ScreenEpochMilliseconds.latest) != nil)
    }
}
