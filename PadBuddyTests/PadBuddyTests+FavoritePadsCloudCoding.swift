//
//  PadBuddyTests+FavoritePadsCloudCoding.swift
//  PadBuddyTests
//

import Foundation
import Testing
@testable import PadBuddy

@Suite("Favorite pads cloud coding")
struct FavoritePadsCloudCodingTests {
    private struct EncodingFailure: Error {}

    @Test func `encoding failure does not produce a replacement cloud blob`() {
        let value: [String: [FavoritePad]] = [:]
        let encoded = FavoritePadsStore.encodeCloud(value) { _ in
            throw EncodingFailure()
        }
        #expect(encoded == nil)
    }
}
