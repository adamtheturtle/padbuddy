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
            #"{"start":-1,"has_more_items":false}"#,
            #"{"limit":0,"has_more_items":false}"#,
            #"{"limit":-1,"has_more_items":false}"#,
            #"{"total":-1,"has_more_items":false}"#,
            #"{"next_start":-1,"has_more_items":false}"#
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
            from: Data(#"{"start":0,"limit":1,"total":0,"next_start":0,"has_more_items":false}"#.utf8)
        )

        #expect(page.start == 0)
        #expect(page.limit == 1)
        #expect(page.total == 0)
        #expect(page.nextStart == 0)
    }

    @Test
    func `has more items is required and must be boolean`() {
        for json in [
            #"{}"#,
            #"{"has_more_items":"false"}"#,
            #"{"has_more_items":0}"#,
            #"{"has_more_items":null}"#
        ] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(ScreenPagination.self, from: Data(json.utf8))
            }
        }
    }

    @Test
    func `invalid nested pagination fails the page instead of truncating it`() {
        let json = #"{"tests":[],"pagination":{"has_more_items":"false"}}"#

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScreenTestsPage.self, from: Data(json.utf8))
        }
    }

    @Test(arguments: [
        #"{}"#,
        #"{"tests":null}"#,
        #"{"tests":{}}"#,
        #"{"tests":"not an array"}"#
    ])
    func `tests is a required array`(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScreenTestsPage.self, from: Data(json.utf8))
        }
    }

    @Test
    func `an explicitly empty tests array remains a valid page`() throws {
        let page = try JSONDecoder().decode(ScreenTestsPage.self, from: Data(#"{"tests":[]}"#.utf8))
        #expect(page.tests.isEmpty)
        #expect(page.discardedTestCount == 0)
    }
}
