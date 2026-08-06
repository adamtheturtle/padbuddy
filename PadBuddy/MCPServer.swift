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
//  The protocol layer - the stdio transport and JSON-RPC 2.0 dispatch - is the official
//  MCP Swift SDK (the same `Server`/`StdioTransport` the standalone `coderpad-mcp` CLI
//  uses), so both servers share one maintained implementation. This file keeps the
//  CoderPad-specific glue: the launch flag and settings keys, the loader that turns saved
//  accounts into an `MCPAccountDirectory`, and the handlers that advertise and run the
//  CoderPad `MCPTools` over the SDK.
//

#if os(macOS)
    import CoderPadMCP
    import Foundation
    import MCP
    import MCPKit
#else
    import Foundation
#endif

/// CoderPad-specific entry glue for the `--mcp` headless mode.
nonisolated enum MCPServer {
    /// Presence of this argument switches the process into headless MCP mode.
    static let commandLineFlag = "--mcp"
    static let healthCheckFlag = "--mcp-health-check"

    /// The MCP server identity reported in the `initialize` handshake's `serverInfo`.
    private static let serverName = "PadBuddy"

    /// The version reported in `serverInfo`, taken from the app bundle.
    private static var serverVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// UserDefaults key behind the "Enable the MCP server" toggle in Settings. It reveals
    /// the setup instructions in the pane and gates serving itself: a `--mcp` launch checks
    /// it and refuses to serve while it's off (#811), so turning the toggle off genuinely
    /// cuts off assistants whose configs still point at the app.
    static let enabledDefaultsKey = "mcpServerEnabled"

    /// UserDefaults key behind the separate "Allow the MCP server to make changes" opt-in
    /// (#502). Off by default: the write tools are only advertised and usable when this is
    /// on, so an assistant can never create or edit interview content unless the user has
    /// deliberately enabled it. Read in `MCPAccountLoader.directory()` on the main actor
    /// (alongside the accounts), not as the first thing in the launch path - reading
    /// `UserDefaults.standard` too early hung the sandboxed direct-exec binary (#402).
    static let writeEnabledDefaultsKey = "mcpServerAllowWrites"
    static let writableAccountIDsDefaultsKey = "mcpServerWritableAccountIDs"

    #if os(macOS)
        /// Serves MCP over stdio until stdin closes, using the CoderPad tool catalogue. The
        /// directory is resolved by the caller on the main actor (`Account` is main-actor
        /// isolated); the SDK's actor-based server then runs nonisolated. Tool activity is
        /// forwarded to `MCPActivityLog` so the app's status view can show it (#523). Never
        /// returns: MCPKit's shared stdio bootstrap blocks on the async server until stdin
        /// closes, then exits.
        ///
        /// The `isEnabled:` gate mirrors the Settings toggle (#811): assistants keep their
        /// installed config after the user turns the server off, so the launch itself must
        /// refuse to serve, with a stderr message telling the user how to re-enable it. Reading
        /// UserDefaults here is safe: the caller has already read it while resolving the
        /// directory, past the too-early-read hang from #402.
        static func runUntilExit(accountSet: MCPAccountSet) -> Never {
            let provider = CoderPadProvider(accountSet: accountSet, cache: MCPAccountLoader.cache) { activity in
                MCPActivityLog.recordCall(
                    tool: activity.tool,
                    account: activity.accountName,
                    succeeded: activity.succeeded,
                    failureReason: activity.failureReason
                )
            }
            MCPKit.MCPServer.runOverStdioUntilExit(
                name: serverName,
                version: serverVersion,
                isEnabled: { UserDefaults.standard.bool(forKey: enabledDefaultsKey) },
                disabledMessage: "The PadBuddy MCP server is turned off. Turn on \u{201C}Enable the "
                    + "MCP server\u{201D} in PadBuddy's Settings > MCP Server, then restart this assistant.",
                onLaunch: { MCPActivityLog.recordLaunch(account: accountSet.defaultAccount?.name) },
                provider: provider
            )
        }
    #endif
}

#if os(macOS)
    /// Loads the accounts the MCP server can act as, without spinning up the full
    /// `AccountsStore` (and its monitors/caches). Mirrors the account decode + the
    /// `currentAccountID` default, reading the same Keychain blob and UserDefaults key.
    /// Main-actor isolated because decoding `Account` (and reading its properties) is.
    enum MCPAccountLoader {
        nonisolated static let cache = CoderPadMCPCache(
            load: { kind, accountID, requireFresh in
                guard let account = UUID(uuidString: accountID) else { return nil }

                if requireFresh {
                    guard let written = CacheDisk.modificationDate(kind: kind.rawValue, account: account),
                          Date().timeIntervalSince(written) <= 10 * 60
                    else {
                        return nil
                    }
                }

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                switch kind {
                case .pads:
                    guard let records = CacheDisk.load([Pad].self, kind: kind.rawValue, account: account) else {
                        return nil
                    }

                    return try? encoder.encode(records)

                case .questions:
                    guard let records = CacheDisk.load([Question].self, kind: kind.rawValue, account: account) else {
                        return nil
                    }

                    return try? encoder.encode(records)
                }
            },
            invalidate: { kind, accountID in
                guard let account = UUID(uuidString: accountID) else { return }

                await MainActor.run {
                    switch kind {
                    case .pads: PadsCacheStore.shared.invalidateSnapshot(account)
                    case .questions: QuestionsCacheStore.shared.invalidateSnapshot(account)
                    }
                }
                CacheDisk.delete(kind: kind.rawValue, account: account)
            }
        )

        @MainActor
        static func accountSet() -> MCPAccountSet {
            guard let data = Keychain.readData(account: Keychain.accountsAccount),
                  let accounts = try? JSONDecoder()
                  .decode([LenientElement<Account>].self, from: data)
                  .compactMap(\.value)
            else {
                return MCPAccountSet(accounts: [], defaultName: "", allowWrites: false)
            }

            // Drop accounts without a usable key (e.g. an in-progress draft), and the demo
            // account: its mock key only works against the in-process mock server the headless
            // process doesn't run, so serving it would send a fake key to the real API and 401
            // ("Invalid API key"). Each remaining account becomes one selectable identity. The
            // Screen key maps onto the package's generic "secondary" credentials slot.
            let writableAccountIDs = Set(UserDefaults.standard
                .stringArray(forKey: MCPServer.writableAccountIDsDefaultsKey) ?? [])
            let credentials: [MCPAccount] = accounts.compactMap { account -> MCPAccount? in
                guard !account.isMock else { return nil }

                let key = account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return nil }

                let screenKey = account.screenApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasScreen = !(screenKey ?? "").isEmpty

                return try? MCPAccount(
                    id: account.id.uuidString,
                    name: account.name,
                    userEmail: account.userEmail,
                    apiKey: key,
                    baseURL: account.resolvedBaseURL,
                    screenAPIKey: hasScreen ? screenKey : nil,
                    screenRegion: account.screenRegion == .europe ? "eu" : "us",
                    allowWrites: writableAccountIDs.contains(account.id.uuidString)
                )
            }

            let currentID = UserDefaults.standard.string(forKey: "currentAccountID")
                .flatMap { UUID(uuidString: $0) }?.uuidString
            let defaultName = credentials.first { $0.id == currentID }?.id
                ?? credentials.first?.id
                ?? ""
            return MCPAccountSet(
                accounts: credentials,
                defaultName: defaultName,
                allowWrites: UserDefaults.standard.bool(forKey: MCPServer.writeEnabledDefaultsKey)
            )
        }
    }
#endif
