import SwiftUI
import UniformTypeIdentifiers

struct ScreenProjectArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        []
    }

    static var writableContentTypes: [UTType] {
        [.gzip]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration _: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    nonisolated static func validate(_ data: Data, limit: Int) throws {
        guard data.count <= min(limit, 52_428_800) else {
            throw CoderPadError.decode(String(localized: "The project archive exceeds the download limit."))
        }
        guard data.count >= 3, data.prefix(3) == Data([0x1F, 0x8B, 0x08]) else {
            throw CoderPadError.decode(String(localized: "The service did not return a gzip project archive."))
        }
    }
}
