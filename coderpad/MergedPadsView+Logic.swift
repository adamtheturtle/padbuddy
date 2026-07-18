//
//  MergedPadsView+Logic.swift
//  coderpad
//
//  Data, filtering, fan-out refresh, and per-account-routed actions for the
//  combined "All Accounts" pads list.
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

extension MergedPadsView {
    // MARK: - Combined + filtered data

    /// Every account's pads, tagged with their source account and sorted newest
    /// first. Read many times in one render (the filter pass, each filter chip's
    /// option list, the result count, the empty-state checks), so it's memoized
    /// into `scopedCache` once per render by `refreshScoped()`. Recomputing the
    /// cross-account sort on every read beach-balled the main thread on large
    /// merged orgs — most visibly when toggling a preset like "Mine", which fires
    /// several re-renders in quick succession.
    var scoped: [AccountScoped<Account, Pad>] {
        scopedCache.rows
    }

    /// Rebuild the memoized `scoped` rows when the underlying data changes. A
    /// reference-type cache (so `body` can refresh it without mutating SwiftUI state
    /// mid-evaluation), keyed to a cheap signature rather than "once per render": the
    /// O(n log n) cross-account sort and the chip-option Sets only rebuild when the
    /// merged pads (or sort) change, not on every keystroke / filter toggle (#366).
    func refreshScoped() {
        let mergeable = accounts.mergeableAccounts
        let signature = scopedSignature(mergeable: mergeable)
        guard scopedCache.signature != signature else { return }

        scopedCache.signature = signature

        var rows: [AccountScoped<Account, Pad>] = []
        for account in mergeable {
            for pad in padsByAccount[account.id] ?? [] {
                rows.append(AccountScoped(account: account, item: pad,
                                          id: Self.rowID(account: account.id, pad: pad.id)))
            }
        }
        let sorted = sort.sorted(rows, by: \.item, tieBreaker: \.id)
        scopedCache.rows = sorted
        // Rebuild the chip-option lists in the same pass (same input signature).
        scopedCache.availableStates = Array(Set(sorted.map(\.item.status)))
            .sorted { $0.label < $1.label }
        scopedCache.availableLanguages = Array(Set(sorted.compactMap { $0.item.language?.lowercased() })
            .filter { !$0.isEmpty }).sorted()
        scopedCache.availableOwners = Array(Set(sorted.map(\.item.ownerEmail))
            .filter { !$0.isEmpty }).sorted()
    }

    /// A cheap hash of everything `scoped` (and the chip-option lists) depends on: the
    /// sort and, per mergeable account, its id and every pad. `Pad` is `Hashable`, so
    /// any displayed-field change invalidates the memo (the cached rows carry these
    /// `Pad` values into the list). O(n) hashing replaces the O(n log n) sort + three
    /// Set passes that previously ran every render.
    func scopedSignature(mergeable: [Account]) -> Int {
        var hasher = Hasher()
        hasher.combine(sort)
        for account in mergeable {
            hasher.combine(account.id)
            let pads = padsByAccount[account.id] ?? []
            hasher.combine(pads.count)
            for pad in pads {
                hasher.combine(pad)
            }
        }
        return hasher.finalize()
    }

    /// The account-namespaced row id used for selection and list identity. Pad
    /// slugs are only unique per server, so two custom CoderPad servers can issue
    /// the same slug; the slug alone would collapse those rows into one identity
    /// and route actions to the wrong account (#758).
    static func rowID(account: UUID, pad: String) -> String {
        "\(account.uuidString):\(pad)"
    }

    var filtered: [AccountScoped<Account, Pad>] {
        // Rows scheduled for bulk deletion leave the list for the undo grace
        // period, so they can't be opened, edited, or re-selected while doomed;
        // Undo brings them straight back untouched (#1262).
        guard let pending = pendingBulkDeleteUndo else { return filteredCache.rows }

        let doomed = Set(pending.items.map(\.id))
        return filteredCache.rows.filter { !doomed.contains($0.id) }
    }

    func refreshFiltered() {
        // Skip the cross-account filter when nothing that affects the result changed.
        // `body` re-runs several times per click as the selection settles, and only the
        // selection differs across those passes — re-filtering the whole merged list each
        // time is what made clicking a row slow on large orgs (mirrors #395). `scoped` is
        // itself memoized (`refreshScoped()`), so its signature stands in for the rows.
        let now = Date()
        let key = FilteredScopedPadsCache.Key(
            scopedSignature: scopedCache.signature ?? 0,
            filterSignature: filterSignature,
            dateFilterTimeToken: dateFilterTimeToken(now: now),
            directoryCount: directory.nameByEmail.count
        )
        guard filteredCache.key != key else { return }

        let criteria = PadFilterCriteria(
            search: search, state: stateFilter, language: languageFilter,
            owner: ownerFilter, team: nil, type: typeFilter,
            updated: updatedWindow, created: createdWindow
        )
        filteredCache.rows = scoped.filter { row in
            (accountFilter == nil || row.account.id == accountFilter)
                && (!mineOnly || isMine(row))
                && PadListLogic.matches(row.item, criteria: criteria, now: now, display: directory.display)
        }
        filteredCache.key = key
    }

    var dateFilterClockActive: Bool {
        updatedWindow.isActive || createdWindow.isActive
    }

    func dateFilterTimeToken(now: Date = Date()) -> String? {
        PadListLogic.dateFilterCacheToken(updated: updatedWindow, created: createdWindow, now: now)
            .map { "\($0):\(dateFilterClockTick)" }
    }

    func runDateFilterClock() async {
        guard dateFilterClockActive else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }

            dateFilterClockTick &+= 1
        }
    }

    /// Whether `row`'s pad is owned by its own account's user. Ownership is account
    /// scoped, so "mine" is compared against each pad's source account.
    func isMine(_ row: AccountScoped<Account, Pad>) -> Bool {
        row.account.owns(row.item.ownerEmail)
    }

    /// The scoped row for a namespaced row id, used to resolve the List selection
    /// back to a specific account's pad (not just the first slug match, which can
    /// be the wrong account when two custom servers share a slug, #758).
    func row(forRowID rowID: String) -> AccountScoped<Account, Pad>? {
        scoped.first { $0.id == rowID }
    }

    /// The row to select after the row with `rowID` is deleted: the next visible
    /// row, then the previous, mirroring `MergedQuestionsView.neighborRowID`, so
    /// deleting the open pad keeps the detail pane populated. Returns a namespaced
    /// row id since selection is keyed by row, not bare pad slug (#758).
    func neighborRowID(forDeletedRowID rowID: String) -> String? {
        let visible = filtered
        guard let index = visible.firstIndex(where: { $0.id == rowID }) else { return visible.first?.id }

        if visible.indices.contains(index + 1) { return visible[index + 1].id }
        if visible.indices.contains(index - 1) { return visible[index - 1].id }
        return nil
    }

    /// Bridge a List selection change to the `Pad` binding and publish the row's
    /// source account so the detail pane routes to the right client (#758). A nil
    /// id clears the selection; a non-nil id that doesn't resolve yet (e.g. a row
    /// inserted this render) is left untouched so it isn't transiently blanked.
    func selectRow(_ rowID: String?) {
        guard let rowID else {
            selection = nil
            router.selectedPadAccountID = nil
            return
        }
        guard let scopedRow = row(forRowID: rowID) else { return }

        selection = scopedRow.item
        router.selectedPadAccountID = scopedRow.account.id
    }

    // MARK: - Options

    /// Chip-option lists, memoized alongside `scoped` and recomputed only when the
    /// merged pads change (#366) rather than rebuilt over every row on each access.
    var availableStates: [PadState] {
        scopedCache.availableStates
    }

    var availableLanguages: [String] {
        scopedCache.availableLanguages
    }

    var availableOwners: [String] {
        scopedCache.availableOwners
    }

    var activeFilterCount: Int {
        (stateFilter != nil ? 1 : 0)
            + [languageFilter, ownerFilter, typeFilter].compactMap(\.self).count
            + (accountFilter != nil ? 1 : 0)
            + (mineOnly ? 1 : 0)
            + (updatedWindow.isActive ? 1 : 0)
            + (createdWindow.isActive ? 1 : 0)
    }

    /// Applies a request queued by `AppNavigation`, matching the single-account Pads
    /// pane so person links work the same way in the combined "All Accounts" list.
    func applyPendingRequest() {
        guard let request = nav.padsRequest else { return }

        nav.padsRequest = nil
        if let saved = request.applySearch {
            apply(saved)
            // A wholesale search replaces the whole filter state; the account filter
            // isn't part of `NamedSearch`, so clear it explicitly or the sidebar's
            // root "Pads" row leaves it applied (#1001).
            accountFilter = nil
        }
        if let owner = request.ownerEmail { ownerFilter = owner }
        if let query = request.search { search = query }
        if request.startCreating, !isReadOnly {
            creatingSeedQuestionID = request.seedQuestionID
            creatingForAccount = newPadDefaultAccount
        }
        if let id = request.selectPadID {
            // `selectPadID` arrives as a bare slug from process-wide entry points
            // (e.g. the command palette in merged mode), but this list keys its
            // selection by account-namespaced row id (#758). Resolve it against the
            // loaded rows; when the row hasn't loaded yet, park the slug and let
            // `resolvePendingSlugSelection()` finish once it appears.
            if let scopedRow = scoped.first(where: { $0.item.id == id }) {
                selectedIDs = [scopedRow.id]
                pendingScrollToID = scopedRow.id
            } else {
                pendingSelectPadSlug = id
            }
        }
    }

    /// A change token so the `List` re-identifies (fast fresh render) whenever the
    /// filter shape changes, matching `PadsView`.
    var filterSignature: String {
        FilterSignature.make([
            search.trimmingCharacters(in: .whitespacesAndNewlines),
            stateFilter?.rawValue,
            languageFilter,
            ownerFilter,
            typeFilter,
            accountFilter?.uuidString,
            mineOnly ? "mine" : nil,
            // Include the custom bounds, not just the named range, so switching
            // between two custom date ranges actually changes the signature.
            updatedWindow.signatureToken,
            createdWindow.signatureToken
        ])
    }

    /// A token covering the set of accounts being merged (ids, keys, and endpoints),
    /// so the load task restarts when an account is added, removed, or rekeyed —
    /// without restarting on unrelated edits.
    var accountKey: String {
        accounts.mergeableAccounts.map {
            FilterSignature.make([
                $0.id.uuidString,
                $0.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                $0.resolvedBaseURL.absoluteString
            ])
        }
        .joined(separator: ",")
    }

    // MARK: - Loading

    /// Show the cached pads for every account immediately, before any network
    /// fetch, so the merged list is populated on appear.
    func seedFromCache() {
        for account in accounts.mergeableAccounts where padsByAccount[account.id] == nil {
            padsByAccount[account.id] = cache.get(account.id)
        }
        publishRoutes()
    }

    func hydrateFromCacheIfEmpty() {
        var changed = false
        for account in accounts.mergeableAccounts where padsByAccount[account.id]?.isEmpty != false {
            let warm = cache.cached(account.id)
            guard !warm.isEmpty else { continue }

            padsByAccount[account.id] = warm
            changed = true
        }
        if changed { publishRoutes() }
    }

    /// Fan out a fresh fetch across every account concurrently. Results are applied
    /// together after every account has answered, so the merged list does not first
    /// render one account and then visibly insert later accounts as they finish.
    func reload() async {
        let mergeable = accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }
        guard !mergeable.isEmpty else { return }

        // Claim the newest generation; an older overlapping reload stops before
        // applying, so its slower all-account result can't overwrite fresher
        // rows/cache/errors (#1226), and a cancelled task can't keep mutating
        // state after navigation or an account change (#1229).
        reloadGeneration &+= 1
        let generation = reloadGeneration

        isLoading = true
        defer { if generation == reloadGeneration { isLoading = false } }
        // Build the clients on the main actor; each is Sendable, so the concurrent
        // children below can hold one without crossing isolation to build it.
        let targets = mergeable.map { (id: $0.id, client: $0.makeClient()) }
        var fetchedByAccount: [UUID: [Pad]] = [:]
        var fetchedErrors: [UUID: String] = [:]

        await withTaskGroup(of: (UUID, [Pad]?, String?).self) { group in
            for target in targets {
                group.addTask {
                    do {
                        let pads = try await target.client.listPads(sort: "updated_at,desc")
                        return (target.id, pads, nil)
                    } catch {
                        return (target.id, nil, error.localizedDescription)
                    }
                }
            }
            for await (id, pads, errorText) in group {
                if let pads {
                    fetchedByAccount[id] = pads
                } else {
                    fetchedErrors[id] = errorText
                }
            }
        }
        guard generation == reloadGeneration, !Task.isCancelled else { return }

        // Apply only for accounts still configured: one removed or re-keyed while
        // the fetch ran must not resurface in rows or errors (#1224, #1230). The
        // cache setter separately validates the fetching client's credentials.
        let mergeableIDs = Set(accounts.mergeableAccounts.map(\.id))
        let clientsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.client) })
        for (id, pads) in fetchedByAccount where mergeableIDs.contains(id) {
            padsByAccount[id] = pads
            accountErrors[id] = nil
            if let client = clientsByID[id] {
                cache.set(id, pads: pads, via: client)
            }
        }
        for (id, errorText) in fetchedErrors where mergeableIDs.contains(id) {
            accountErrors[id] = errorText
        }
        // Prune rows and errors left by accounts that are gone, so a reintroduced
        // UUID can't inherit an old failure or stale list (#1230).
        padsByAccount = padsByAccount.filter { mergeableIDs.contains($0.key) }
        accountErrors = accountErrors.filter { mergeableIDs.contains($0.key) }
        publishRoutes()
        // Stamp the refresh time for the "Updated X ago" freshness cue (#619).
        lastRefreshed = Date()
        // Cold start with empty caches: the list first appears here, so this is the
        // earliest the saved selection can be resolved. Idempotent (guarded by
        // `didRestoreSelection`), so the per-refresh calls after this are no-ops.
        restoreSelectedPadIfNeeded()
        // Same timing for a favourite tapped before the list loaded: its slug can
        // only resolve to a namespaced row id once the row exists (#758).
        resolvePendingSlugSelection()
    }

    /// Publish the pad -> account map so the detail pane and row actions can route
    /// to the right client.
    func publishRoutes() {
        var routes: [String: UUID] = [:]
        for account in accounts.mergeableAccounts {
            for pad in padsByAccount[account.id] ?? [] {
                routes[pad.id] = account.id
            }
        }
        router.setPadRoutes(routes)
    }

    // The row mutations (edit/delete/create) live in MergedPadsView+Mutations.swift
    // and the open/delete row actions in MergedPadsView+Dialogs.swift (next to
    // the confirmations that trigger them) to keep this file under the length lint.
}
