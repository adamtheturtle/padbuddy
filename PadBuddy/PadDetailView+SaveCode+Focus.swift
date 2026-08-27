//
//  PadDetailView+SaveCode+Focus.swift
//  coderpad
//
//
//  Focused-value plumbing for Save All Code, and the staged-archive sweep.

import SwiftUI

extension FocusedValues {
    /// Whether the focused pad's detail pane has any code to save yet, published by
    /// `PadDetailView` so the Pad menu's "Save All Code…" command disables until at least
    /// one environment (or a legacy pad's inline contents) has loaded. `nil` when no
    /// pad detail is frontmost.
    @Entry var padHasSavableCode: Bool?
}

#if !os(macOS)
    /// A staged export for the iPad's `.fileExporter`, always a single file: a one-file
    /// pad (or the Markdown export) exports as plain text the user names; a multi-file pad
    /// exports as a `.zip` whose entries preserve the pad's project folder structure.
    ///
    /// A single file (rather than a directory `FileWrapper`) is deliberate: SwiftUI's
    /// `.fileExporter` writes a directory document to a same-named temporary path and
    /// throws "a file with the same name already exists" when a prior export of the same
    /// pad lingers there. Zipping keeps every export on the robust single-file path.
    struct PadExportDocument: FileDocument {
        static var readableContentTypes: [UTType] {
            []
        }

        static var writableContentTypes: [UTType] {
            [.plainText, .zip]
        }

        /// The content type handed to `.fileExporter` — `.plainText` for a single file,
        /// `.zip` for a multi-file pad.
        let contentType: UTType
        /// The default name the export sheet pre-fills (including the extension).
        let defaultName: String
        private let data: Data?
        /// The staged archive on disk for a multi-file export. Kept as a file (and
        /// mapped lazily by `fileWrapper`) rather than loaded into `data`: holding
        /// the archive bytes in Data AND in the FileWrapper doubled peak memory
        /// for large pads (#1741).
        private let archiveURL: URL?

        /// A single text file the user names in the export sheet.
        init(text: String, contentType: UTType, defaultName: String) {
            self.contentType = contentType
            self.defaultName = defaultName
            data = Data(text.utf8)
            archiveURL = nil
        }

        /// A multi-file pad zipped into one archive named after the pad, each file at its
        /// relative path (e.g. `src/main.rs`) so the project structure survives. Returns
        /// `nil` if the archive can't be built (the caller surfaces an error).
        init?(zipName: String, files: [(path: String, contents: String)]) {
            guard let archive = Self.zipFileURL(folderName: zipName, files: files) else { return nil }

            contentType = .zip
            defaultName = "\(zipName).zip"
            data = nil
            archiveURL = archive
        }

        init(configuration _: ReadConfiguration) throws {
            throw CocoaError(.featureUnsupported)
        }

        func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
            if let archiveURL {
                return try FileWrapper(url: archiveURL, options: [])
            }
            return FileWrapper(regularFileWithContents: data ?? Data())
        }

        /// Writes the files into a uniquely-named temporary folder, then uses
        /// `NSFileCoordinator`'s `.forUploading` option (Foundation's built-in zip) to
        /// archive it, copying the archive to a stable temporary file and returning
        /// its URL (disk-to-disk, never buffering the archive in memory, #1741).
        /// Cleans up the scratch directory. The staged archive must be deleted by
        /// ``discardStagedArchive()`` after the exporter finishes — the temp directory
        /// is not a safe place to leave candidate code (#4665).
        private static func zipFileURL(folderName: String,
                                       files: [(path: String, contents: String)]) -> URL? {
            let fileManager = FileManager.default
            let scratch = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let folder = scratch.appendingPathComponent(folderName)
            defer { try? fileManager.removeItem(at: scratch) }

            do {
                for file in files {
                    let destination = folder.appending(path: file.path)
                    try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
                    try Data(file.contents.utf8).write(to: destination)
                }
            } catch {
                return nil
            }

            var staged: URL?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading,
                                           error: &coordinationError) { zippedURL in
                let destination = fileManager.temporaryDirectory
                    .appendingPathComponent("\(stagedArchivePrefix)\(UUID().uuidString).zip")
                if (try? fileManager.copyItem(at: zippedURL, to: destination)) != nil {
                    staged = destination
                }
            }
            return staged
        }

        /// Filename prefix for staged multi-file export archives in the temp directory.
        static let stagedArchivePrefix = "padbuddy-export-"

        /// Deletes the on-disk archive after the system exporter finishes or cancels (#4665).
        func discardStagedArchive() {
            guard let archiveURL else { return }

            try? FileManager.default.removeItem(at: archiveURL)
        }

        /// Removes leftover `padbuddy-export-*.zip` archives from prior launches (#4665).
        @discardableResult
        static func sweepStagedArchives(
            in directory: URL = FileManager.default.temporaryDirectory,
            fileManager: FileManager = .default
        ) -> Int {
            sweepPadbuddyExportArchives(
                in: directory,
                fileManager: fileManager,
                prefix: stagedArchivePrefix
            )
        }
    }

    /// Clears a pending iPad export and deletes any staged ZIP it still owns (#4665).
    func clearPendingPadExport(_ document: inout PadExportDocument?) {
        document?.discardStagedArchive()
        document = nil
    }
#endif

/// Removes leftover staged multi-file export ZIPs from a directory (#4665).
@discardableResult
nonisolated func sweepPadbuddyExportArchives(
    in directory: URL,
    fileManager: FileManager = .default,
    prefix: String = "padbuddy-export-"
) -> Int {
    guard let urls = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ) else { return 0 }

    var removed = 0
    for url in urls {
        let name = url.lastPathComponent
        guard name.hasPrefix(prefix), name.hasSuffix(".zip") else { continue }

        do {
            try fileManager.removeItem(at: url)
            removed += 1
        } catch {
            continue
        }
    }
    return removed
}
