import SwiftUI

extension EnvironmentCodeCard {
    /// Starts one owned generation task. Retaining it lets the card cancel model
    /// work when it disappears or its file revision is replaced (#1900).
    func startExplanation() {
        explanationTask?.cancel()
        let generation = UUID()
        explanationGeneration = generation
        explanationTask = Task { await explainSelected(generation: generation) }
    }

    func cancelExplanation() {
        explanationTask?.cancel()
        explanationTask = nil
        explanationGeneration = UUID()
        isExplaining = false
    }

    func pruneExplanations() {
        let liveKeys = Set(files.map(\.explanationKey))
        explanations = explanations.filter { liveKeys.contains($0.key) }
        explanationLRU.removeAll { !liveKeys.contains($0) }
    }

    private func cache(_ explanation: CodeExplanation, for key: CodeFileExplanationKey) {
        explanations[key] = explanation
        explanationLRU.removeAll { $0 == key }
        explanationLRU.append(key)
        while explanationLRU.count > 8 {
            explanations.removeValue(forKey: explanationLRU.removeFirst())
        }
    }

    /// Generates or reuses an explanation keyed to an exact file revision.
    func explainSelected(generation: UUID) async {
        let file = selected
        let key = file.explanationKey
        if explanations[key] != nil {
            explanationLRU.removeAll { $0 == key }
            explanationLRU.append(key)
            showExplanation = true
            return
        }
        isExplaining = true
        explanationFailed = false
        defer {
            if explanationGeneration == generation { isExplaining = false }
        }
        let result = await PadCodeExplainer.explain(file: file)
        // A canceled, superseded, or changed-file request cannot publish stale UI
        // even when the model completes out of order (#749, #937, #1901).
        guard !Task.isCancelled else { return }
        guard explanationGeneration == generation else { return }
        guard selected.explanationKey == key else { return }

        if let result { cache(result, for: key) }
        explanationFailed = result == nil
        showExplanation = true
    }
}
