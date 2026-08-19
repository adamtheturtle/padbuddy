import Darwin
import Foundation

nonisolated extension MCPActivityLog {
    static func readTail(at url: URL) throws -> ActivityLogTail {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw errno == ENOENT ? ActivityLogReadError.missing : .unavailable
        }

        defer { close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size >= 0 else {
            throw ActivityLogReadError.unavailable
        }

        var position = Int64(metadata.st_size)
        var chunks: [Data] = []
        var bytesRead = 0
        var newlineCount = 0
        while position > 0, bytesRead < maxReadBytes, newlineCount <= maxEntries {
            let count = min(64 * 1024, maxReadBytes - bytesRead, Int(position))
            position -= Int64(count)
            var chunk = Data(count: count)
            let actual = chunk.withUnsafeMutableBytes { bytes in
                pread(descriptor, bytes.baseAddress, count, position)
            }
            guard actual >= 0 else {
                if errno == EINTR {
                    position += Int64(count)
                    continue
                }
                throw ActivityLogReadError.unavailable
            }
            guard actual == count else { throw ActivityLogReadError.unavailable }

            newlineCount += chunk.count(where: { $0 == 0x0A })
            chunks.append(chunk)
            bytesRead += count
        }

        return try makeTail(chunks: chunks, bytesRead: bytesRead, position: position, descriptor: descriptor)
    }

    private static func makeTail(
        chunks: [Data], bytesRead: Int, position: Int64, descriptor: Int32
    ) throws -> ActivityLogTail {
        var data = Data(capacity: bytesRead)
        for chunk in chunks.reversed() {
            data.append(chunk)
        }
        var previousByte: UInt8 = 0
        let previousCount = position > 0 ? withUnsafeMutableBytes(of: &previousByte) { bytes in
            pread(descriptor, bytes.baseAddress, 1, position - 1)
        } : 0
        guard position == 0 || previousCount == 1 else {
            throw ActivityLogReadError.unavailable
        }

        let truncated = position > 0 && previousByte != 0x0A
        if truncated, let newline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(data.startIndex ... newline)
        } else if truncated {
            data.removeAll(keepingCapacity: false)
        }
        return ActivityLogTail(completeData: data, hasTruncatedLeadingLine: truncated)
    }
}

nonisolated struct ActivityLogTail {
    let completeData: Data
    let hasTruncatedLeadingLine: Bool
}

nonisolated enum ActivityLogReadError: Error {
    case missing
    case unavailable
}
