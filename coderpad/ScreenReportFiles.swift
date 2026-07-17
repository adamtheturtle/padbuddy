//
//  ScreenReportFiles.swift
//  coderpad
//
//  Temporary-file handling for opened Screen report PDFs (#804, #807). Reports carry
//  candidate identity, scores, and proctoring data, and Screen test IDs are only unique
//  within one organization, so each opened report is staged in its own single-use
//  subdirectory (restrictive permissions, unique path per invocation - reports from two
//  accounts with the same test ID can never overwrite each other) and deleted again:
//  shortly after the viewer has opened it, and at the next launch for anything left
//  behind by an earlier run.
//

import Foundation

nonisolated enum ScreenReportFiles {
    /// The root folder under the app's temporary directory that holds every staged
    /// report, so launch cleanup can sweep them all with one remove.
    private static var root: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenReports", isDirectory: true)
    }

    /// Writes report data to a fresh single-use subdirectory (owner-only permissions)
    /// and returns the file URL to hand to the viewer. The filename keeps the test ID
    /// so the window title in Preview stays meaningful; uniqueness comes from the
    /// enclosing directory.
    static func stage(_ data: Data, testID: Int) throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = folder.appendingPathComponent("ScreenReport-\(testID).pdf")
        try data.write(to: url)
        return url
    }

    /// Removes one staged report (its whole single-use subdirectory).
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// Removes a staged report once the viewer has had ample time to load it. Deleting
    /// an open file is safe (the viewer keeps its own handle or in-memory copy); if the
    /// app quits before the delay elapses, `cleanUpLeftovers()` sweeps it next launch.
    static func scheduleRemoval(of url: URL, after duration: Duration = .seconds(300)) {
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: duration)
            remove(url)
        }
    }

    /// Launch-time sweep of reports left behind by earlier runs (e.g. the app quit
    /// before a scheduled removal fired).
    static func cleanUpLeftovers() {
        try? FileManager.default.removeItem(at: root)
    }
}
