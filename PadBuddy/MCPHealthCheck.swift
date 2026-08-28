//
//  MCPHealthCheck.swift
//  coderpad
//

#if os(macOS)
    import Foundation
    import os

    enum MCPHealthStatus: Equatable {
        case idle
        case checking
        case usable
        case unusable(String)
    }

    struct MCPHealthResult: Equatable {
        let isUsable: Bool
        let output: String
    }

    enum MCPHealthTimeout {
        static func wait(
            for duration: Duration,
            using sleep: ((Duration) async throws -> Void)? = nil
        ) async throws {
            if let sleep {
                try await sleep(duration)
            } else {
                try await Task.sleep(for: duration)
            }
        }
    }

    /// Collects a bounded amount of the child's combined stdout/stderr while it runs.
    ///
    /// The health check gives stdout and stderr one pipe and used to read it only after
    /// waiting for termination. A child that wrote more than the pipe buffer blocked in
    /// `write`, never exited, and was reported as a startup timeout — so a real, verbose
    /// diagnostic failure was misclassified (#4594).
    final nonisolated class MCPDiagnosticBuffer: @unchecked Sendable {
        private struct State {
            var text = Data()
            var isComplete = false
        }

        private let state = OSAllocatedUnfairLock(initialState: State())

        var text: String {
            state.withLock { String(bytes: $0.text, encoding: .utf8) ?? "" }
        }

        var isComplete: Bool {
            state.withLock(\.isComplete)
        }

        /// Appends up to `limit` bytes overall, reporting whether more is still wanted.
        func append(_ data: Data, limit: Int) -> Bool {
            state.withLock { state in
                if state.text.count < limit {
                    state.text.append(data.prefix(limit - state.text.count))
                }
                return state.text.count < limit
            }
        }

        func markComplete() {
            state.withLock { $0.isComplete = true }
        }
    }

    enum MCPHealthCheck {
        /// Enough to show a real diagnostic failure, far less than a wedged child can emit.
        static let maximumDiagnosticBytes = 64 * 1024
        /// How long a child gets to honour SIGTERM before it is killed outright.
        static let terminationGrace = Duration.seconds(1)

        static func evaluate(enabled: Bool, usableAccountCount: Int) -> MCPHealthResult {
            guard enabled else {
                return MCPHealthResult(isUsable: false, output: "The MCP server is disabled.")
            }
            guard usableAccountCount > 0 else {
                return MCPHealthResult(
                    isUsable: false,
                    output: "No saved account with a usable API key is available to the MCP server."
                )
            }

            return MCPHealthResult(isUsable: true, output: "usable")
        }

        @MainActor
        static func run(executablePath: String) async -> MCPHealthStatus {
            guard FileManager.default.isExecutableFile(atPath: executablePath) else {
                return .unusable("The PadBuddy executable cannot be launched from its current location.")
            }

            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = [MCPServer.healthCheckFlag]
            process.standardOutput = output
            process.standardError = output
            do {
                try process.run()
            } catch {
                return .unusable("The MCP server process could not be launched.")
            }

            let diagnostics = MCPDiagnosticBuffer()
            let readHandle = output.fileHandleForReading
            let limit = maximumDiagnosticBytes
            Task.detached {
                drain(readHandle, into: diagnostics, limit: limit)
            }

            let status = await terminationStatus(process, timeout: .seconds(5))
            // The child is dead by here — killed outright if it ignored SIGTERM — so the
            // drain sees end-of-file promptly. Waiting a bounded moment for it, rather
            // than reading to end-of-file on this flow, means a grandchild still holding
            // the pipe open cannot freeze the health check (#4593).
            for _ in 0 ..< 20 where !diagnostics.isComplete {
                try? await Task.sleep(for: .milliseconds(10))
            }

            guard let status else {
                let partial = diagnostics.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard partial.isEmpty else {
                    return .unusable("The MCP server self-test timed out during startup. \(partial)")
                }

                return .unusable("The MCP server self-test timed out during startup.")
            }

            let message = diagnostics.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if status == EXIT_SUCCESS {
                return .usable
            }
            if !message.isEmpty {
                return .unusable(message)
            }
            return .unusable("The MCP server self-test failed.")
        }

        private nonisolated static func drain(
            _ handle: FileHandle, into diagnostics: MCPDiagnosticBuffer, limit: Int
        ) {
            while true {
                let chunk = handle.availableData
                guard !chunk.isEmpty else { break }
                guard diagnostics.append(chunk, limit: limit) else { break }
            }
            // Closing the read end past the cap makes a child that keeps writing fail with
            // SIGPIPE rather than block forever on a pipe nobody is draining.
            try? handle.close()
            diagnostics.markComplete()
        }

        private nonisolated static func signal(_ pid: pid_t, _ code: Int32) {
            guard pid > 0 else { return }

            _ = kill(pid, code)
        }

        @MainActor
        private static func terminationStatus(
            _ process: Process, timeout: Duration
        ) async -> Int32? {
            let waiter = SingleResume<Int32?>()
            // `pid_t`, not the `Process`, so the cancellation handler has something
            // Sendable to act on.
            let pid = process.processIdentifier
            process.terminationHandler = { process in
                waiter.finish(process.terminationStatus)
            }

            let timer = Task { @MainActor in
                do {
                    try await MCPHealthTimeout.wait(for: timeout)
                } catch is CancellationError {
                    return
                } catch {
                    assertionFailure("MCP health-check timeout timer failed: \(error)")
                    return
                }
                signal(pid, SIGTERM)
                // SIGTERM is a request. Escalating keeps the advertised timeout a real
                // upper bound rather than one a wedged child can extend (#4593).
                try? await MCPHealthTimeout.wait(for: terminationGrace)
                signal(pid, SIGKILL)
                waiter.finish(nil)
            }
            defer { timer.cancel() }

            return await withTaskCancellationHandler {
                await withCheckedContinuation { waiter.attach($0) }
            } onCancel: {
                // Closing Settings or cancelling the caller must not leave a health-check
                // process running and this continuation suspended forever (#4592).
                signal(pid, SIGKILL)
                waiter.finish(nil)
            }
        }
    }
#else
    enum MCPHealthStatus: Equatable {
        case idle
        case checking
        case usable
        case unusable(String)
    }

    enum MCPHealthCheck {
        @MainActor
        static func run(executablePath _: String) async -> MCPHealthStatus {
            .unusable("The MCP server is only available on macOS.")
        }
    }
#endif
