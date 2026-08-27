//
//  PadBuddyTests+ExportStagingCleanup.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Export staging cleanup")
struct ExportStagingCleanupTests {
    private struct ExportFailure: LocalizedError {
        var errorDescription: String? {
            "Destination unavailable"
        }
    }

    private struct CleanupFailure: LocalizedError {
        var errorDescription: String? {
            "Permission denied"
        }
    }

    @Test func `cleanup failure retains both export causes`() {
        do {
            try ExportStagingCleanup.rethrowing(ExportFailure()) {
                throw CleanupFailure()
            }
        } catch {
            #expect(error.localizedDescription
                == "Export failed (Destination unavailable); temporary export cleanup also failed (Permission denied).")
        }
    }
}
