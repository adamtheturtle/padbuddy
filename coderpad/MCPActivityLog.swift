//
//  MCPActivityLog.swift
//  coderpad
//
//  A tiny, shared activity log for the in-app MCP server (#523). The headless `--mcp`
//  process is a separate launch from the running app, so it records what it does to a
//  small file in the shared container; the MCP Settings pane tails that file to show the
//  user the server is actually working (last launch, recent tool calls, the account it
//  served).
//
//  Privacy-light by design: it stores only the event time, the tool name, the account's
//  display name, and ok/error — never tool arguments or any candidate/pad content.
//
//  Concurrency: several MCP clients can each launch their own `--mcp` process, so writes
//  are append-only (atomic small appends). Trimming to the last N entries is done by the
//  app (a single, main-actor reader) when it loads, avoiding multi-process rewrite races.
//

import BuddyMCP
import Foundation

/// One recorded MCP server event. `launch` marks a `--mcp` process starting; `call` marks
/// one tool invocation.
nonisolated struct MCPActivityEntry: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case launch
        case call
    }

    let id: UUID
    let time: Date
    let kind: Kind
    /// The tool name for a `call`, nil for a `launch`.
    let tool: String?
    /// The display name of the account served, when known.
    let account: String?
    /// Whether a `call` succeeded; nil for a `launch`.
    let succeeded: Bool?
}

/// Reads and writes the MCP activity log. All members are `nonisolated` so the headless
/// server (which runs off the main actor) can append from any context.
nonisolated enum MCPActivityLog {
    /// The most recent entries kept; older ones are dropped when the app trims on load.
    static let maxEntries = 30

    /// Backing store: buddy-kit's JSONL log in the shared container, keeping the same
    /// directory (`com.coderpad.app`), filename (`mcp-activity.jsonl`), cap, and ISO-8601
    /// date coding as the previous hand-rolled implementation, so existing logs read back
    /// unchanged. Nil only if Application Support can't be resolved, in which case every
    /// operation is a safe no-op (matching the old `fileURL == nil` guards).
    private static let store: JSONLLog<MCPActivityEntry>? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }

        let dir = base.appending(path: "com.coderpad.app", directoryHint: .isDirectory)
        return JSONLLog(directory: dir, fileName: "mcp-activity.jsonl", maxEntries: maxEntries)
    }()

    // MARK: - Writing (headless server)

    /// Record a `--mcp` process launch serving `account` (its display name, or nil).
    static func recordLaunch(account: String?) {
        store?.append(MCPActivityEntry(id: UUID(), time: Date(), kind: .launch, tool: nil, account: account,
                                       succeeded: nil))
    }

    /// Record one tool call: its name, the account served, and whether it succeeded.
    static func recordCall(tool: String, account: String?, succeeded: Bool) {
        store?.append(MCPActivityEntry(id: UUID(), time: Date(), kind: .call, tool: tool, account: account,
                                       succeeded: succeeded))
    }

    // MARK: - Reading (app)

    /// The most recent entries, newest last, decoding tolerantly (a malformed line, e.g.
    /// from a torn concurrent append, is skipped rather than failing the whole read).
    static func load() -> [MCPActivityEntry] {
        store?.load() ?? []
    }

    /// Rewrite the file to only the last `maxEntries` lines, so the debug log can't grow
    /// without bound. Called by the app (one process) after a load, so it doesn't race the
    /// headless appenders for the rewrite.
    static func trimIfNeeded() {
        store?.trim()
    }

    /// Delete the log, e.g. so it doesn't outlive the data it describes.
    static func clear() {
        store?.clear()
    }
}
