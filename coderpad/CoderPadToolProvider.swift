//
//  CoderPadToolProvider.swift
//  coderpad
//
//  The app's adapter to the reusable BuddyMCP server (#514): it supplies PadBuddy's
//  identity and wraps today's read/write CoderPad ``MCPTools`` as the injected
//  ``MCPToolProvider``. BuddyMCP owns the stdio loop, JSON-RPC envelope, and account
//  resolution; this is the only CoderPad-specific seam.
//

import BuddyMCP
import Foundation

nonisolated struct CoderPadToolProvider: MCPToolProvider {
    let serverName = "PadBuddy"

    var serverVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    let noAccountMessage = """
    No CoderPad account is configured in PadBuddy. Open the app, add an account with an \
    API key, then try again.
    """

    func toolDescriptors(directory: MCPAccountDirectory) -> [[String: Any]] {
        // The secondary key is the account's CoderPad Screen key, so screen_* tools are
        // advertised only when some account has one configured (#499).
        MCPTools.all(allowWrites: directory.allowWrites, screenEnabled: directory.secondaryAvailable)
    }

    func run(name: String, arguments: [String: Any], directory: MCPAccountDirectory) async -> MCPToolOutcome {
        let outcome = await MCPTools.run(name: name, arguments: arguments, directory: directory)
        return MCPToolOutcome(text: outcome.text, isError: outcome.isError)
    }
}
