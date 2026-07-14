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
                rows.append(AccountScoped(account: account, item: pad, id: pad.id))
            }
        }
        let sorted = sort.sorted(rows, by: \.item)
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

    var filtered: [AccountScoped<Account, Pad>] {
        filteredCache.rows
    }

    func refreshFiltered() {
        // Skip the cross-account filter when nothing that affects the result changed.
        // `body` re-runs several times per click as the selection settles, and only the
        // selection differs across those passes — re-filtering the whole merged list each
        // time is what made clicking a row slow on large orgs (mirrors #395). `scoped` is
        // itself memoized (`refreshScoped()`), so its signature stands in for the rows.
        let key = FilteredScopedPadsCache.Key(
            scopedSignature: scopedCache.signature ?? 0,
            filterSignature: filterSignature,
            directoryCount: directory.nameByEmail.count
        )
        guard filteredCache.key != key else { return }

        let criteria = PadFilterCriteria(
            search: search, state: stateFilter, language: languageFilter,
            owner: ownerFilter, team: nil, type: typeFilter,
            updated: updatedWindow, created: createdWindow
        )
        let now = Date()
        filteredCache.rows = scoped.filter { row in
            (accountFilter == nil || row.account.id == accountFilter)
                && (!mineOnly || isMine(row))
                && PadListLogic.matches(row.item, criteria: criteria, now: now, display: directory.display)
        }
        filteredCache.key = key
    }

    /// Whether `row`'s pad is owned by its own account's user. Ownership is account
    /// scoped, so "mine" is compared against each pad's source account.
    func isMine(_ row: AccountScoped<Account, Pad>) -> Bool {
        row.account.owns(row.item.ownerEmail)
    }

    func pad(forID id: String) -> Pad? {
        // Resolve the owning account in O(1) via the route map and index into just
        // that account's pads, rather than scanning every account's full array (#368).
        if let accountID = router.padAccountID[id],
           let match = padsByAccount[accountID]?.first(where: { $0.id == id }) {
            return match
        }
        // Fallback: the route map can lag a just-inserted pad, so scan as before.
        for pads in padsByAccount.values {
            if let match = pads.first(where: { $0.id == id }) { return match }
        }
        return nil
    }

    /// The pad to select after the pad with `id` is deleted: the next visible row,
    /// then the previous, mirroring `PadsView.neighborSelection`.
    func neighborSelection(forDeleted id: String) -> Pad? {
        let visible = filtered.map(\.item)
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return visible.first }

        if visible.indices.contains(index + 1) { return visible[index + 1] }
        if visible.indices.contains(index - 1) { return visible[index - 1] }
        return nil
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
        if let saved = request.applySearch { apply(saved) }
        if let owner = request.ownerEmail { ownerFilter = owner }
        if let query = request.search { search = query }
        if request.startCreating, !isReadOnly {
            creatingSeedQuestionID = request.seedQuestionID
            creatingForAccount = newPadDefaultAccount
        }
        if let id = request.selectPadID {
            selectedIDs = [id]
            pendingScrollToID = id
        }
    }

    /// A change token so the `List` re-identifies (fast fresh render) whenever the
    /// filter shape changes, matching `PadsView`.
    var filterSignature: String {
        ([search, stateFilter?.rawValue, languageFilter, ownerFilter, typeFilter,
          accountFilter?.uuidString, mineOnly ? "mine" : nil]
                .map { $0 ?? "·" }
                // Include the custom bounds, not just the named range, so switching
                // between two custom date ranges actually changes the signature.
                + [updatedWindow.signatureToken, createdWindow.signatureToken])
            .joined(separator: "|")
    }

    /// A token covering the set of accounts being merged (ids + key emptiness), so
    /// the load task restarts when an account is added, removed, or has its key
    /// changed — without restarting on unrelated edits.
    var accountKey: String {
        accounts.mergeableAccounts.map { "\($0.id.uuidString):\($0.apiKey.isEmpty ? 0 : 1)" }
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

    /// Fan out a fresh fetch across every account concurrently. Results are applied
    /// together after every account has answered, so the merged list does not first
    /// render one account and then visibly insert later accounts as they finish.
    func reload() async {
        let mergeable = accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }
        guard !mergeable.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }
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

        for (id, pads) in fetchedByAccount {
            padsByAccount[id] = pads
            accountErrors[id] = nil
            cache.set(id, pads: pads)
        }
        for (id, errorText) in fetchedErrors {
            accountErrors[id] = errorText
        }
        publishRoutes()
        // Stamp the refresh time for the "Updated X ago" freshness cue (#619).
        lastRefreshed = Date()
        // Cold start with empty caches: the list first appears here, so this is the
        // earliest the saved selection can be resolved. Idempotent (guarded by
        // `didRestoreSelection`), so the per-refresh calls after this are no-ops.
        restoreSelectedPadIfNeeded()
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

    // MARK: - Mutations

    func applyUpdated(_ pad: Pad) {
        guard let accountID = router.padAccountID[pad.id],
              var pads = padsByAccount[accountID],
              let index = pads.firstIndex(where: { $0.id == pad.id }) else { return }

        pads[index] = pad
        padsByAccount[accountID] = pads
        if selection?.id == pad.id { selection = pad }
    }

    func removePad(id: String) {
        // Pad ids are global slugs, so the route map points at the single owning
        // account — drop the row from just that account rather than scanning and
        // rebuilding every account's array (#368).
        if let accountID = router.padAccountID[id],
           padsByAccount[accountID]?.contains(where: { $0.id == id }) == true {
            padsByAccount[accountID] = padsByAccount[accountID]?.filter { $0.id != id }
        } else {
            // Fallback when the route map doesn't have the pad yet.
            for (accountID, pads) in padsByAccount where pads.contains(where: { $0.id == id }) {
                padsByAccount[accountID] = pads.filter { $0.id != id }
            }
        }
        publishRoutes()
    }

    func insert(_ pad: Pad, into account: Account) {
        var pads = padsByAccount[account.id] ?? []
        pads.insert(pad, at: 0)
        padsByAccount[account.id] = pads
        cache.set(account.id, pads: pads)
        publishRoutes()
    }

    // MARK: - Actions

    func openPad(_ pad: Pad) {
        guard let url = pad.webURL else { return }

        BrowserSettings.openExternally(url)
    }

    func deletePad(_ pad: Pad) async {
        let client = (router.account(forPadID: pad.id) ?? accounts.currentAccount)?.makeClient()
        guard let client else { return }

        do {
            try await client.deletePad(id: pad.id)
            AppRouter.padDeleted(id: pad.id)
        } catch {
            deleteError = error.localizedDescription
        }
    }
}
