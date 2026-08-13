//
//  ExportStagingCleanup.swift
//  PadBuddy
//

import Foundation

nonisolated struct ExportStagingCleanupError: LocalizedError {
    let primary: String
    let cleanup: String

    var errorDescription: String? {
        "Export failed (\(primary)); temporary export cleanup also failed (\(cleanup))."
    }
}

nonisolated enum ExportStagingCleanup {
    static func rethrowing(
        _ primary: any Error,
        cleanup: () throws -> Void
    ) throws -> Never {
        do {
            try cleanup()
        } catch {
            throw ExportStagingCleanupError(
                primary: primary.localizedDescription,
                cleanup: error.localizedDescription
            )
        }
        throw primary
    }
}
