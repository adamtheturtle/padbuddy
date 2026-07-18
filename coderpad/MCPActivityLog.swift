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
//  Concurrency: several MCP clients can each launch their own `--mcp` process. Appends,
//  trims, and clears are wrapped in an advisory file lock so the GUI never rewrites the
//  log from an old snapshot while a headless process is appending (#763).
//

import Foundation
import MCPKit
#if canImport(Darwin)
    import Darwin
#endif

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
    /// A short, sanitized reason for a failed `call` (first line, capped) so the
    /// activity view can say *why* a tool errored, not just that it did (#688).
    /// Never tool arguments or result payloads; nil on success, for launches, and
    /// for entries written before the field existed.
    var failureReason: String?
}

/// Reads and writes the MCP activity log. All members are `nonisolated` so the headless
/// server (which runs off the main actor) can append from any context.
nonisolated enum MCPActivityLog {
    /// The most recent entries kept; older ones are dropped when the app trims on load.
    static let maxEntries = 30

    /// Backing store: MCPKit's JSONL log in the shared container, keeping the same
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

    private static let lockFileName = "mcp-activity.jsonl.lock"

    // MARK: - Writing (headless server)

    /// Record a `--mcp` process launch serving `account` (its display name, or nil).
    static func recordLaunch(account: String?) {
        withLockedStore { store in
            store.append(MCPActivityEntry(id: UUID(), time: Date(), kind: .launch, tool: nil, account: account,
                                          succeeded: nil, failureReason: nil))
        }
    }

    /// Record one tool call: its name, the account served, whether it succeeded,
    /// and - for failures - a short sanitized reason (#688).
    static func recordCall(tool: String, account: String?, succeeded: Bool, failureReason: String? = nil) {
        withLockedStore { store in
            store.append(MCPActivityEntry(id: UUID(), time: Date(), kind: .call, tool: tool, account: account,
                                          succeeded: succeeded,
                                          failureReason: failureReason.flatMap(sanitizedReason)))
        }
    }

    /// Reduces an error text to a log-safe summary: the first non-empty line,
    /// capped at 120 characters. Error texts are validation/HTTP messages, but the
    /// cap keeps any verbose server body from ballooning the log or echoing
    /// response payloads into it.
    static func sanitizedReason(_ text: String) -> String? {
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !firstLine.isEmpty else { return nil }

        return String(firstLine.prefix(120))
    }

    // MARK: - Reading (app)

    /// How long entries are retained. The log stores account display names in a
    /// shared on-disk file, and a low-use install must not preserve them
    /// indefinitely — anything older is dropped by `trimIfNeeded` (#1145).
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    /// The most recent entries, newest last, decoding tolerantly (a malformed line, e.g.
    /// from a torn concurrent append, is skipped rather than failing the whole read).
    static func load() -> [MCPActivityEntry] {
        store?.load() ?? []
    }

    /// The entries plus how many stored lines failed to decode, so the activity
    /// view can say unreadable entries were skipped — a corrupted log (torn write,
    /// failed lock) must be distinguishable from "no MCP use" (#1146). The count
    /// is exact whenever the file is within its cap (its steady state after
    /// trims); between trims it can undercount.
    static func loadWithDiagnostics() -> (entries: [MCPActivityEntry], unreadableLines: Int) {
        guard let store else { return ([], 0) }

        let entries = store.load()
        let url = store.directory.appending(path: "mcp-activity.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return (entries, 0) }

        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: true).count
        return (entries, max(0, min(lineCount, maxEntries) - entries.count))
    }

    /// Rewrite the file to only the last `maxEntries` lines and drop entries past
    /// the retention window (#1145), so the debug log can't grow without bound or
    /// retain account names indefinitely. The same lock as append/clear keeps the
    /// rewrite from dropping a concurrent headless tool-call record.
    static func trimIfNeeded() {
        withLockedStore { store in
            store.trim()
            let entries = store.load()
            let cutoff = Date().addingTimeInterval(-retention)
            let retained = entries.filter { $0.time >= cutoff }
            guard retained.count != entries.count else { return }

            store.clear()
            for entry in retained {
                store.append(entry)
            }
        }
    }

    /// Delete the log, e.g. so it doesn't outlive the data it describes.
    static func clear() {
        withLockedStore { $0.clear() }
    }

    private static func withLockedStore(_ operation: (JSONLLog<MCPActivityEntry>) -> Void) {
        guard let store else { return }

        withActivityLogLock(in: store.directory) {
            operation(store)
        }
    }

    private static func withActivityLogLock(in directory: URL, operation: () -> Void) {
        #if canImport(Darwin)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let lockURL = directory.appending(path: lockFileName)
            if !FileManager.default.fileExists(atPath: lockURL.path) {
                FileManager.default.createFile(atPath: lockURL.path, contents: nil)
            }

            guard let handle = try? FileHandle(forWritingTo: lockURL) else {
                operation()
                return
            }
            defer { try? handle.close() }

            flock(handle.fileDescriptor, LOCK_EX)
            defer { flock(handle.fileDescriptor, LOCK_UN) }
            operation()
        #else
            operation()
        #endif
    }
}
