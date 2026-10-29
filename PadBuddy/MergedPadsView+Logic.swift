//
//  MergedPadsView+Logic.swift
//  coderpad
//
//  Data, filtering, fan-out refresh, and per-account-routed actions for the
//  combined "All Accounts" pads list.
//

// swiftlint:disable file_length

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
                guard MergedPadIdentity.validated(pad.id) != nil else { continue }

                rows.append(AccountScoped(account: account, item: pad,
                                          id: Self.rowID(account: account.id, pad: pad.id)))
            }
        }
        let sorted = sort.sorted(rows, by: \.item, tieBreaker: \.id)
        scopedCache.rows = sorted
        // Rebuild the chip-option lists in the same pass (same input signature).
        scopedCache.availableStates = Array(Set(sorted.map(\.item.status)))
            .sorted { $0.label < $1.label }
        scopedCache.availableLanguages = FilterOptionValues.boundedLanguages(sorted.lazy.map(\.item.language))
        scopedCache.availableOwners = FilterOptionValues.boundedOwners(sorted.lazy.map(\.item.ownerEmail))
    }

    /// A cheap signature of everything `scoped` (and the chip-option lists) depends
    /// on: the sort, the mergeable account set, `padsRevision` — bumped by every
    /// mutation of `padsByAccount` — and the directory revision. The revision stands
    /// in for the row contents, so the per-render O(n) full-model hash over every
    /// merged pad (a main-actor stall on large orgs) is gone (#1234).
    ///
    /// The directory revision is here for the reason `refreshFiltered` keys on it: an
    /// organization reload that renames members leaves the count equal. Without it the
    /// rows and filtered results updated while the Owner chip's menu still offered the
    /// old names, and selecting one matched nothing (#4792).
    func scopedSignature(mergeable: [Account]) -> Int {
        var hasher = Hasher()
        hasher.combine(sort)
        hasher.combine(padsRevision)
        hasher.combine(directory.revision)
        for account in mergeable {
            hasher.combine(account.id)
        }
        return hasher.finalize()
    }

    /// The account-namespaced row id used for selection and list identity. Pad
    /// slugs are only unique per server, so two custom CoderPad servers can issue
    /// the same slug; the slug alone would collapse those rows into one identity
    /// and route actions to the wrong account (#758).
    static func rowID(account: UUID, pad: String) -> String {
        // Invalid IDs never enter scoped rows. Keep rejected selection requests
        // bounded too, using a marker outside the pad-ID alphabet.
        "\(account.uuidString):\(MergedPadIdentity.validated(pad) ?? "!invalid")"
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
            directoryRevision: directory.revision
        )
        guard filteredCache.key != key else { return }

        let criteria = PadFilterCriteria(
            search: search, state: stateFilter, language: languageFilter,
            owner: ownerFilter, team: nil, type: typeFilter,
            updated: updatedWindow, created: createdWindow
        ).normalized // Normalized once, not once per row, in the predicate below (#2098).
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
            do {
                try await DateFilterClock.wait()
            } catch is CancellationError {
                return
            } catch {
                assertionFailure("Merged pad date-filter clock failed: \(error)")
                return
            }
            guard !Task.isCancelled else { return }

            dateFilterClockTick &+= 1
        }
    }

    /// Whether `row`'s pad is owned by its own account's user. Ownership is account
    /// scoped, so "mine" is compared against each pad's source account.
    func isMine(_ row: AccountScoped<Account, Pad>) -> Bool {
        row.account.owns(row.item.ownerEmail)
    }

    /// The scoped row for a namespaced row id, used to resolve the List selection back
    /// to a specific account's pad (not just the first slug match, which can be the
    /// wrong account when two servers share a slug, #758). Indexed, not scanned (#2100).
    func row(forRowID rowID: String) -> AccountScoped<Account, Pad>? {
        scopedCache.row(forID: rowID)
    }

    /// The row to select after the row with `rowID` is deleted: the next visible
    /// row, then the previous, mirroring `MergedQuestionsView.neighborRowID`, so
    /// deleting the open pad keeps the detail pane populated. Returns a namespaced
    /// row id since selection is keyed by row, not bare pad slug (#758).
    func neighborRowID(forDeletedRowID rowID: String) -> String? {
        let visible = filtered
        guard let index = visible.firstIndex(where: { $0.id == rowID }) else { return visible.first?.id }

        if visible.indices.contains(index + 1) {
            return visible[index + 1].id
        }
        if visible.indices.contains(index - 1) {
            return visible[index - 1].id
        }
        return nil
    }

    /// Bridge a List selection change to the `Pad` binding and publish the row's
    /// source account so the detail pane routes to the right client (#758). A nil
    /// inserted this render) is left untouched so it isn't transiently blanked.
    /// inserted this render) is left untouched so it is not transiently blanked.
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
        guard request.accountScope?.isCurrent == true else { return }

        if let saved = request.applySearch {
            apply(saved)
            // A wholesale search replaces the whole filter state; the account filter
            // isn't part of `NamedSearch`, so clear it explicitly or the sidebar's
            // root "Pads" row leaves it applied (#1001).
            accountFilter = nil
        }
        if let owner = request.ownerEmail {
            ownerFilter = owner
        }
        if let query = request.search {
            search = query
        }
        if request.startCreating, !isReadOnly {
            creatingSeedQuestionID = request.seedQuestionID
            creatingFallbackError = request.createError
            creatingForAccount = newPadDefaultAccount
        }
        if let id = request.selectPadID {
            // `selectPadID` arrives as a bare slug from process-wide entry points
            // (e.g. the command palette in merged mode), but this list keys its
            // selection by account-namespaced row id (#758). Resolve it against the
            // loaded rows — honoring the owning account when the request carries
            // one, since slugs collide across custom servers (#1255); when the row
            // hasn't loaded yet, park the slug and let
            // `resolvePendingSlugSelection()` finish once it appears.
            let owner = request.selectPadAccountID
            let matches = scoped.filter { $0.item.id == id && (owner == nil || $0.account.id == owner) }
            if let scopedRow = matches.first, owner != nil || matches.count == 1 {
                selectedIDs = [scopedRow.id]
                pendingScrollToID = scopedRow.id
            } else if matches.isEmpty {
                pendingSelectPadSlug = id
            }
            // Several bare-id matches: ambiguous — a deep link must not open a
            // nondeterministic account's pad, so the request is dropped (#1655),
            // mirroring resolvePendingSlugSelection (#1232).
        }
    }

    /// A change token so the `List` re-identifies (fast fresh render) whenever the
    /// filter shape changes, matching `PadsView`.
    var filterSignature: FilterSignature {
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
    var accountKey: [MergedAccountToken] {
        accounts.mergeableAccounts.map(MergedAccountToken.init(account:))
    }

    // MARK: - Loading

    /// Show the cached pads for every account immediately, before any network
    /// fetch, so the merged list is populated on appear.
    func seedFromCache() {
        var changed = false
        for account in accounts.mergeableAccounts where padsByAccount[account.id] == nil {
            padsByAccount[account.id] = cache.get(account.id)
            changed = true
        }
        if changed {
            padsRevision += 1
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
        if changed {
            padsRevision += 1
            publishRoutes()
        }
    }

    /// Fan out a fresh fetch across every account concurrently. Results are applied
    /// together after every account has answered, so the merged list does not first
    /// render one account and then visibly insert later accounts as they finish.
    func reload(force: Bool = false) async { // swiftlint:disable:this function_body_length
        reportIneligibleAccounts()
        let mergeable = MergedAccountFetch.eligibleAccounts(accounts.mergeableAccounts)
        guard !mergeable.isEmpty else { return }

        // Claim the newest generation; an older overlapping reload stops before
        // rows/cache/errors (#1226), and a cancelled task can't keep mutating
        // rows/cache/errors (#1226), and a cancelled task cannot keep mutating
        // state after navigation or an account change (#1229).
        reloadGeneration &+= 1
        let generation = reloadGeneration

        isLoading = true
        defer {
            if generation == reloadGeneration {
                isLoading = false
            }
        }
        // Build Sendable clients on the main actor before concurrent children use them.
        let targets = mergeable.map { (id: $0.id, client: $0.makeClient()) }
        let loadContext = cacheLoadContext(targets)
        let health = NavigationPrefetchHealth.snapshot(kind: .pads).filter { loadContext.clients[$0.key] != nil }
        accountErrors.merge(health) { current, _ in current }
        var fetchedByAccount: [UUID: [Pad]] = [:]
        var fetchedErrors: [UUID: String] = [:]

        let results: [(UUID, Result<[Pad], any Error>)] = await MergedAccountFetch.results(
            for: targets, shouldContinue: { generation == reloadGeneration }, fetch: { target in
                do {
                    let values = try await APIReadCoordinator.shared.pads(
                        accountID: target.id, client: target.client, force: force
                    )
                    return (target.id, .success(values))
                } catch {
                    return (target.id, .failure(error))
                }
            }
        )
        for (id, result) in results {
            switch result {
            case let .success(values): fetchedByAccount[id] = values
            case let .failure(error):
                fetchedErrors[id] = ExternalText.singleLine(error.localizedDescription, limit: 512)
            }
        }
        guard generation == reloadGeneration, !Task.isCancelled else { return }

        // Apply only for accounts still configured: one removed or re-keyed while
        // the fetch ran must not resurface in rows or errors (#1224, #1230). The
        // cache setter separately validates the fetching client's credentials.
        let mergeableIDs = Set(accounts.mergeableAccounts.map(\.id))
        for (id, pads) in fetchedByAccount where mergeableIDs.contains(id) {
            padsByAccount[id] = pads
            accountErrors[id] = nil
            NavigationPrefetchHealth.clear(account: id, kind: .pads)
            if let client = loadContext.clients[id], let cacheLoad = loadContext.loads[id] {
                persistFetchedPads(pads, account: id, client: client, cacheLoad: cacheLoad)
            }
        }
        for (id, errorText) in fetchedErrors where mergeableIDs.contains(id) {
            accountErrors[id] = errorText
        }
        // Prune rows and errors left by accounts that are gone, so a reintroduced
        // UUID can't inherit an old failure or stale list (#1230).
        padsByAccount = padsByAccount.filter { mergeableIDs.contains($0.key) }
        accountErrors = accountErrors.filter { mergeableIDs.contains($0.key) }
        padsRevision += 1
        publishRoutes()
        lastRefreshed = Date()
        // Cold start with empty caches: the list first appears here, so this is the
        // earliest the saved selection can be resolved. Idempotent (guarded by
        // `didRestoreSelection`), so the per-refresh calls after this are no-ops.
        restoreSelectedPadIfNeeded(loadComplete: true)
        // Same timing for a favourite tapped before the list loaded: its slug can
        // only resolve to a namespaced row id once the row exists (#758).
        resolvePendingSlugSelection(loadComplete: true)
    }

    private func persistFetchedPads(_ pads: [Pad], account: UUID, client: CoderPadClient, cacheLoad: Int) {
        guard accounts.isCurrentClient(client, for: account) else { return }

        cache.set(account, pads: pads, via: client, accepting: cacheLoad)
        PadOpenedStore.shared.reconcile(account: account, presentPadIDs: Set(pads.map(\.id)))
    }

    /// Publish bounded ownership information. Two distinct owners are sufficient
    /// to reject an ambiguous bare slug; selected rows carry their account directly.
    func publishRoutes() {
        let sources = accounts.mergeableAccounts.lazy.map { ($0.id, padsByAccount[$0.id] ?? []) }
        router.setPadRoutes(MergedPadRouteIndex.build(sources))
    }

    private func reportIneligibleAccounts() {
        for account in accounts.mergeableAccounts where !account.isInterviewFetchEligible {
            accountErrors[account.id] = account.interviewFetchUnavailableMessage
        }
    }

    // Row mutations live in MergedPadsView+Mutations.swift; open/delete actions live in
    // MergedPadsView+Dialogs.swift beside their confirmations, keeping this file within lint limits.
}
