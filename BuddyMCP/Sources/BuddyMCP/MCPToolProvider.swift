//
//  MCPToolProvider.swift
//  BuddyMCP
//
//  The seam between the reusable MCP server core and a particular app's tools (#514).
//  BuddyMCP owns the stdio loop, the JSON-RPC envelope, and account resolution; the host
//  app supplies the server identity and the tool catalogue + implementations here.
//

import Foundation

/// The result of running one tool: the text returned to the client, and whether it
/// represents an error (surfaced as MCP `isError`).
public nonisolated struct MCPToolOutcome: Sendable {
    public let text: String
    public let isError: Bool

    public init(text: String, isError: Bool) {
        self.text = text
        self.isError = isError
    }
}

/// The app-specific half of the MCP server, injected into ``MCPServer`` /
/// ``MCPRequestHandler``. Sendable so the `nonisolated` handler can carry it across the
/// detached task that services each request.
/// `nonisolated` requirements so the off-main, `nonisolated` ``MCPRequestHandler`` can
/// reach them: a conforming type supplies these from non-main-actor context too.
public protocol MCPToolProvider: Sendable {
    /// Name reported in the `initialize` handshake's `serverInfo`.
    nonisolated var serverName: String { get }
    /// Version reported in `serverInfo`.
    nonisolated var serverVersion: String { get }
    /// Returned (as an error result) when a tool is called but no account is configured.
    nonisolated var noAccountMessage: String { get }

    /// The tools advertised by `tools/list`, as MCP tool descriptor dictionaries. Given
    /// the directory so optional families (writes, secondary-key tools) can be gated on
    /// what the configured accounts permit.
    nonisolated func toolDescriptors(directory: MCPAccountDirectory) -> [[String: Any]]

    /// Runs a named tool with its JSON arguments against the directory (the tool resolves
    /// the `account` argument itself via `directory.resolve`), returning its outcome.
    nonisolated func run(name: String, arguments: [String: Any], directory: MCPAccountDirectory) async -> MCPToolOutcome
}
