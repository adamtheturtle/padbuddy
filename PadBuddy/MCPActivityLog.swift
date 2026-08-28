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
import os

private struct MCPActivityDiagnosticsResult {
    let entries: [MCPActivityEntry]
    let unreadableLines: Int
    let truncatedLeadingLine: Bool
}

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

    /// The entry with its free-text fields re-bounded.
    ///
    /// Writes are already sanitized (#1758), but the log is a plain file in a
    /// shared container: anything that corrupts or edits it out of band can put
    /// arbitrarily long tool or account strings in front of the renderer, which
    /// then expands the layout and re-does the work on every three-second poll
    /// (#2553). Applying the same caps on read means the view can only ever be
    /// handed values it can display.
    var bounded: Self {
        Self(id: id, time: time, kind: kind,
             tool: MCPActivityLog.sanitizedField(tool, cap: 64),
             account: MCPActivityLog.sanitizedField(account, cap: 100),
             succeeded: succeeded,
             failureReason: failureReason.flatMap(MCPActivityLog.sanitizedReason))
    }
}

/// Reads and writes the MCP activity log. All members are `nonisolated` so the headless
/// server (which runs off the main actor) can append from any context.
nonisolated enum MCPActivityLog {
    /// The most recent entries kept; older ones are dropped when the app trims on load.
    static let maxEntries = 30
    static let maxReadBytes = 1_048_576
    private static let logger = Logger(subsystem: "com.coderpad.app", category: "mcp-activity")

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

    static let lockFileName = "mcp-activity.jsonl.lock"

    // MARK: - Writing (headless server)

    /// Record a `--mcp` process launch serving `account` (its display name, or nil).
    /// A no-op while the server toggle is off: a headless process that was already
    /// running when the user disabled the feature must stop recording too (#1761).
    static func recordLaunch(account: String?) {
        guard UserDefaults.standard.bool(forKey: MCPServer.enabledDefaultsKey) else { return }

        appendLocked(MCPActivityEntry(id: UUID(), time: Date(), kind: .launch, tool: nil,
                                      account: sanitizedField(account, cap: 100),
                                      succeeded: nil, failureReason: nil))
    }

    /// Record one tool call: its name, the account served, whether it succeeded,
    /// and - for failures - a short sanitized reason (#688). A no-op while the
    /// server toggle is off (#1761).
    static func recordCall(tool: String, account: String?, succeeded: Bool, failureReason: String? = nil) {
        guard UserDefaults.standard.bool(forKey: MCPServer.enabledDefaultsKey) else { return }

        appendLocked(MCPActivityEntry(id: UUID(), time: Date(), kind: .call,
                                      tool: sanitizedField(tool, cap: 64),
                                      account: sanitizedField(account, cap: 100),
                                      succeeded: succeeded,
                                      failureReason: failureReason.flatMap(sanitizedReason)))
    }

    /// Appends an entry and enforces the cap and retention window in the same
    /// locked section.
    ///
    /// Trimming used to happen only from the GUI's poll, so an install that never
    /// opened the MCP settings pane — the normal case for someone who wired up a
    /// client once and left it running — grew the file without bound and kept
    /// account display names far past the retention window (#2549). Doing it here
    /// costs a few reads of a file that is at most `maxEntries` lines in its steady
    /// state, and needs no extra lock: the append already holds the exclusive one.
    private static func appendLocked(_ entry: MCPActivityEntry) {
        withLockedStore { store in
            store.append(entry)
            _ = trim(store: store)
        }
    }

    /// Bounds a recorded tool/account string: first line only, control characters
    /// stripped, and capped, so one malformed identifier can't make every retained
    /// JSONL line enormous (#1758).
    static func sanitizedField(_ value: String?, cap: Int) -> String? {
        guard let value else { return nil }

        let firstLine = value.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let cleaned = String(firstLine.unicodeScalars.filter(isSafeLogScalar))
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(cap))
    }

    /// Reduces an error text to a log-safe summary: the first non-empty line,
    /// capped at 120 characters. Error texts are validation/HTTP messages, but the
    /// cap keeps any verbose server body from ballooning the log or echoing
    /// response payloads into it.
    static func sanitizedReason(_ text: String) -> String? {
        // Walk to the first non-empty line directly: splitting the whole failure text
        // (which can be a full HTTP/HTML body) allocates every line just to keep one (#2245).
        var start = text.startIndex
        while start < text.endIndex {
            let end = text[start...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[start ..< end].trimmingCharacters(in: .whitespaces)
            let cleaned = String(line.unicodeScalars.filter(isSafeLogScalar))
                .trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty {
                return String(cleaned.prefix(120))
            }
            guard end < text.endIndex else { break }

            start = text.index(after: end)
        }
        return nil
    }

    /// Controls can alter a JSONL record and format scalars such as bidi overrides
    /// can make its rendered meaning differ from the stored text.
    private static func isSafeLogScalar(_ scalar: Unicode.Scalar) -> Bool {
        !CharacterSet.controlCharacters.contains(scalar)
            && scalar.properties.generalCategory != .format
    }

    // MARK: - Reading (app)

    /// How long entries are retained. The log stores account display names in a
    /// shared on-disk file, and a low-use install must not preserve them
    /// indefinitely — anything older is dropped by `trimIfNeeded` (#1145).
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    /// The entries plus how many stored lines failed to decode, so the activity
    /// view can say unreadable entries were skipped — a corrupted log (torn write,
    /// failed lock) must be distinguishable from "no MCP use" (#1146). The count
    /// is exact whenever the file is within its cap (its steady state after
    /// trims); between trims it can undercount. Read under a shared lock (#1755).
    /// As `loadWithDiagnostics`, but `nil` when the log could not be read at all —
    /// no shared container, or the advisory lock wasn't obtained within its bounded
    /// wait — as opposed to being read and found empty.
    ///
    /// The polling UI needs the difference: treating an unreadable log as empty, or
    /// silently keeping the previous entries, both present stale activity as current
    /// (#2554). Note that a *missing file* still reads as an empty log, which is
    /// correct: that is what "no MCP use yet" looks like.
    static func loadWithDiagnosticsIfReadable() -> (entries: [MCPActivityEntry], unreadableLines: Int)? {
        guard let store else { return nil }

        let locked: (entries: [MCPActivityEntry], unreadableLines: Int)?? = withActivityLogLock(
            in: store.directory,
            exclusive: false
        ) {
            let url = store.directory.appending(path: "mcp-activity.jsonl")
            return loadDiagnostics(at: url)
        }
        return locked.flatMap(\.self)
    }

    /// Reads one activity file. A missing file means that MCP has not recorded any
    /// activity yet; every other read or UTF-8 decoding failure is reported to the
    /// caller instead of being presented as an empty, successfully read log.
    static func loadDiagnostics(
        at url: URL
    ) -> (entries: [MCPActivityEntry], unreadableLines: Int)? {
        guard let result = loadDiagnosticsWithTail(at: url) else { return nil }

        return (result.entries, result.unreadableLines)
    }

    private static func loadDiagnosticsWithTail(
        at url: URL
    ) -> MCPActivityDiagnosticsResult? {
        let tail: ActivityLogTail
        do {
            tail = try readTail(at: url)
        } catch ActivityLogReadError.missing {
            return MCPActivityDiagnosticsResult(entries: [], unreadableLines: 0, truncatedLeadingLine: false)
        } catch {
            logger.error("Could not read MCP activity log at \(url.path, privacy: .private): \(error)")
            return nil
        }

        let decoder = JSONLLog<MCPActivityEntry>.iso8601Decoder
        var lines: [Data?] = tail.completeData.split(separator: 0x0A, omittingEmptySubsequences: true)
            .map { Data($0) }
            .map(Optional.some)
        if tail.hasTruncatedLeadingLine {
            lines.insert(nil, at: 0)
        }
        let retainedLines = lines.suffix(maxEntries)
        var entries: [MCPActivityEntry] = []
        var unreadableLines = 0
        for line in retainedLines {
            guard let line else {
                unreadableLines += 1
                continue
            }

            if String(data: line, encoding: .utf8) != nil,
               let entry = try? decoder.decode(MCPActivityEntry.self, from: line) {
                entries.append(entry.bounded)
            } else {
                unreadableLines += 1
            }
        }
        return MCPActivityDiagnosticsResult(
            entries: entries,
            unreadableLines: unreadableLines,
            truncatedLeadingLine: tail.hasTruncatedLeadingLine
        )
    }

    /// Rewrite the file to only the last `maxEntries` lines and drop entries past
    /// the retention window (#1145), so the debug log can't grow without bound or
    /// retain account names indefinitely. Also rewrites when the file holds
    /// unreadable lines, so torn-write debris can't accumulate and slow every
    /// settings poll forever (#1759). The same lock as append/clear keeps the
    /// rewrite from dropping a concurrent headless tool-call record.
    @discardableResult
    static func trimIfNeeded() -> Bool? {
        withLockedStore { trim(store: $0) }
    }

    /// The cap + retention rewrite. The caller must already hold the exclusive lock.
    /// Returns false after logging any atomic publication failure so callers can
    /// surface that retention was not applied.
    static func trim(
        store: JSONLLog<MCPActivityEntry>,
        write: (Data, URL) throws -> Void = { data, url in
            try writeRestrictedLog(data, to: url)
        }
    ) -> Bool {
        let url = store.directory.appending(path: "mcp-activity.jsonl")
        guard let diagnostics = loadDiagnosticsWithTail(at: url) else { return false }
        guard !diagnostics.truncatedLeadingLine || !diagnostics.entries.isEmpty else {
            return true
        }

        let cutoff = Date().addingTimeInterval(-retention)
        let retained = diagnostics.entries.filter { $0.time >= cutoff }

        // Rewrite the retained entries in one atomic write: clear() plus a
        // per-entry append() rewrote/touched the file once per retained line (#2248).
        // Same encoder as the store's appends, so the file reads back unchanged.
        let encoder = JSONLLog<MCPActivityEntry>.iso8601Encoder
        var payload = Data()
        for entry in retained {
            guard let data = try? encoder.encode(entry) else { continue }

            payload.append(data)
            payload.append(0x0A) // "\n"
        }
        do {
            guard !payload.isEmpty else {
                store.clear()
                return true
            }

            try write(payload, url)
            return true
        } catch {
            logger.error("Could not apply MCP activity retention at \(url.path, privacy: .private): \(error)")
            return false
        }
    }

    /// Delete the log, e.g. so it doesn't outlive the data it describes.
    static func clear() {
        withLockedStore { $0.clear() }
    }

    private static func withLockedStore<T>(_ operation: (JSONLLog<MCPActivityEntry>) -> T) -> T? {
        guard let store else { return nil }

        return withActivityLogLock(in: store.directory, exclusive: true) {
            operation(store)
        }
    }
}
