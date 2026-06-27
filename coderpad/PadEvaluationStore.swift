//
//  PadEvaluationStore.swift
//  coderpad
//
//  A per-pad evaluation layer (#591): the interviewer's own rating, free-text notes,
//  and tags for a pad. This is private scratch data the CoderPad API doesn't model, so
//  it lives on-device in UserDefaults keyed by pad id rather than being pushed back to
//  the service — and, like favourites / saved searches / pad-open history, it now also
//  mirrors through iCloud so it follows the interviewer across their devices (#598).
//

import BuddyAppKit
import Foundation
import Observation

/// One pad's interviewer-private evaluation. `rating` is 0 when unrated, otherwise 1...5.
struct PadEvaluation: Codable, Equatable {
    var rating: Int = 0
    var notes: String = ""
    var tags: [String] = []

    /// True when nothing has been entered, so the store can drop the entry entirely
    /// rather than persist an empty record.
    var isEmpty: Bool {
        rating == 0 && notes.isEmpty && tags.isEmpty
    }

    /// Splits a comma-separated tag string into clean tags: trimmed, non-empty, and
    /// de-duplicated case-insensitively while preserving the order they were typed.
    /// Shared by the editor (live preview + save) so both agree on the stored form.
    static func parseTags(from text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}

@MainActor
@Observable
final class PadEvaluationStore {
    static let shared = PadEvaluationStore()

    private static let defaultsKey = "padEvaluations"
    /// When each pad's evaluation was last edited, so the iCloud merge can keep the most
    /// recent edit per pad (last-writer-wins by recency). Kept in a sibling key so the
    /// evaluation blob under `defaultsKey` stays the plain `[padID: PadEvaluation]` map
    /// older builds already wrote.
    private static let updatedAtKey = "padEvaluations.updatedAt.v1"
    /// The iCloud mirror carries both maps under one key. Evaluations are global by pad
    /// id (a CoderPad slug is unique across orgs), and these are the interviewer's own
    /// private notes, so unlike the per-account stores this syncs as a single flat blob
    /// tied to the person's iCloud rather than to any one CoderPad account (#598).
    private static let cloudKey = "padEvaluations.cloud.v1"

    /// Pad id -> evaluation. Only non-empty evaluations are kept.
    private var evaluations: [String: PadEvaluation]
    /// Pad id -> when its evaluation was last edited on this device, used only for merge
    /// recency. Entries can be absent (e.g. evaluations written by a build before sync),
    /// which the merge treats as `.distantPast`.
    private var updatedAt: [String: Date]
    /// Held so the external-change observation task isn't cancelled; the store is a
    /// singleton that lives for the whole process, so it's never explicitly stopped.
    private var cloudObserverTask: Task<Void, Never>?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: PadEvaluation].self, from: data) {
            evaluations = decoded
        } else {
            evaluations = [:]
        }
        if let data = UserDefaults.standard.data(forKey: Self.updatedAtKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            updatedAt = decoded
        } else {
            updatedAt = [:]
        }
        // Re-pull and merge whenever iCloud reports an external change to our mirror.
        cloudObserverTask = Task { @MainActor in
            for await note in NotificationCenter.default.notifications(named: CloudSyncStore.didChangeExternally) {
                guard note.userInfo?["key"] as? String == Self.cloudKey else { continue }

                Self.shared.syncFromCloud()
            }
        }
    }

    /// The evaluation for `padID`, or an empty one when the pad has never been evaluated.
    func evaluation(for padID: String) -> PadEvaluation {
        evaluations[padID] ?? PadEvaluation()
    }

    /// Stores `evaluation` for `padID`, dropping the entry when it's empty so cleared
    /// evaluations don't linger, then persists. `now` stamps the edit time for the
    /// iCloud merge and is injectable for tests.
    func setEvaluation(_ evaluation: PadEvaluation, for padID: String, now: Date = Date()) {
        let existing = evaluations[padID]
        if evaluation.isEmpty {
            guard existing != nil else { return }
            evaluations[padID] = nil
            updatedAt[padID] = nil
        } else {
            guard existing != evaluation else { return }
            evaluations[padID] = evaluation
            updatedAt[padID] = now
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(evaluations) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        if let data = try? JSONEncoder().encode(updatedAt) {
            UserDefaults.standard.set(data, forKey: Self.updatedAtKey)
        }
        mirrorToCloud()
    }

    // MARK: - iCloud sync (#598)

    /// The shape mirrored to iCloud: the evaluations map plus its per-pad edit times,
    /// so a pull can resolve conflicts by recency.
    private struct CloudPayload: Codable {
        var evaluations: [String: PadEvaluation]
        var updatedAt: [String: Date]
    }

    /// Pushes the current evaluations (and their edit times) up to iCloud. No-op when
    /// iCloud is unavailable (#598).
    private func mirrorToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        let payload = CloudPayload(evaluations: evaluations, updatedAt: updatedAt)
        if let data = try? JSONEncoder().encode(payload) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudKey)
        }
    }

    /// Pulls the iCloud evaluations and merges them into the local set, keeping the most
    /// recently edited evaluation per pad, then persists. Called once accounts have
    /// loaded and on every external iCloud change. No-op when iCloud is unavailable.
    func syncFromCloud() {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let payload = try? JSONDecoder().decode(CloudPayload.self, from: data) else { return }

        let merged = Self.merged(
            cloudEvaluations: payload.evaluations,
            cloudUpdatedAt: payload.updatedAt,
            localEvaluations: evaluations,
            localUpdatedAt: updatedAt
        )
        guard merged.evaluations != evaluations || merged.updatedAt != updatedAt else { return }

        evaluations = merged.evaluations
        updatedAt = merged.updatedAt
        persist()
    }

    /// Pure last-writer-wins-by-recency merge: starts from the local set and, for each
    /// pad present in the cloud, takes the cloud evaluation when the local side has none
    /// (additive union, so neither device's pads are lost) or when the cloud edit is
    /// strictly newer. Deletions do NOT propagate, matching the other synced stores — a
    /// pad cleared on one device is re-added from the cloud copy. Factored out so the
    /// merge semantics are unit-testable without iCloud.
    static func merged(
        cloudEvaluations: [String: PadEvaluation],
        cloudUpdatedAt: [String: Date],
        localEvaluations: [String: PadEvaluation],
        localUpdatedAt: [String: Date]
    ) -> (evaluations: [String: PadEvaluation], updatedAt: [String: Date]) {
        var evaluations = localEvaluations
        var updatedAt = localUpdatedAt
        for (padID, cloudEvaluation) in cloudEvaluations {
            let cloudDate = cloudUpdatedAt[padID] ?? .distantPast
            let localDate = localUpdatedAt[padID] ?? .distantPast
            guard evaluations[padID] == nil || cloudDate > localDate else { continue }

            evaluations[padID] = cloudEvaluation
            updatedAt[padID] = cloudDate
        }
        return (evaluations, updatedAt)
    }
}
