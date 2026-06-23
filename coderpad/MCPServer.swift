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

/// CoderPad-specific entry glue for the `--mcp` headless mode.
nonisolated enum MCPServer {
    /// Presence of this argument switches the process into headless MCP mode.
    static let commandLineFlag = "--mcp"

    /// The MCP server identity reported in the `initialize` handshake's `serverInfo`.
    private static let serverName = "PadBuddy"

    /// The version reported in `serverInfo`, taken from the app bundle.
    private static var serverVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Returned (as an error result) when a tool is called but no account is configured.
    private static let noAccountMessage = """
    No CoderPad account is configured in PadBuddy. Open the app, add an account with an \
    API key, then try again.
    """

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
    /// isolated); the SDK's actor-based server then runs nonisolated. Tool activity is
    /// forwarded to `MCPActivityLog` so the app's status view can show it (#523). Never
    /// returns: it blocks the calling thread on the async server until stdin closes.
    static func runUntilExit(directory: MCPAccountDirectory) -> Never {
        MCPActivityLog.recordLaunch(account: directory.current?.accountName)
        // Bridge the SDK's async server to this synchronous, never-returning entry point.
        // The directory is a plain Sendable value, so it crosses into the task safely.
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await serve(directory: directory)
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }

    /// Builds the SDK `Server`, registers the tools/list and tools/call handlers backed by
    /// `MCPTools`, and serves over stdio until the transport closes.
    private static func serve(directory: MCPAccountDirectory) async {
        let server = Server(
            name: serverName,
            version: serverVersion,
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            // Screen tools appear only when some account has a Screen key; write tools only
            // when writes are opted in (mirrors the standalone CLI's advertised set).
            let descriptors = MCPTools.all(
                allowWrites: directory.allowWrites,
                screenEnabled: directory.secondaryAvailable
            )
            return ListTools.Result(tools: descriptors.map(tool(from:)))
        }

        await server.withMethodHandler(CallTool.self) { params in
            // With nothing configured, give the friendly setup message rather than a raw
            // account-resolution error (matches the prior hand-rolled behaviour).
            guard !directory.accounts.isEmpty else {
                return CallTool.Result(
                    content: [.text(text: noAccountMessage, annotations: nil, _meta: nil)],
                    isError: true
                )
            }

            let arguments = nativeArguments(params.arguments)
            let outcome = await MCPTools.run(name: params.name, arguments: arguments, directory: directory)
            // Report the call (tool name + served account + ok/error only - never arguments)
            // so the app's MCP status view can show recent activity (#523).
            let served = directory.resolve(arguments[MCPTools.account] as? String)?.accountName
                ?? directory.current?.accountName
            MCPActivityLog.recordCall(tool: params.name, account: served, succeeded: !outcome.isError)
            return CallTool.Result(
                content: [.text(text: outcome.text, annotations: nil, _meta: nil)],
                isError: outcome.isError ? true : nil
            )
        }

        do {
            try await server.start(transport: StdioTransport())
            await server.waitUntilCompleted()
        } catch {
            FileHandle.standardError.write(Data("PadBuddy MCP server failed to start: \(error)\n".utf8))
        }
    }

    // MARK: - Catalogue and argument adapters

    /// Turns one shared catalogue descriptor (`{ name, description, inputSchema,
    /// annotations? }`, plumbing-neutral JSON) into the SDK's `Tool`. The catalogue is
    /// defined once in CoderPadToolCore; each server builds its own tool objects from it,
    /// the same conversion the standalone CLI does.
    private static func tool(from descriptor: [String: Any]) -> Tool {
        let name = descriptor["name"] as? String ?? ""
        let description = descriptor["description"] as? String ?? ""
        let inputSchema = mcpValue(descriptor["inputSchema"] ?? [String: Any]())
        let annotations = (descriptor["annotations"] as? [String: Any]).map(annotations(from:))
            ?? Tool.Annotations()
        return Tool(name: name, description: description, inputSchema: inputSchema, annotations: annotations)
    }

    private static func annotations(from dict: [String: Any]) -> Tool.Annotations {
        Tool.Annotations(
            title: dict["title"] as? String,
            readOnlyHint: dict["readOnlyHint"] as? Bool,
            destructiveHint: dict["destructiveHint"] as? Bool,
            openWorldHint: dict["openWorldHint"] as? Bool
        )
    }

    /// Converts a JSON value from the shared catalogue into an MCP `Value`. Bool is checked
    /// before the numeric types so a flag isn't read as an int.
    private static func mcpValue(_ any: Any) -> Value {
        switch any {
        case let value as Value: value
        case let bool as Bool: .bool(bool)
        case let int as Int: .int(int)
        case let double as Double: .double(double)
        case let string as String: .string(string)
        case let array as [Any]: .array(array.map(mcpValue))
        case let object as [String: Any]: .object(object.mapValues(mcpValue))
        default: .null
        }
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
