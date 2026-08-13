//
//  WidgetSnapshotMetadata.swift
//  RecentPadsWidget
//

import Foundation

enum WidgetSnapshotMetadataOutcome {
    case date(Date?)
    case failed(String)
}

enum WidgetSnapshotMetadata {
    static func modificationDate(
        at url: URL,
        using load: (URL) throws -> Date? = {
            try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
    ) -> WidgetSnapshotMetadataOutcome {
        do {
            return .date(try load(url))
        } catch {
            return .failed("Could not read the recent pads snapshot timestamp: \(error.localizedDescription)")
        }
    }
}
