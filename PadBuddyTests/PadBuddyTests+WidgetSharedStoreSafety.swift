import Foundation
@testable import PadBuddy
import Testing

@Suite("Widget shared-store reads")
struct WidgetSharedStoreSafetyTests {
    @Test
    func `oversized writes preserve the last readable snapshot`() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(WidgetSharedStore.save("original", to: url, purpose: "test"))
        let original = try Data(contentsOf: url)
        #expect(!WidgetSharedStore.save(
            String(repeating: "x", count: WidgetSharedStore.maxSnapshotFileBytes), to: url, purpose: "test"
        ))
        #expect(try Data(contentsOf: url) == original)
        #expect(WidgetSharedStore.loadData(url: url, purpose: "test") == original)
    }

    @Test func `replacement after open cannot change validated bytes`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-read-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = directory.appendingPathComponent("snapshot.json")
        let replacement = directory.appendingPathComponent("replacement.json")
        let original = Data("safe".utf8)
        try original.write(to: snapshot)
        try Data(repeating: 0x41, count: WidgetSharedStore.maxSnapshotFileBytes + 1).write(to: replacement)

        let loaded = WidgetSharedStore.loadData(url: snapshot, purpose: "test") {
            _ = try? FileManager.default.replaceItemAt(snapshot, withItemAt: replacement)
        }

        #expect(loaded == original)
    }

    @Test func `file growth is bounded while reading`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("growing-widget-\(UUID().uuidString).json")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = WidgetSharedStore.loadData(url: url, purpose: "test") {
            let handle = try? FileHandle(forWritingTo: url)
            try? handle?.write(contentsOf: Data(repeating: 0x41, count: WidgetSharedStore.maxSnapshotFileBytes + 1))
            try? handle?.close()
        }

        #expect(loaded == nil)
    }

    @Test func `symbolic links are rejected`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.json")
        let link = directory.appendingPathComponent("snapshot.json")
        try Data("secret".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(WidgetSharedStore.loadData(url: link, purpose: "test") == nil)
    }
}
