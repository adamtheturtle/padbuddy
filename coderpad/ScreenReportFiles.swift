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
import os
import Synchronization

nonisolated enum ScreenReportFiles {
    private static let logger = Logger(subsystem: "com.coderpad.app", category: "screen-reports")

    /// Folders staged by this process (keyed by their unique directory name), each
    /// with its scheduled removal task when one exists. The registry keeps the launch
    /// sweep from deleting a report staged concurrently (#1947), lets an explicit
    /// removal cancel its now-pointless scheduled task (#1117, #1948), and makes both
    /// paths idempotent.
    private static let active = Mutex([String: Task<Void, Never>?]())

    /// Every PDF starts with this marker (#1943).
    static let pdfMagic = Array("%PDF-".utf8)

    /// Whether the bytes plausibly are a PDF document.
    static func isLikelyPDF(_ data: Data) -> Bool {
        data.starts(with: pdfMagic)
    }

    /// The root folder under the app's temporary directory that holds every staged
    /// report, so launch cleanup can sweep them all in one pass.
    private static var root: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenReports", isDirectory: true)
    }

    /// Writes report data to a fresh single-use subdirectory (owner-only permissions)
    /// and returns the file URL to hand to the viewer. The filename keeps the test ID
    /// so the window title in Preview stays meaningful; uniqueness comes from the
    /// enclosing directory.
    static func stage(_ data: Data, testID: Int) throws -> URL {
        // Never put non-PDF bytes under a .pdf name for an external viewer, even if
        // a caller forgot its own validation (#1943).
        guard isLikelyPDF(data) else { throw CocoaError(.fileWriteUnknown) }

        let name = UUID().uuidString
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = folder.appendingPathComponent("ScreenReport-\(testID).pdf")
        do {
            // Atomic, so the viewer can never observe a partially written report
            // (#1115), and owner-only like its folder (#1385, #1949).
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // A failed write must not leave the sensitive single-use folder behind
            // (#1942).
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        active.withLock { $0[name] = .some(nil) }
        return url
    }

    /// Removes one staged report (its whole single-use subdirectory), cancelling any
    /// removal still scheduled for it (#1117). Deleting a file an external viewer has
    /// open is safe: the viewer's handle (or in-memory copy) keeps the data readable;
    /// the unlink only removes the name.
    static func remove(_ url: URL) {
        let folder = url.deletingLastPathComponent()
        // Only ever delete inside the staging root: a caller passing an unexpected
        // URL must not be able to remove an arbitrary parent directory (#1946).
        guard folder.deletingLastPathComponent().standardizedFileURL.path
            == root.standardizedFileURL.path else {
            logger.error("Refused to remove a Screen report outside the staging root.")
            return
        }

        let scheduled = active.withLock { $0.removeValue(forKey: folder.lastPathComponent) }
        if let scheduled, let scheduled { scheduled.cancel() }
        do {
            try FileManager.default.removeItem(at: folder)
        } catch CocoaError.fileNoSuchFile {
            // Already swept; both cleanup paths are idempotent (#1948).
        } catch {
            // Candidate data that couldn't be deleted is worth a trace, not silence
            // (#1116, #1387, #1944); the launch sweep retries next run.
            logger.error("Couldn't remove a staged Screen report: \(error.localizedDescription)")
        }
    }

    /// Removes a staged report once the viewer has had ample time to load it. If the
    /// app quits before the delay elapses, `cleanUpLeftovers()` sweeps it next launch.
    static func scheduleRemoval(of url: URL, after duration: Duration = .seconds(300)) {
        let name = url.deletingLastPathComponent().lastPathComponent
        let task = Task.detached(priority: .utility) {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }

            remove(url)
        }
        active.withLock { registry in
            if let previous = registry[name], let previous { previous.cancel() }
            registry[name] = task
        }
    }

    /// Launch-time sweep of reports left behind by earlier runs (e.g. the app quit
    /// before a scheduled removal fired). Reports staged by this process are skipped,
    /// so a late sweep can't race a concurrently opened report (#1947).
    static func cleanUpLeftovers() {
        let manager = FileManager.default
        let entries: [URL]
        do {
            entries = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        } catch CocoaError.fileReadNoSuchFile {
            // Nothing was ever staged (or a prior sweep finished the job).
            return
        } catch {
            // Reports hold candidate data: a sweep that can't even list the
            // staging root must not pass silently as if it cleaned up (#1959).
            logger.error("Couldn't sweep leftover Screen reports: \(error.localizedDescription)")
            return
        }

        let live = active.withLock { Set($0.keys) }
        for entry in entries where !live.contains(entry.lastPathComponent) {
            do {
                try manager.removeItem(at: entry)
            } catch {
                logger.error("Couldn't sweep a leftover Screen report: \(error.localizedDescription)")
            }
        }
    }
}
