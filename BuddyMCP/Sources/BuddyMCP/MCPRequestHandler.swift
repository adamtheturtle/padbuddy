//
//  MCPRequestHandler.swift
//  BuddyMCP
//
//  JSON-RPC 2.0 request handling for the MCP server (#514). The tool catalogue and
//  implementations come from an injected ``MCPToolProvider``; this type owns the
//  envelope, dispatch, and account resolution. `nonisolated` so it runs off the main
//  actor — see ``MCPServer``.
//

import Foundation

/// Handles one MCP JSON-RPC message at a time and returns the response line to write
/// back (or `nil` for notifications, which take no reply).
public nonisolated struct MCPRequestHandler: Sendable {
    /// The app's tool catalogue + implementations.
    let provider: any MCPToolProvider
    /// The accounts the tools can act as. Empty when no account is configured yet.
    let directory: MCPAccountDirectory
    /// Called after each `tools/call` with the tool name, the served account's display
    /// name (if any), and whether it succeeded — for the host's activity log. Never sees
    /// the arguments.
    let onCall: @Sendable (_ tool: String, _ account: String?, _ succeeded: Bool) -> Void

    /// The tool argument that selects which account to act as.
    static let accountArgument = "account"

    /// MCP protocol version this server implements; echoed back to the client unless the
    /// client requests a specific one during `initialize`.
    private static let protocolVersion = "2025-06-18"

    public init(
        provider: any MCPToolProvider,
        directory: MCPAccountDirectory,
        onCall: @escaping @Sendable (String, String?, Bool) -> Void = { _, _, _ in }
    ) {
        self.provider = provider
        self.directory = directory
        self.onCall = onCall
    }

    public func handle(_ line: String) async -> String? {
        guard let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Self.errorResponse(id: nil, code: -32700, message: "Parse error")
        }

        let method = message["method"] as? String ?? ""
        // Notifications (no `id`) never get a reply - that includes
        // `notifications/initialized`, which the client sends after `initialize`.
        let id = message["id"]
        let isNotification = id == nil

        switch method {
        case "initialize":
            return initializeResponse(id: id, params: message["params"] as? [String: Any])

        case "tools/list":
            return toolsListResponse(id: id)

        case "tools/call":
            return await toolsCallResponse(id: id, params: message["params"] as? [String: Any])

        case "ping":
            return Self.successResponse(id: id, result: [:])

        default:
            if isNotification { return nil }
            return Self.errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - Method handlers

    private func initializeResponse(id: Any?, params: [String: Any]?) -> String {
        let version = (params?["protocolVersion"] as? String) ?? Self.protocolVersion
        let result: [String: Any] = [
            "protocolVersion": version,
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": [
                "name": provider.serverName,
                "version": provider.serverVersion
            ]
        ]
        return Self.successResponse(id: id, result: result)
    }

    private func toolsListResponse(id: Any?) -> String {
        Self.successResponse(id: id, result: [
            "tools": provider.toolDescriptors(directory: directory)
        ])
    }

    private func toolsCallResponse(id: Any?, params: [String: Any]?) async -> String {
        guard let name = params?["name"] as? String else {
            return Self.errorResponse(id: id, code: -32602, message: "Missing tool name")
        }

        let arguments = params?["arguments"] as? [String: Any] ?? [:]

        guard !directory.accounts.isEmpty else {
            return Self.toolResultResponse(id: id, text: provider.noAccountMessage, isError: true)
        }

        let outcome = await provider.run(name: name, arguments: arguments, directory: directory)
        // Report the call (tool name + served account + ok/error only — never arguments)
        // so the host can show recent activity.
        let served = directory.resolve(arguments[Self.accountArgument] as? String)?.accountName
            ?? directory.current?.accountName
        onCall(name, served, !outcome.isError)
        return Self.toolResultResponse(id: id, text: outcome.text, isError: outcome.isError)
    }

    // MARK: - JSON-RPC envelope helpers

    /// Wraps a tool's text in the MCP `CallTool` result shape.
    private static func toolResultResponse(id: Any?, text: String, isError: Bool) -> String {
        var result: [String: Any] = ["content": [["type": "text", "text": text]]]
        if isError { result["isError"] = true }
        return successResponse(id: id, result: result)
    }

    static func successResponse(id: Any?, result: [String: Any]) -> String {
        encode(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    static func errorResponse(id: Any?, code: Int, message: String) -> String {
        encode(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])
    }

    /// Serializes a JSON-RPC object to a single line. Falls back to a hand-built parse
    /// error if serialization somehow fails, so the client always gets valid JSON-RPC.
    private static func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
        }

        return string
    }
}
