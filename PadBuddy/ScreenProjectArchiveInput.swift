import Foundation

enum ScreenProjectArchiveInput {
    nonisolated static func validate(_ data: Data) throws {
        guard data.count >= 3, data.prefix(3) == Data([0x1F, 0x8B, 0x08]),
              data.count <= ScreenClient.maximumTemporaryFileBytes else {
            throw CoderPadError.decode(String(localized: "Choose a gzip archive no larger than 50 MiB."))
        }
    }

    nonisolated static func read(_ url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard url.isFileURL, try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw CoderPadError.decode(String(localized: "Choose a regular gzip archive file."))
        }

        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard try file.seekToEnd() <= UInt64(ScreenClient.maximumTemporaryFileBytes) else {
            throw CoderPadError.decode(String(localized: "Choose a gzip archive no larger than 50 MiB."))
        }

        try file.seek(toOffset: 0)
        var bytes = Data()
        while let chunk = try file.read(upToCount: 65536), !chunk.isEmpty {
            try Task.checkCancellation()
            guard chunk.count <= ScreenClient.maximumTemporaryFileBytes - bytes.count else {
                throw CoderPadError.decode(String(localized: "Choose a gzip archive no larger than 50 MiB."))
            }

            bytes.append(chunk)
        }
        try validate(bytes)
        return bytes
    }
}
