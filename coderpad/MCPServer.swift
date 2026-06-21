//
//  MCPServer.swift
//  coderpad
//
//  A headless, in-app Model Context Protocol server (#402, #393). When the app is
//  launched with the `--mcp` flag it does NOT start the UI - it speaks MCP over stdio
//  (newline-delimited JSON-RPC 2.0) and exposes read-only CoderPad tools backed by the
//  user's saved account, reading the API key straight from the Keychain.
//
//  This is the App-Store-viable shape of the feature: the MCP client (e.g. Claude
//  Desktop) launches the app's own executable as the server, so there's no separate
//  binary to build, download, or sign - it ships and updates with the app, inside the
//  sandbox, using the account the user already configured.
//
//  Only read endpoints are exposed deliberately: a server an assistant can drive should
//  not be able to create, edit, or delete interview content.
//

import Foundation

/// Entry point and stdio run loop for the `--mcp` headless mode. Marked `nonisolated`
/// so its work runs off the main actor: the loop blocks the main thread on `readLine()`
/// while each request is handled on a background task, which would deadlock against the
/// app's default `MainActor` isolation if these types inherited it.
nonisolated enum MCPServer {
    /// Presence of this argument switches the process into headless MCP mode.
    static let commandLineFlag = "--mcp"

    /// UserDefaults key behind the "Enable the MCP server" toggle in Settings, which
    /// reveals the setup instructions. (The `--mcp` server serves whenever it's launched;
    /// the user controls it by adding or removing the MCP client configuration.)
    static let enabledDefaultsKey = "mcpServerEnabled"

    /// Reads JSON-RPC requests line by line from stdin, writes responses to stdout, and
    /// runs until stdin closes. Never returns - the process exists only to serve MCP. The
    /// credentials are resolved on the main actor by the caller (`Account` is main-actor
    /// isolated) and passed in as plain Sendable values.
    static func runUntilExit(credentials: MCPCredentials?) -> Never {
        let handler = MCPRequestHandler(credentials: credentials)
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let reply = blockingHandle(handler, line: trimmed) {
                FileHandle.standardOutput.write(Data((reply + "\n").utf8))
            }
        }
        exit(0)
    }

    /// Bridges the async request handler to the synchronous read loop. The detached task
    /// runs off-main (handler is `nonisolated`), so blocking the main thread here never
    /// deadlocks; the semaphore also publishes the box's write to this thread.
    private static func blockingHandle(_ handler: MCPRequestHandler, line: String) -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ReplyBox()
        Task.detached {
            box.reply = await handler.handle(line)
            semaphore.signal()
        }
        semaphore.wait()
        return box.reply
    }

    /// Carries one reply across the detached-task boundary. Safe because the semaphore
    /// orders the write (before `signal`) ahead of the read (after `wait`).
    private final class ReplyBox: @unchecked Sendable {
        var reply: String?
    }
}

/// The minimal, Sendable credentials the MCP tools need: an API key and the resolved
/// base URL. Extracted from the saved `Account` on the main actor so the rest of the
/// server can stay `nonisolated`.
struct MCPCredentials {
    let apiKey: String
    let baseURL: URL
}

/// Loads the account the MCP server should act as, without spinning up the full
/// `AccountsStore` (and its monitors/caches). Mirrors `AccountsStore.loadAccounts` +
/// the `currentAccountID` default, reading the same Keychain blob and UserDefaults key.
/// Main-actor isolated because decoding `Account` (and reading its properties) is.
enum MCPAccountLoader {
    @MainActor
    static func currentCredentials() -> MCPCredentials? {
        guard let data = Keychain.readData(account: Keychain.accountsAccount),
              let accounts = try? JSONDecoder()
              .decode([LenientElement<Account>].self, from: data)
              .compactMap(\.value),
              !accounts.isEmpty
        else {
            return nil
        }

        let chosen: Account = if let storedID = UserDefaults.standard.string(forKey: "currentAccountID"),
                                 let uuid = UUID(uuidString: storedID),
                                 let match = accounts.first(where: { $0.id == uuid }) {
            match
        } else {
            accounts[0]
        }

        let key = chosen.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        return MCPCredentials(apiKey: key, baseURL: chosen.resolvedBaseURL)
    }
}
