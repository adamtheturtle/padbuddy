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
            account: owningAccountID,
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
        // Both sides lowercased/case-insensitive: a saved or deep-linked filter
        // may carry "Swift" or a mixed-case email while the API values differ
        // only in casing (#1644, #1650).
        let languageQuery = languageFilter?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // An unrecognized draft value matched nothing, so a corrupt or stale persisted
        // filter emptied the list with no way to tell why. Anything that isn't one of
        // the two known states is ignored, which reads as "no draft filter" (#2496).
        let draftQuery = FilterValueValidation.draftState(draftFilter)
        let filtered = questions.filter { question in
            (favoriteFilter?.contains(question.id) ?? true) &&
                (languageQuery == nil || (question.language ?? "").lowercased() == languageQuery) &&
                (ownerFilter.map { question.ownerEmail.caseInsensitiveCompare($0) == .orderedSame } ?? true) &&
                (typeFilter == nil || question.interviewType.rawValue == typeFilter) &&
                (draftQuery == nil
                    || (draftQuery == "draft" && question.isDraft == true)
                    || (draftQuery == "published" && question.isDraft != true)) &&
                // Locale-aware case-insensitive matching (see PadListLogic.matches).
                (searchQuery.isEmpty
                    || question.title.localizedCaseInsensitiveContains(searchQuery)
                    || question.ownerEmail.localizedCaseInsensitiveContains(searchQuery)
                    || (question.language ?? "").localizedCaseInsensitiveContains(searchQuery)
                    || (question.authorName ?? "").localizedCaseInsensitiveContains(searchQuery))
        }
        listCache.sorted = applySort(filtered)
        // `uniquingKeysWith`, not `uniqueKeysWithValues`: duplicate ids do reach this
        // list (a cache seed overlapping a fresh page), and the trapping initializer
        // turned that into a crash (#2497). First occurrence wins, matching the row
        // the sorted list shows first.
        listCache.rowPresentations = Dictionary(
            listCache.sorted.map { question in
                (question.id, QuestionRowPresentation(question: question, account: nil))
            },
            uniquingKeysWith: { first, _ in first }
        )
        // The chip-option lists change only with `questions`, but recompute them in
        // the same pass so the filter bar's several reads don't each rebuild a Set.
        // Both normalized before de-duplication and sorted locale-aware. Case variants
        // of one language or owner otherwise became separate chips for the same filter,
        // and default `sorted()` orders by Unicode scalar, which puts every capitalized
        // entry ahead of every lowercase one and ignores locale collation (#2498).
        listCache.languages = Set(questions.compactMap {
            $0.language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        .filter { !$0.isEmpty }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        // Whitespace-only owner emails would render blank-looking, hard to
        // deselect Owner options and can persist unusable filters (#1662).
        listCache.owners = Set(questions.map {
            $0.ownerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        .filter { !$0.isEmpty }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
        /// The owning account: two orgs can coincidentally share a revision,
        /// filter signature, and favorite ids across an account swap, and the
        /// previous org's cached rows must not be reused then (#1206).
        let account: UUID?
        let questionsRevision: Int
        let filterSignature: String
        let favoritesOnly: Bool
        let sortRawValue: String
        /// Favorites drive both the favorites filter and each row's star, so a toggle
        /// must re-run; comparing the small id set is cheap and exact.
        let favoriteIDs: Set<Int>
    }
}
