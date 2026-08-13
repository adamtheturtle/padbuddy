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

    enum MCPHealthCheck {
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

            let status = await terminationStatus(process, timeout: .seconds(5))
            guard let status else {
                return .unusable("The MCP server self-test timed out during startup.")
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if status == EXIT_SUCCESS {
                return .usable
            }
            if let message, !message.isEmpty {
                return .unusable(message)
            }
            return .unusable("The MCP server self-test failed.")
        }

        @MainActor
        private static func terminationStatus(
            _ process: Process, timeout: Duration
        ) async -> Int32? {
            await withCheckedContinuation { continuation in
                let completed = OSAllocatedUnfairLock(initialState: false)
                process.terminationHandler = { process in
                    let shouldResume = completed.withLock { completed in
                        guard !completed else { return false }

                        completed = true
                        return true
                    }
                    if shouldResume {
                        continuation.resume(returning: process.terminationStatus)
                    }
                }
                Task { @MainActor in
                    do {
                        try await MCPHealthTimeout.wait(for: timeout)
                    } catch is CancellationError {
                        return
                    } catch {
                        assertionFailure("MCP health-check timeout timer failed: \(error)")
                        return
                    }
                    let shouldResume = completed.withLock { completed in
                        guard !completed else { return false }

                        completed = true
                        return true
                    }
                    guard shouldResume else { return }

                    if process.isRunning {
                        process.terminate()
                    }
                    continuation.resume(returning: nil)
                }
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
