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
    }
#endif
