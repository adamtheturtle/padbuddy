//
//  PadBuddyTests+MCPAccountCacheEncoding.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

#if os(macOS)
    @Suite("MCP account cache encoding")
    struct MCPAccountCacheEncodingTests {
        private struct EncodeFailure: LocalizedError {
            var errorDescription: String? {
                "Invalid date"
            }
        }

        @Test func `failure retains the affected cache kind`() {
            let outcome = MCPAccountCacheEncoding.evaluate(["record"], kind: "pads") { _ in
                throw EncodeFailure()
            }

            guard case let .failed(message) = outcome else {
                Issue.record("Expected cache encoding failure")
                return
            }

            #expect(message == "Could not encode the pads MCP cache: Invalid date")
        }

        @Test func `freshness accepts only bounded past age and small forward skew`() {
            let now = Date(timeIntervalSince1970: 1_700_000_000)

            #expect(MCPAccountCacheFreshness.isFresh(written: now, now: now))
            #expect(MCPAccountCacheFreshness.isFresh(
                written: now.addingTimeInterval(MCPAccountCacheFreshness.maxFutureClockSkew), now: now
            ))
            #expect(!MCPAccountCacheFreshness.isFresh(
                written: now.addingTimeInterval(MCPAccountCacheFreshness.maxFutureClockSkew + 1), now: now
            ))
            #expect(!MCPAccountCacheFreshness.isFresh(
                written: now.addingTimeInterval(-MCPAccountCacheFreshness.maxAge - 1), now: now
            ))
        }
    }
#endif
