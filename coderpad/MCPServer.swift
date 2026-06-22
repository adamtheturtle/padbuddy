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
//  The reusable server core - the stdio loop, JSON-RPC dispatch, and account model -
//  lives in the BuddyMCP package (#514). This file keeps the CoderPad-specific glue:
//  the launch flag and settings keys, and the loader that turns saved accounts into the
//  package's `MCPAccountDirectory`. The tool catalogue is supplied by `CoderPadToolProvider`.
//

import BuddyMCP
import Foundation

/// CoderPad-specific entry glue for the `--mcp` headless mode.
nonisolated enum MCPServer {
    /// Presence of this argument switches the process into headless MCP mode.
    static let commandLineFlag = "--mcp"

    /// UserDefaults key behind the "Enable the MCP server" toggle in Settings, which
    /// reveals the setup instructions. (The `--mcp` server serves whenever it's launched;
    /// the user controls it by adding or removing the MCP client configuration.)
    static let enabledDefaultsKey = "mcpServerEnabled"

    /// UserDefaults key behind the separate "Allow the MCP server to make changes" opt-in
    /// (#502). Off by default: the write tools are only advertised and usable when this is
    /// on, so an assistant can never create or edit interview content unless the user has
    /// deliberately enabled it. Read in `MCPAccountLoader.directory()` on the main actor
    /// (alongside the accounts), not as the first thing in the launch path - reading
    /// `UserDefaults.standard` too early hung the sandboxed direct-exec binary (#402).
    static let writeEnabledDefaultsKey = "mcpServerAllowWrites"

    /// Serves MCP over stdio until stdin closes, using the CoderPad tool catalogue. The
    /// directory is resolved by the caller on the main actor (`Account` is main-actor
    /// isolated); the BuddyMCP loop then runs nonisolated. Tool activity is forwarded to
    /// `MCPActivityLog` so the app's status view can show it (#523). Never returns.
    static func runUntilExit(directory: MCPAccountDirectory) -> Never {
        BuddyMCP.MCPServer.runUntilExit(
            provider: CoderPadToolProvider(),
            directory: directory,
            onLaunch: { MCPActivityLog.recordLaunch(account: $0) },
            onCall: { MCPActivityLog.recordCall(tool: $0, account: $1, succeeded: $2) }
        )
    }
}

/// Loads the accounts the MCP server can act as, without spinning up the full
/// `AccountsStore` (and its monitors/caches). Mirrors the account decode + the
/// `currentAccountID` default, reading the same Keychain blob and UserDefaults key.
/// Main-actor isolated because decoding `Account` (and reading its properties) is.
enum MCPAccountLoader {
    @MainActor
    static func directory() -> MCPAccountDirectory {
        guard let data = Keychain.readData(account: Keychain.accountsAccount),
              let accounts = try? JSONDecoder()
              .decode([LenientElement<Account>].self, from: data)
              .compactMap(\.value)
        else {
            return MCPAccountDirectory(accounts: [], currentID: nil)
        }

        // Drop accounts without a usable key (e.g. an in-progress draft), and the demo
        // account: its mock key only works against the in-process mock server the headless
        // process doesn't run, so serving it would send a fake key to the real API and 401
        // ("Invalid API key"). Each remaining account becomes one selectable identity. The
        // Screen key maps onto the package's generic "secondary" credentials slot.
        let credentials: [MCPCredentials] = accounts.compactMap { account in
            guard !account.isMock else { return nil }

            let key = account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }

            let screenKey = account.screenApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasScreen = !(screenKey ?? "").isEmpty

            return MCPCredentials(
                id: account.id.uuidString,
                apiKey: key,
                baseURL: account.resolvedBaseURL,
                accountName: account.name,
                userEmail: account.userEmail,
                secondaryApiKey: hasScreen ? screenKey : nil,
                secondaryBaseURL: hasScreen ? account.screenRegion.baseURL : nil
            )
        }

        let currentID = UserDefaults.standard.string(forKey: "currentAccountID")
            .flatMap { UUID(uuidString: $0) }?.uuidString
        let allowWrites = UserDefaults.standard.bool(forKey: MCPServer.writeEnabledDefaultsKey)
        return MCPAccountDirectory(accounts: credentials, currentID: currentID, allowWrites: allowWrites)
    }
}
