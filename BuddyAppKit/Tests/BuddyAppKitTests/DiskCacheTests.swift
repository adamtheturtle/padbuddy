//
//  DiskCacheTests.swift
//  BuddyAppKitTests
//

@testable import BuddyAppKit
import Testing

@Suite("Disk cache paths")
struct DiskCacheTests {
    @Test(arguments: ["pads", "questions_v2", "organization-cache", "A1"])
    func `safe filename tokens are accepted`(kind: String) {
        #expect(DiskCache.isValidKind(kind))
    }

    @Test(arguments: ["", ".", "..", "../pads", "nested/pads", #"nested\pads"#, "pads.json", "💾"])
    func `path-like and non-ASCII kinds are rejected`(kind: String) {
        #expect(!DiskCache.isValidKind(kind))
    }

    @Test
    func `unreasonably long kinds are rejected`() {
        #expect(!DiskCache.isValidKind(String(repeating: "a", count: 65)))
    }
}
