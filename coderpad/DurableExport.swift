//
//  DurableExport.swift
//  coderpad
//

#if os(macOS)
    import Darwin
    import Foundation

    nonisolated enum DurableExport {
        static func synchronizeTree(at root: URL) throws {
            let fileManager = FileManager.default
            let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: []
            )
            var directories = [root]
            while let url = enumerator?.nextObject() as? URL {
                let values = try url.resourceValues(forKeys: Set(keys))
                if values.isRegularFile == true {
                    try synchronizeFile(at: url)
                } else if values.isDirectory == true {
                    directories.append(url)
                }
            }
            for directory in directories.reversed() {
                try synchronizeDirectory(at: directory)
            }
        }

        static func synchronizeFile(at url: URL) throws {
            let handle = try FileHandle(forUpdating: url)
            defer { try? handle.close() }
            try handle.synchronize()
        }

        static func synchronizeDirectory(at url: URL) throws {
            let descriptor: Int32 = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return -1 }

                return open(path, O_RDONLY)
            }
            guard descriptor >= 0 else { throw posixError() }

            defer { close(descriptor) }
            guard fsync(descriptor) == 0 else { throw posixError() }
        }

        private static func posixError() -> POSIXError {
            POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
#endif
