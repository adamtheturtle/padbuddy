//
//  MergedQuestionsView+Logic.swift
//  coderpad
//
//  Data, filtering, fan-out refresh, and per-account-routed favorites for the
//  combined "All Accounts" questions list.
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

extension MergedQuestionsView {
    // MARK: - Combined + filtered data

    /// Every account's questions, tagged with their source account and arranged by
    /// the active sort. Memoized into `scopedCache`; read many times in one `body`
    /// (filter pass, chip options, counts, empty-state checks).
    var scoped: [MergedQuestionRow] {
        scopedCache.rows
    }

    /// Rebuild the memoized `scoped` rows when the underlying data or sort changes,
    /// rather than once per render: the tagged-array build, cross-account sort, and
    /// chip-option Sets only rerun when the merged questions actually change, not on
    /// every keystroke / selection / filter toggle (#366/#633). Reads only
    /// `questionsByAccount` so it never triggers a cache read.
    func refreshScoped() {
        let mergeable = accounts.mergeableAccounts
        let signature = scopedSignature(mergeable: mergeable)
        guard scopedCache.signature != signature else { return }

        scopedCache.signature = signature

        var rows: [MergedQuestionRow] = []
        for account in mergeable {
            for question in questionsByAccount[account.id] ?? [] {
                rows.append(MergedQuestionRow(account: account, item: question))
            }
        }
        scopedCache.rows = sort.sorted(rows, question: { $0.item }, tieBreaker: \.id)
        // Rebuild the chip-option lists in the same pass, sharing the input signature.
        scopedCache.availableLanguages = FilterOptionValues.boundedLanguages(rows.lazy.map(\.item.language))
        scopedCache.availableOwners = FilterOptionValues.boundedOwners(rows.lazy.map(\.item.ownerEmail))
    }

    /// A cheap signature of everything `scoped` (and the chip-option lists) depends
    /// on: the sort, the mergeable account set, and `questionsRevision` — bumped by
    /// every mutation of `questionsByAccount`. The revision stands in for the row
    /// contents, so the per-render O(n) full-model hash over every merged question
    /// (a main-actor stall on large orgs) is gone (#1235).
    func scopedSignature(mergeable: [Account]) -> Int {
        var hasher = Hasher()
        hasher.combine(sort)
        hasher.combine(questionsRevision)
        for account in mergeable {
            hasher.combine(account.id)
        }
        return hasher.finalize()
    }

    /// The account-namespaced row id used for selection and `ForEach` identity.
    /// Per-org question ids collide across accounts, so the id alone isn't unique.
    static func rowID(account: UUID, question: Int) -> String {
        "\(account.uuidString):\(question)"
    }

    /// Filtered rows arranged by the active sort, matching `QuestionsView.sorted`.
    /// Memoized into `sortedCache` once per render by `refreshSorted()`.
    var sorted: [MergedQuestionRow] {
        // Rows scheduled for bulk deletion leave the list for the undo grace
        // period, so they can't be opened, edited, or re-selected while doomed;
        // Undo brings them straight back untouched (#1262).
        guard let pending = pendingBulkDeleteUndo else { return sortedCache.rows }

        let doomed = Set(pending.items.map(\.id))
        return sortedCache.rows.filter { !doomed.contains($0.id) }
    }

    /// Rebuild the memoized filtered + sorted rows for one render. Folds the filter
    /// pass in here (rather than a separately-recomputed `filtered`) so the list,
    /// overlay, and count bar share a single pass.
    func refreshSorted() {
        // Skip the filter+sort on selection-only body passes (mirrors #395). `scoped` is
        // itself memoized, so its signature stands in for the rows; the favorites
        // revision is in the key so toggling a favorite still re-runs.
        let key = SortedQuestionsCache.Key(
            scopedSignature: scopedCache.signature ?? 0,
            filterSignature: filterSignature,
            favoritesOnly: favoritesOnly,
            favoritesRevision: favorites.revision
        )
        guard sortedCache.key != key else { return }

        sortedCache.key = key
        // Precompute each account's favorites once per rebuild, so both the favorites
        // *filter* and every row's `isFavorite` check are O(1) (#367), shared with the
        // row body and swipe actions. Built past the guard: one Set per account just to
        // compare in the key cost O(total favorites) allocations per render (#2084).
        // Duplicate mergeable UUIDs must not trap the combined Questions view (#4613).
        let favoritesByAccount = Dictionary(accounts.mergeableAccounts.map {
            ($0.id, Set(favorites.favorites(account: $0.id)))
        }, uniquingKeysWith: { first, _ in first })
        sortedCache.favoritesByAccount = favoritesByAccount
        let searchQuery = search.trimmingCharacters(in: .whitespacesAndNewlines)
        // Both sides lowercased/case-insensitive; mirrors the single-account
        // list (#1644, #1650).
        let languageQuery = languageFilter?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let now = Date()
        let filtered = scoped.filter { row in
            let item = row.item
            return (accountFilter == nil || row.account.id == accountFilter)
                && (!mineOnly || isMine(row))
                && (!favoritesOnly || (favoritesByAccount[row.account.id]?.contains(item.id) ?? false))
                && FilterOptionValues.language(item.language, matches: languageQuery)
                && FilterOptionValues.owner(item.ownerEmail, matches: ownerFilter)
                && (typeFilter == nil || item.interviewType.rawValue == typeFilter)
                && (draftFilter == nil
                    || (draftFilter == "draft" && item.isDraft == true)
                    || (draftFilter == "published" && item.isDraft != true))
                && matchesDateFilters(item, now: now)
                // Locale-aware case-insensitive matching (see PadListLogic.matches).
                && (searchQuery.isEmpty
                    || item.title.localizedCaseInsensitiveContains(searchQuery)
                    || item.ownerEmail.localizedCaseInsensitiveContains(searchQuery)
                    || (item.language ?? "").localizedCaseInsensitiveContains(searchQuery)
                    || (item.authorName ?? "").localizedCaseInsensitiveContains(searchQuery))
        }
        sortedCache.rows = filtered
    }

    func isMine(_ row: MergedQuestionRow) -> Bool {
        row.account.owns(row.item.ownerEmail)
    }

    func isFavorite(_ row: MergedQuestionRow) -> Bool {
        // Consult the per-render memo built by `refreshSorted()` — O(1), no per-call
        // array allocation (#367).
        sortedCache.favoritesByAccount[row.account.id]?.contains(row.item.id) ?? false
    }

    /// Whether any account has at least one starred question, gating the Favorites
    /// preset chip.
    var hasAnyFavorites: Bool {
        accounts.mergeableAccounts.contains { favorites.hasFavorites(account: $0.id) }
    }

    /// The scoped row for a namespaced row id, used to resolve the List selection
    /// back to a specific account's question (not just the first id match). Indexed
    /// with `scoped`, so selection and deletion no longer rescan every row (#2086).
    func row(forRowID rowID: String) -> MergedQuestionRow? {
        scopedCache.row(forID: rowID)
    }

    /// The row to select after the row with `rowID` is deleted: the next visible
    /// row, then the previous, mirroring `MergedPadsView.neighborSelection`, so
    /// deleting the open question keeps the detail pane populated. Returns a
    /// namespaced row id since selection is keyed by row, not bare question id.
    func neighborRowID(forDeletedRowID rowID: String) -> String? {
        let visible = sorted
        guard let index = visible.firstIndex(where: { $0.id == rowID }) else { return visible.first?.id }

        if visible.indices.contains(index + 1) {
            return visible[index + 1].id
        }
        if visible.indices.contains(index - 1) {
            return visible[index - 1].id
        }
        return nil
    }

    /// Bridge a List selection change to the `Question` binding and publish the
    /// row's source account so the detail pane routes to the right client. A nil id
    /// inserted this render) is left untouched so it isn't transiently blanked.
    /// inserted this render) is left untouched so it is not transiently blanked.
    func selectRow(_ rowID: String?) {
        guard let rowID else {
            selection = nil
            router.selectedQuestionAccountID = nil
            return
        }
        guard let scopedRow = row(forRowID: rowID) else { return }

        selection = scopedRow.item
        router.selectedQuestionAccountID = scopedRow.account.id
    }

    /// Select a specific scoped row (from a context menu or a freshly inserted
    /// question), keeping the List selection, the `Question` binding, and the
    /// routed account in step.
    func select(_ scopedRow: MergedQuestionRow) {
        router.selectedQuestionAccountID = scopedRow.account.id
        selection = scopedRow.item
        selectedRowID = scopedRow.id
        // Also move the List's own selection (the highlight) to this row, so a
        // context-menu action on an unselected row doesn't leave the visible
        // highlight pointing at a different row than the action targets.
        selectedRowIDs = [scopedRow.id]
    }

    // MARK: - Options

    /// Chip-option lists, memoized alongside `scoped` and recomputed only when the
    /// merged questions change (#366) rather than rebuilt over every row on each access.
    var availableLanguages: [String] {
        scopedCache.availableLanguages
    }

    var availableOwners: [String] {
        scopedCache.availableOwners
    }

    /// The account a global "New Question" targets in merged mode: the current
    /// account when it can create, else the first mergeable account that can.
    /// Mirrors `MergedPadsView.newPadDefaultAccount`.
    var newQuestionDefaultAccount: Account? {
        if let current = accounts.currentAccount, !current.apiKey.isEmpty {
            return current
        }
        return accounts.mergeableAccounts.first { !$0.apiKey.isEmpty }
    }

    /// Applies a request queued by `AppNavigation`, matching the single-account
    /// Questions pane. Without this consumer every global New Question entry point
    /// (⌘⇧N, the deep link, the palette) only switched sections in merged mode, and
    /// the unconsumed request later fired a surprise create sheet the moment a
    /// single-account Questions list mounted (#1000).
    func applyPendingRequest() {
        guard let request = nav.questionsRequest else { return }

        nav.questionsRequest = nil
        guard request.accountScope?.isCurrent == true else { return }

        if let saved = request.applySearch {
            apply(saved)
            // A wholesale search replaces the whole filter state; the account filter
            // isn't part of `NamedSearch`, so clear it explicitly or the sidebar's
            // root "Questions" row leaves it applied (#1001).
            accountFilter = nil
        }
        if let query = request.search {
            search = query
        }
        if request.startCreating, !isReadOnly {
            creatingForAccount = newQuestionDefaultAccount
        }
        if let id = request.selectQuestionID {
            // Per-org question ids collide across accounts, so a bare id request
            // (queued by single-account entry points) is honored only when exactly
            // one merged account holds it — selecting whichever account loads
            // first could silently open another org's question (#1233).
            // Account-carrying requests use `pendingMergedFavoriteQuestion`.
            let matches = scoped.filter { $0.item.id == id }
            if matches.count == 1, let scopedRow = matches.first {
                selectedRowIDs = [scopedRow.id]
                pendingScrollToRowID = scopedRow.id
            }
        }
    }

    var accountKey: [MergedAccountToken] {
        accounts.mergeableAccounts.map(MergedAccountToken.init(account:))
    }
}
