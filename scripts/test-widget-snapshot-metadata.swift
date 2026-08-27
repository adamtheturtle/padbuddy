// Compile together with RecentPadsWidget/WidgetSnapshotMetadata.swift.

import Foundation

private struct MetadataFailure: LocalizedError {
    var errorDescription: String? {
        "Container unavailable"
    }
}

@main
private enum WidgetSnapshotMetadataRegression {
    static func main() {
        let outcome = WidgetSnapshotMetadata.modificationDate(
            at: URL(fileURLWithPath: "/snapshot.json"),
            using: { _ in throw MetadataFailure() }
        )
        guard case let .failed(message) = outcome,
              message == "Could not read the recent pads snapshot timestamp: Container unavailable" else {
            fatalError("Widget snapshot timestamp failure lost its operation context")
        }
    }
}
