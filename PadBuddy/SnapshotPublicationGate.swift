import Foundation

/// Publish the first available prefix immediately, then keep progress work off each page arrival.
nonisolated struct SnapshotPublicationGate {
    private var nextPublication: ContinuousClock.Instant?

    mutating func shouldPublish(at now: ContinuousClock.Instant = ContinuousClock.now) -> Bool {
        if let nextPublication, now < nextPublication {
            return false
        }

        nextPublication = now.advanced(by: .milliseconds(200))
        return true
    }
}
