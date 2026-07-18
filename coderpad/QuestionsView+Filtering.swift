//
//  QuestionsView+Filtering.swift
//  coderpad
//
//  The single-account questions list's per-render filter+sort memo and chip-option
//  lists. Split out of QuestionsView+List so that file stays under the project's
//  file-length lint, mirroring the merged list's +Logic split.
//

import SwiftUI

extension QuestionsView {
    /// Filtered questions arranged by the active sort, memoized once per render by
    /// `refreshSorted()` so the body's several readers (count, ForEach, selection)
    /// share one filter + sort pass instead of each re-running it over thousands of
    /// rows (#365). Mirrors `PadsView`/`MergedQuestionsView`.
    var sorted: [Question] {
        // Rows scheduled for bulk deletion leave the list for the undo grace
        // period, so they can't be opened, edited, or re-selected while doomed;
        // Undo brings them straight back untouched (#1262).
        guard let pending = pendingBulkDeleteUndo else { return listCache.sorted }

        let doomed = Set(pending.items.map(\.id))
        return listCache.sorted.filter { !doomed.contains($0.id) }
    }

    /// The current account's favorite question ids, memoized once per render so a
    /// membership test (filtering, sorting, every row's star) is O(1) and doesn't
    /// rebuild the Set per row.
    var favoriteIDSet: Set<Int> {
        listCache.favoriteIDSet
    }

    var availableLanguages: [String] {
        listCache.languages
    }

    var availableOwners: [String] {
        listCache.owners
    }

    /// Rebuild the per-render memo. A reference-type cache, so `body` can refresh it
    /// without mutating SwiftUI state mid-evaluation. Called once at the top of `body`.
    func refreshSorted() {
        let favoriteIDs = Set(favorites.favorites(account: accounts.currentAccountID))
        // Skip the filter+sort on selection-only body passes (mirrors #395). A click
        // re-runs body several times and only the selection differs; favoriteIDs is in
        // the key so toggling a favorite still re-runs.
        let key = QuestionsListCache.Key(
            questionsRevision: questionsRevision,
            filterSignature: filterSignature,
            favoritesOnly: favoritesOnly,
            sortRawValue: sort.rawValue,
            favoriteIDs: favoriteIDs
        )
        guard listCache.key != key else { return }

        listCache.key = key

        listCache.favoriteIDSet = favoriteIDs
        let favoriteFilter = favoritesOnly ? favoriteIDs : nil
        let searchQuery = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = questions.filter { question in
            (favoriteFilter?.contains(question.id) ?? true) &&
                (languageFilter == nil || (question.language ?? "").lowercased() == languageFilter) &&
                (ownerFilter == nil || question.ownerEmail == ownerFilter) &&
                (typeFilter == nil || question.interviewType.rawValue == typeFilter) &&
                (draftFilter == nil
                    || (draftFilter == "draft" && question.isDraft == true)
                    || (draftFilter == "published" && question.isDraft != true)) &&
                // Locale-aware case-insensitive matching (see PadListLogic.matches).
                (searchQuery.isEmpty
                    || question.title.localizedCaseInsensitiveContains(searchQuery)
                    || question.ownerEmail.localizedCaseInsensitiveContains(searchQuery)
                    || (question.language ?? "").localizedCaseInsensitiveContains(searchQuery)
                    || (question.authorName ?? "").localizedCaseInsensitiveContains(searchQuery))
        }
        listCache.sorted = applySort(filtered)
        listCache.rowPresentations = Dictionary(
            uniqueKeysWithValues: listCache.sorted.map { question in
                (question.id, QuestionRowPresentation(question: question, account: nil))
            }
        )
        // The chip-option lists change only with `questions`, but recompute them in
        // the same pass so the filter bar's several reads don't each rebuild a Set.
        listCache.languages = Array(Set(questions.compactMap { $0.language?.lowercased() })
            .filter { !$0.isEmpty }).sorted()
        listCache.owners = Array(Set(questions.map(\.ownerEmail)).filter { !$0.isEmpty }).sorted()
    }

    /// Arrange `items` by the active sort. Favorites keep their natural position;
    /// the Favorites chip filters the list down to them when needed.
    private func applySort(_ items: [Question]) -> [Question] {
        sort.sorted(items)
    }
}

/// Per-render memo for the single-account questions list (a reference type, not
/// `@Observable`) so `body` can refresh it without mutating SwiftUI state
/// mid-evaluation, mirroring the other list views' caches (#365).
final class QuestionsListCache {
    var sorted: [Question] = []
    var rowPresentations: [Int: QuestionRowPresentation] = [:]
    var favoriteIDSet: Set<Int> = []
    var languages: [String] = []
    var owners: [String] = []
    /// The inputs the cached rows were filtered+sorted for. A row click re-runs `body`
    /// several times via the selection cascade, and only the selection differs across
    /// those passes — so when this key is unchanged `refreshSorted()` reuses the cached
    /// rows instead of re-running the O(n) filter (with its per-row case-insensitive
    /// search) and sort each time, mirroring the single-account pad fix in #395.
    var key: Key?

    struct Key: Equatable {
        let questionsRevision: Int
        let filterSignature: String
        let favoritesOnly: Bool
        let sortRawValue: String
        /// Favorites drive both the favorites filter and each row's star, so a toggle
        /// must re-run; comparing the small id set is cheap and exact.
        let favoriteIDs: Set<Int>
    }
}
