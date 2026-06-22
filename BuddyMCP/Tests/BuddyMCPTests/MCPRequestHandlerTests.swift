//
//  MCPRequestHandlerTests.swift
//  BuddyMCPTests
//
//  Drives the JSON-RPC dispatch through a fake provider (#514): the initialize /
//  tools/list / tools/call handshake the server's acceptance calls for, plus the
//  no-account and notification paths — all without stdio or any app dependency.
//

import BuddyMCP
import Foundation
import Testing

private struct FakeProvider: MCPToolProvider {
    let serverName = "test-server"
    let serverVersion = "9.9"
    let noAccountMessage = "no account configured"

    func toolDescriptors(directory: MCPAccountDirectory) -> [[String: Any]] {
        var tools: [[String: Any]] = [["name": "echo", "description": "Echoes its text argument"]]
        if directory.allowWrites { tools.append(["name": "write", "description": "A write tool"]) }
        return tools
    }

    func run(name: String, arguments: [String: Any], directory _: MCPAccountDirectory) async -> MCPToolOutcome {
        switch name {
        case "echo": MCPToolOutcome(text: "echoed:\(arguments["text"] as? String ?? "")", isError: false)
        default: MCPToolOutcome(text: "unknown tool \(name)", isError: true)
        }
    }
}

/// Collects `onCall` reports from the (`@Sendable`) handler callback. The handler invokes
/// it synchronously within `handle`, so a simple lock-free reference is enough here.
private final nonisolated class CallRecorder: @unchecked Sendable {
    private(set) var calls: [(tool: String, account: String?, succeeded: Bool)] = []
    func record(_ tool: String, _ account: String?, _ succeeded: Bool) {
        calls.append((tool, account, succeeded))
    }
}

private func parse(_ line: String?) -> [String: Any] {
    guard let line, let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }

    return object
}

private let oneAccount = MCPAccountDirectory(
    accounts: [MCPCredentials(id: "1", apiKey: "k", baseURL: URL(string: "https://example.com")!,
                              accountName: "Acme", userEmail: "a@example.com")],
    currentID: "1"
)

@Suite("MCP request handler dispatch")
struct MCPRequestHandlerTests {
    @Test
    func `initialize echoes the provider's server identity`() async {
        let handler = MCPRequestHandler(provider: FakeProvider(), directory: oneAccount)
        let response = await parse(handler.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#))
        let serverInfo = (response["result"] as? [String: Any])?["serverInfo"] as? [String: Any]
        #expect(serverInfo?["name"] as? String == "test-server")
        #expect(serverInfo?["version"] as? String == "9.9")
    }

    @Test
    func `tools-list returns the provider's catalogue and gates writes`() async {
        let readOnly = MCPRequestHandler(provider: FakeProvider(), directory: oneAccount)
        let names = await toolNames(readOnly)
        #expect(names == ["echo"])

        var writable = oneAccount
        writable.allowWrites = true
        let names2 = await toolNames(MCPRequestHandler(provider: FakeProvider(), directory: writable))
        #expect(names2.contains("write"))
    }

    @Test
    func `tools-call runs the named tool and reports the served account`() async {
        let recorder = CallRecorder()
        let handler = MCPRequestHandler(provider: FakeProvider(), directory: oneAccount,
                                        onCall: { recorder.record($0, $1, $2) })
        let line = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hi"}}}"#
        let result = await parse(handler.handle(line))["result"] as? [String: Any]
        let content = (result?["content"] as? [[String: Any]])?.first
        #expect(content?["text"] as? String == "echoed:hi")
        #expect(result?["isError"] == nil)
        #expect(recorder.calls.count == 1)
        #expect(recorder.calls.first?.tool == "echo")
        #expect(recorder.calls.first?.account == "Acme")
        #expect(recorder.calls.first?.succeeded == true)
    }

    @Test
    func `tools-call with no account returns the provider's message as an error`() async {
        let empty = MCPAccountDirectory(accounts: [], currentID: nil)
        let handler = MCPRequestHandler(provider: FakeProvider(), directory: empty)
        let line = #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{}}}"#
        let result = await parse(handler.handle(line))["result"] as? [String: Any]
        #expect(result?["isError"] as? Bool == true)
        let content = (result?["content"] as? [[String: Any]])?.first
        #expect(content?["text"] as? String == "no account configured")
    }

    @Test
    func `an unknown notification gets no reply`() async {
        let handler = MCPRequestHandler(provider: FakeProvider(), directory: oneAccount)
        let reply = await handler.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        #expect(reply == nil)
    }

    private func toolNames(_ handler: MCPRequestHandler) async -> [String] {
        let response = await parse(handler.handle(#"{"jsonrpc":"2.0","id":9,"method":"tools/list"}"#))
        let tools = (response["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
        return tools.compactMap { $0["name"] as? String }
    }
}
