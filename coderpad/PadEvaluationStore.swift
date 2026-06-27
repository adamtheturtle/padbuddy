//
//  PadEvaluationStore.swift
//  coderpad
//
//  A local, per-pad evaluation layer (#591): the interviewer's own rating, free-text
//  notes, and tags for a pad. This is private scratch data the CoderPad API doesn't
//  model, so it lives on-device in UserDefaults keyed by pad id rather than being
//  pushed back to the service. (iCloud sync parity - mirroring how favourites/saved
//  searches sync - is a deliberate follow-up; the store is the seam for it.)
//

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
}

@MainActor
@Observable
final class PadEvaluationStore {
    static let shared = PadEvaluationStore()

    private static let defaultsKey = "padEvaluations"

    /// Pad id -> evaluation. Only non-empty evaluations are kept.
    private var evaluations: [String: PadEvaluation]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: PadEvaluation].self, from: data) {
            evaluations = decoded
        } else {
            evaluations = [:]
        }
    }

    /// The evaluation for `padID`, or an empty one when the pad has never been evaluated.
    func evaluation(for padID: String) -> PadEvaluation {
        evaluations[padID] ?? PadEvaluation()
    }

    /// Stores `evaluation` for `padID`, dropping the entry when it's empty so cleared
    /// evaluations don't linger, then persists.
    func setEvaluation(_ evaluation: PadEvaluation, for padID: String) {
        let existing = evaluations[padID]
        if evaluation.isEmpty {
            guard existing != nil else { return }
            evaluations[padID] = nil
        } else {
            guard existing != evaluation else { return }
            evaluations[padID] = evaluation
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(evaluations) else { return }

        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
