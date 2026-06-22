//
//  MCPServer.swift
//  BuddyMCP
//
//  The headless stdio run loop for a Model Context Protocol server (#514, #402): reads
//  newline-delimited JSON-RPC 2.0 from stdin, writes responses to stdout, and runs until
//  stdin closes. The tools come from an injected ``MCPToolProvider``; the host app owns
//  the launch flag, settings, and credential loading.
//

import Foundation

/// Entry point and stdio run loop for an MCP server. Marked `nonisolated` so its work
/// runs off the main actor: the loop blocks the calling thread on `readLine()` while each
/// request is handled on a background task, which would deadlock against a `MainActor`
/// default isolation if these types inherited it.
public nonisolated enum MCPServer {
    /// Reads JSON-RPC requests line by line from stdin, writes responses to stdout, and
    /// runs until stdin closes. Never returns — the process exists only to serve MCP. The
    /// credentials are resolved by the caller (on whatever actor the app's account model
    /// requires) and passed in as plain Sendable values.
    ///
    /// - Parameters:
    ///   - provider: the app's tool catalogue + implementations.
    ///   - directory: the accounts the server may act as.
    ///   - onLaunch: called once with the default account's name when serving begins.
    ///   - onCall: called after each tool call (name, served account, success) for the
    ///     host's activity log; never sees arguments.
    public static func runUntilExit(
        provider: any MCPToolProvider,
        directory: MCPAccountDirectory,
        onLaunch: @Sendable (String?) -> Void = { _ in },
        onCall: @escaping @Sendable (String, String?, Bool) -> Void = { _, _, _ in }
    ) -> Never {
        onLaunch(directory.current?.accountName)
        let handler = MCPRequestHandler(provider: provider, directory: directory, onCall: onCall)
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let reply = blockingHandle(handler, line: trimmed) {
                FileHandle.standardOutput.write(Data((reply + "\n").utf8))
            }
        }
        exit(0)
    }

    /// Bridges the async request handler to the synchronous read loop. The detached task
    /// runs off-main (handler is `nonisolated`), so blocking the calling thread here never
    /// deadlocks; the semaphore also publishes the box's write to this thread.
    private static func blockingHandle(_ handler: MCPRequestHandler, line: String) -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ReplyBox()
        Task.detached {
            box.reply = await handler.handle(line)
            semaphore.signal()
        }
        semaphore.wait()
        return box.reply
    }

    /// Carries one reply across the detached-task boundary. Safe because the semaphore
    /// orders the write (before `signal`) ahead of the read (after `wait`).
    private final class ReplyBox: @unchecked Sendable {
        var reply: String?
    }
}
