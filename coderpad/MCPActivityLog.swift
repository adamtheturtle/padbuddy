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

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }

        let dir = base.appending(path: "com.coderpad.app", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "mcp-activity.jsonl")
    }

    // MARK: - Writing (headless server)

    /// Record a `--mcp` process launch serving `account` (its display name, or nil).
    static func recordLaunch(account: String?) {
        append(MCPActivityEntry(id: UUID(), time: Date(), kind: .launch, tool: nil, account: account, succeeded: nil))
    }

    /// Record one tool call: its name, the account served, and whether it succeeded.
    static func recordCall(tool: String, account: String?, succeeded: Bool) {
        append(MCPActivityEntry(id: UUID(), time: Date(), kind: .call, tool: tool, account: account,
                                succeeded: succeeded))
    }

    private static func append(_ entry: MCPActivityEntry) {
        guard let url = fileURL,
              let data = try? encoder.encode(entry),
              let line = String(bytes: data, encoding: .utf8) else { return }

        let payload = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: payload)
        } else {
            // First write: create the file with this line.
            try? payload.write(to: url, options: .atomic)
        }
    }

    // MARK: - Reading (app)

    /// The most recent entries, newest last, decoding tolerantly (a malformed line, e.g.
    /// from a torn concurrent append, is skipped rather than failing the whole read).
    static func load() -> [MCPActivityEntry] {
        guard let url = fileURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        let entries = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> MCPActivityEntry? in
                guard let data = line.data(using: .utf8) else { return nil }

                return try? decoder.decode(MCPActivityEntry.self, from: data)
            }
        return Array(entries.suffix(maxEntries))
    }

    /// Rewrite the file to only the last `maxEntries` lines, so the debug log can't grow
    /// without bound. Called by the app (one process) after a load, so it doesn't race the
    /// headless appenders for the rewrite.
    static func trimIfNeeded() {
        guard let url = fileURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > maxEntries else { return }

        let trimmed = lines.suffix(maxEntries).joined(separator: "\n") + "\n"
        try? Data(trimmed.utf8).write(to: url, options: .atomic)
    }

    /// Delete the log, e.g. so it doesn't outlive the data it describes.
    static func clear() {
        guard let url = fileURL else { return }

        try? FileManager.default.removeItem(at: url)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
