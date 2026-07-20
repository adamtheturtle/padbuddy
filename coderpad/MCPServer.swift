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

import Foundation
import MCP
import MCPKit

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
    static func runUntilExit(directory: MCPAccountDirectory) -> Never {
        MCPKit.MCPServer.runOverStdioUntilExit(
            name: serverName,
            version: serverVersion,
            capabilities: .init(tools: .init(listChanged: false)),
            isEnabled: { UserDefaults.standard.bool(forKey: enabledDefaultsKey) },
            disabledMessage: "The PadBuddy MCP server is turned off. Turn on \u{201C}Enable the "
                + "MCP server\u{201D} in PadBuddy's Settings > MCP Server, then restart this assistant.",
            onLaunch: { MCPActivityLog.recordLaunch(account: directory.current?.accountName) },
            provider: CoderPadToolProvider(directory: directory)
        )
    }
}

/// The CoderPad in-app MCP tool provider for MCPKit's `MCPServer`. It advertises
/// the CoderPad catalogue (gated on the configured accounts' Screen / writes settings) and
/// runs `MCPTools` against them. Tools-only - the in-app server exposes no prompts or
/// resources - so it relies on the `MCPToolProvider` defaults for those. `nonisolated`
/// (the app defaults to MainActor isolation) so its `Sendable` conformance holds and the
/// SDK's nonisolated server can drive it; it carries only the plain Sendable directory.
private nonisolated struct CoderPadToolProvider: MCPToolProvider {
    let directory: MCPAccountDirectory

    /// Returned (as an error result) when a tool is called but no account is configured.
    private static let noAccountMessage = """
    No CoderPad account is configured in PadBuddy. Open the app, add an account with an \
    API key, then try again.
    """

    /// Screen tools appear only when some account has a Screen key; write tools only when
    /// writes are opted in (mirrors the standalone CLI's advertised set).
    func tools() async -> [Tool] {
        mcpTools(from: MCPTools.all(
            allowWrites: directory.allowWrites,
            screenEnabled: directory.secondaryAvailable
        ))
    }

    func callTool(_ name: String, arguments: [String: Value]?) async -> CallTool.Result {
        // With nothing configured, give the friendly setup message rather than a raw
        // account-resolution error (matches the prior hand-rolled behaviour).
        guard !directory.accounts.isEmpty else {
            return errorResult(Self.noAccountMessage)
        }

        let arguments = Self.nativeArguments(arguments)
        let outcome = await MCPTools.run(name: name, arguments: arguments, directory: directory)
        // Report the call (tool name + served account + ok/error - never arguments)
        // so the app's MCP status view can show recent activity (#523). Failures
        // carry a short sanitized reason so "why did that call fail?" is answerable
        // from the activity window instead of only from the assistant (#688).
        let served = MCPActivityAttribution.accountName(arguments: arguments, directory: directory)
        MCPActivityLog.recordCall(tool: name, account: served, succeeded: !outcome.isError,
                                  failureReason: outcome.isError ? outcome.text : nil)
        return textResult(outcome.text, isError: outcome.isError ? true : nil)
    }

    /// Flattens the SDK's typed `[String: Value]` arguments into the `[String: Any]` the
    /// `MCPTools` dispatcher coerces from, yielding native Swift Bool/Int/String/etc.
    private static func nativeArguments(_ arguments: [String: Value]?) -> [String: Any] {
        (arguments ?? [:]).mapValues(native(from:))
    }

    private static func native(from value: Value) -> Any {
        switch value {
        case .null: NSNull()
        case let .bool(bool): bool
        case let .int(int): int
        case let .double(double): double
        case let .string(string): string
        case let .data(_, data): data
        case let .array(array): array.map(native(from:))
        case let .object(object): object.mapValues(native(from:))
        }
    }
}

/// Computes the account label stored in the MCP activity log. Invalid explicit
/// selectors are recorded as requested instead of falling back to the default account,
/// because no account actually served that failed request.
nonisolated enum MCPActivityAttribution {
    static func accountName(arguments: [String: Any], directory: MCPAccountDirectory) -> String? {
        guard let selector = (arguments[MCPTools.account] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selector.isEmpty
        else {
            return directory.current?.accountName
        }

        return directory.resolve(selector)?.accountName ?? selector
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
