//
//  Models.swift
//  CoderPadMCPCore
//
//  The network-free core of the standalone CoderPad MCP server (#393), split out
//  of the executable so it can be unit-tested (#522) and, in time, shared with the
//  in-app server (#521). Everything here is pure: argument coercion, tool schemas,
//  and the pad code / count / aggregate transforms. The executable (`coderpad-mcp`)
//  keeps the env reading, the REST calls, and the stdio server wiring.
//

import Foundation

/// The status and raw JSON body of a CoderPad REST call. The body is passed through
/// verbatim to the MCP client rather than decoded — the API's JSON is already the
/// most useful representation for an assistant, and passing it through keeps the
/// server resilient to schema additions.
public struct APIResponse: Sendable {
    public let status: Int
    public let body: String

    public init(status: Int, body: String) {
        self.status = status
        self.body = body
    }

    public var ok: Bool {
        (200 ..< 300).contains(status)
    }
}
