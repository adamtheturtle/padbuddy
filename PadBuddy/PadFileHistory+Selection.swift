import Foundation

extension PadFileHistory {
    /// Prefer the newest, fullest response for each file rather than API delivery order.
    nonisolated static func preferredUnique(_ histories: [Self]) -> [Self] {
        var selected: [Self] = []
        var positions: [String: Int] = [:]
        for history in histories {
            if let index = positions[history.id] {
                if history.isPreferred(to: selected[index]) {
                    selected[index] = history
                }
            } else {
                positions[history.id] = selected.count
                selected.append(history)
            }
        }
        return selected
    }

    private nonisolated func isPreferred(to other: Self) -> Bool {
        let revision = (latestEntry?.timestamp ?? Int64.min, snapshots.count)
        let otherRevision = (other.latestEntry?.timestamp ?? Int64.min, other.snapshots.count)
        if revision != otherRevision {
            return revision > otherRevision
        }
        if wasTruncated != other.wasTruncated {
            return !wasTruncated
        }
        return (checkpoints.last?.contents ?? "") > (other.checkpoints.last?.contents ?? "")
    }
}
