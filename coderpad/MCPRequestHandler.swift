//
//  MCPRequestHandler.swift
//  coderpad
//
//  The JSON-RPC 2.0 request handling and the read-only tool set for the in-app MCP
//  server (#402). Kept separate from the stdio run loop in `MCPServer.swift`.
//

import Foundation

/// Handles one MCP JSON-RPC message at a time and returns the response line to write
/// back (or `nil` for notifications, which take no reply). `nonisolated` so it runs off
/// the main actor — see `MCPServer`.
nonisolated struct MCPRequestHandler {
    /// The credentials the tools act as, or `nil` if no account is configured yet.
    let credentials: MCPCredentials?

    /// MCP protocol version this server implements; echoed back to the client unless the
    /// client requests a specific one during `initialize`.
    private static let protocolVersion = "2025-06-18"

    func handle(_ line: String) async -> String? {
        guard let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Self.errorResponse(id: nil, code: -32700, message: "Parse error")
        }

        let method = message["method"] as? String ?? ""
        // Notifications (no `id`) never get a reply — that includes
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
                "name": "padbuddy-coderpad",
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            ]
        ]
        return Self.successResponse(id: id, result: result)
    }

    private func toolsListResponse(id: Any?) -> String {
        Self.successResponse(id: id, result: ["tools": MCPTools.all])
    }

    private func toolsCallResponse(id: Any?, params: [String: Any]?) async -> String {
        guard let name = params?["name"] as? String else {
            return Self.errorResponse(id: id, code: -32602, message: "Missing tool name")
        }

        let arguments = params?["arguments"] as? [String: Any] ?? [:]

        guard let credentials else {
            return Self.toolResultResponse(
                id: id,
                text: """
                No CoderPad account is configured in PadBuddy. Open the app, add an \
                account with an API key, then try again.
                """,
                isError: true
            )
        }

        let outcome = await MCPTools.run(name: name, arguments: arguments, credentials: credentials)
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
