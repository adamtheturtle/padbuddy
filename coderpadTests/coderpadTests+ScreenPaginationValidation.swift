//
//  coderpadTests+ScreenPaginationValidation.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Screen pagination validation")
struct ScreenPaginationValidationTests {
    @Test
    func `negative offsets counts and nonpositive limits are rejected`() {
        for json in [
            #"{"start":-1}"#,
            #"{"limit":0}"#,
            #"{"limit":-1}"#,
            #"{"total":-1}"#,
            #"{"next_start":-1}"#
        ] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(ScreenPagination.self, from: Data(json.utf8))
            }
        }
    }

    @Test
    func `zero offsets and total with a positive limit are valid`() throws {
        let page = try JSONDecoder().decode(
            ScreenPagination.self,
            from: Data(#"{"start":0,"limit":1,"total":0,"next_start":0}"#.utf8)
        )

        #expect(page.start == 0)
        #expect(page.limit == 1)
        #expect(page.total == 0)
        #expect(page.nextStart == 0)
    }
}
