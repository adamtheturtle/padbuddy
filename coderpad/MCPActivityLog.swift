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
            performTrim(store)
        }
    }

    /// Bounds a recorded tool/account string: first line only, control characters
    /// stripped, and capped, so one malformed identifier can't make every retained
    /// JSONL line enormous (#1758).
    static func sanitizedField(_ value: String?, cap: Int) -> String? {
        guard let value else { return nil }

        let firstLine = value.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let cleaned = String(firstLine.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
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
        while start < text.endIndex, text[start] == "\n" {
            start = text.index(after: start)
        }
        guard start < text.endIndex else { return nil }

        let end = text[start...].firstIndex(of: "\n") ?? text.endIndex
        let firstLine = text[start ..< end].trimmingCharacters(in: .whitespaces)
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
    /// Read under a shared lock so the UI never observes a half-written rewrite from
    /// a concurrent headless trim/clear (#1755).
    static func load() -> [MCPActivityEntry] {
        guard let store else { return [] }

        return withActivityLogLock(in: store.directory, exclusive: false) {
            store.load().map(\.bounded)
        } ?? []
    }

    /// The entries plus how many stored lines failed to decode, so the activity
    /// view can say unreadable entries were skipped — a corrupted log (torn write,
    /// failed lock) must be distinguishable from "no MCP use" (#1146). The count
    /// is exact whenever the file is within its cap (its steady state after
    /// trims); between trims it can undercount. Read under a shared lock (#1755).
    static func loadWithDiagnostics() -> (entries: [MCPActivityEntry], unreadableLines: Int) {
        loadWithDiagnosticsIfReadable() ?? ([], 0)
    }

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

        return withActivityLogLock(in: store.directory, exclusive: false) {
            let url = store.directory.appending(path: "mcp-activity.jsonl")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return ([], 0) }

            // One read, one pass: decode each line here (the same tolerant per-line
            // decode and cap as JSONLLog.load()) instead of loading through the store
            // and then re-reading the whole file just to count its lines (#2246).
            let decoder = JSONLLog<MCPActivityEntry>.iso8601Decoder
            var decoded: [MCPActivityEntry] = []
            var lineCount = 0
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                lineCount += 1
                if let data = line.data(using: .utf8),
                   let entry = try? decoder.decode(MCPActivityEntry.self, from: data) {
                    decoded.append(entry)
                }
            }
            let entries = decoded.suffix(maxEntries).map(\.bounded)
            return (entries, max(0, min(lineCount, maxEntries) - entries.count))
        }
    }

    /// Rewrite the file to only the last `maxEntries` lines and drop entries past
    /// the retention window (#1145), so the debug log can't grow without bound or
    /// retain account names indefinitely. Also rewrites when the file holds
    /// unreadable lines, so torn-write debris can't accumulate and slow every
    /// settings poll forever (#1759). The same lock as append/clear keeps the
    /// rewrite from dropping a concurrent headless tool-call record.
    static func trimIfNeeded() {
        withLockedStore(performTrim)
    }

    /// The cap + retention rewrite. The caller must already hold the exclusive lock.
    private static func performTrim(_ store: JSONLLog<MCPActivityEntry>) {
        store.trim()
        let entries = store.load()
        let cutoff = Date().addingTimeInterval(-retention)
        let retained = entries.filter { $0.time >= cutoff }
        let url = store.directory.appending(path: "mcp-activity.jsonl")
        let rawLines = (try? String(contentsOf: url, encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: true).count ?? entries.count
        guard retained.count != entries.count || rawLines != entries.count else { return }

        if retained.isEmpty {
            store.clear()
            return
        }

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
        try? payload.write(to: url, options: .atomic)
    }

    /// Delete the log, e.g. so it doesn't outlive the data it describes.
    static func clear() {
        withLockedStore { $0.clear() }
    }

    private static func withLockedStore(_ operation: (JSONLLog<MCPActivityEntry>) -> Void) {
        guard let store else { return }

        withActivityLogLock(in: store.directory, exclusive: true) {
            operation(store)
        }
    }

    /// Runs `operation` under the advisory file lock, or returns nil without running
    /// it when the lock can't be acquired within the bounded wait. The log stores
    /// account display names, so the directory and its files are kept user-private
    /// (0700/0600) as a side effect of taking the lock (#1760).
    @discardableResult
    private static func withActivityLogLock<T>(
        in directory: URL, exclusive: Bool, operation: () -> T
    ) -> T? {
        #if canImport(Darwin)
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let lockURL = directory.appending(path: lockFileName)
            if !FileManager.default.fileExists(atPath: lockURL.path) {
                FileManager.default.createFile(
                    atPath: lockURL.path, contents: nil,
                    attributes: [.posixPermissions: 0o600]
                )
            }
            restrictLogPermissions(in: directory)

            guard let handle = try? FileHandle(forWritingTo: lockURL) else {
                // Never operate on the shared file without the lock: concurrent
                // unlocked writers are exactly how the JSONL tears (#1756).
                return nil
            }

            defer { try? handle.close() }

            // Bounded, non-blocking acquisition: a stalled headless process holding
            // the lock must not freeze Settings actions running on the main actor
            // (#1757), and a failed lock must skip the operation rather than write
            // concurrently (#1756).
            let kind = exclusive ? LOCK_EX : LOCK_SH
            var acquired = flock(handle.fileDescriptor, kind | LOCK_NB) == 0
            var attempts = 0
            while !acquired, attempts < 20 {
                usleep(100_000)
                attempts += 1
                acquired = flock(handle.fileDescriptor, kind | LOCK_NB) == 0
            }
            guard acquired else { return nil }

            defer { flock(handle.fileDescriptor, LOCK_UN) }

            return operation()
        #else
            return operation()
        #endif
    }

    /// Keeps the log and lock files user-private: they carry account display names
    /// and activity timing (#1760).
    private static func restrictLogPermissions(in directory: URL) {
        let logPath = directory.appending(path: "mcp-activity.jsonl").path
        if FileManager.default.fileExists(atPath: logPath) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logPath)
        }
    }
}
