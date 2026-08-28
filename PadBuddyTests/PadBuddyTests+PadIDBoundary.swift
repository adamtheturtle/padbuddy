//
//  PadBuddyTests+PadIDBoundary.swift
//  PadBuddyTests
//
//  Split from PadBuddyTests.swift for file length.
//

import CoderPadKit
import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad ID decoding boundary")
struct PadIDBoundaryTests {
    private func pad(_ json: String) throws -> Pad {
        try CoderPadClient.decoder.decode(Pad.self, from: Data(json.utf8))
    }

    /// A pad id that is not a single URL path component no longer reaches the app:
    /// CoderPadKit rejects it while decoding, and the page it arrived in drops that
    /// one record rather than failing. The fallback-URL hardening below still stands
    /// for the ids that do decode.
    @Test
    func `path-like pad IDs are rejected at the decoding boundary`() {
        for id in ["../outside", "bad\nslug", "", "a/b"] {
            #expect(throws: DecodingError.self) {
                try pad(#"{"id":"\#(id)"}"#)
            }
        }
    }
}
