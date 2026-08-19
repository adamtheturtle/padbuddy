import Foundation
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

nonisolated extension DiskCache {
    func resolvedURL(kind: String, account: UUID) throws -> URL {
        guard Self.isValidKind(kind), Self.isValidDirectoryName(directoryName) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        try FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var descriptor = open(base.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw Self.directoryError() }

        defer { close(descriptor) }

        var directory = base
        for component in directoryName.split(separator: "/").map(String.init) {
            if mkdirat(descriptor, component, 0o700) != 0, errno != EEXIST {
                throw Self.directoryError()
            }
            let child = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            guard child >= 0 else { throw Self.directoryError() }
            guard fchmod(child, 0o700) == 0 else {
                close(child)
                throw Self.directoryError()
            }

            close(descriptor)
            descriptor = child
            directory.append(path: component, directoryHint: .isDirectory)
        }

        return directory.appending(path: "\(kind)-\(account.uuidString).json")
    }

    private static func directoryError() -> Error {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
