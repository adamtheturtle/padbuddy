//
//  MergedPadsView+Logic.swift
//  coderpad
//
//  Data, filtering, fan-out refresh, and per-account-routed actions for the
//  combined "All Accounts" pads list.
//

import AppKit
import SwiftUI

extension MergedPadsView {
    // MARK: - Combined + filtered data

    /// Every account's pads, tagged with their source account and sorted newest
    /// first. Reads only `padsByAccount` (seeded from cache, then refreshed) so a
    /// `body` evaluation never triggers a cache read.
    var scoped: [AccountScoped<Pad>] {
        var rows: [AccountScoped<Pad>] = []
        for account in accounts.mergeableAccounts {
            for pad in padsByAccount[account.id] ?? [] {
                rows.append(AccountScoped(account: account, item: pad, id: pad.id))
            }
        }
        return rows.sorted {
            ($0.item.updatedAt ?? $0.item.createdAt ?? .distantPast)
                > ($1.item.updatedAt ?? $1.item.createdAt ?? .distantPast)
        }
    }

    var filtered: [AccountScoped<Pad>] {
        filteredCache.rows
    }

    func refreshFiltered() {
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
    }

    /// Whether `row`'s pad is owned by its own account's user. Ownership is account
    /// scoped, so "mine" is compared against each pad's source account.
    func isMine(_ row: AccountScoped<Pad>) -> Bool {
        let email = row.account.userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return false }
        return row.item.ownerEmail.caseInsensitiveCompare(email) == .orderedSame
    }

    func pad(forID id: String) -> Pad? {
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

    var availableStates: [PadState] {
        Array(Set(scoped.map(\.item.status))).sorted { $0.label < $1.label }
    }

    var availableLanguages: [String] {
        Array(Set(scoped.compactMap { $0.item.language?.lowercased() }).filter { !$0.isEmpty }).sorted()
    }

    var availableOwners: [String] {
        Array(Set(scoped.map(\.item.ownerEmail)).filter { !$0.isEmpty }).sorted()
    }

    var activeFilterCount: Int {
        (stateFilter != nil ? 1 : 0)
            + [languageFilter, ownerFilter, typeFilter].compactMap(\.self).count
            + (accountFilter != nil ? 1 : 0)
            + (mineOnly ? 1 : 0)
            + (updatedWindow.isActive ? 1 : 0)
            + (createdWindow.isActive ? 1 : 0)
    }

    func clearAllFilters() {
        stateFilter = nil; languageFilter = nil; ownerFilter = nil; typeFilter = nil
        accountFilter = nil; mineOnly = false
        updatedWindow = PadDateWindow(); createdWindow = PadDateWindow()
    }

    /// A change token so the `List` re-identifies (fast fresh render) whenever the
    /// filter shape changes, matching `PadsView`.
    var filterSignature: String {
        ([search, stateFilter?.rawValue, languageFilter, ownerFilter, typeFilter,
          accountFilter?.uuidString, mineOnly ? "mine" : nil]
                .map { $0 ?? "·" }
                + [updatedWindow.range ?? "·", createdWindow.range ?? "·"])
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

    /// Fan out a fresh fetch across every account concurrently. Each account's
    /// result is applied as it lands (so fast accounts show first), and one
    /// account's failure is recorded without disturbing the others.
    func reload() async {
        let mergeable = accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }
        guard !mergeable.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        // Build the clients on the main actor; each is Sendable, so the concurrent
        // children below can hold one without crossing isolation to build it.
        let targets = mergeable.map { (id: $0.id, client: $0.makeClient()) }
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
                    padsByAccount[id] = pads
                    accountErrors[id] = nil
                    cache.set(id, pads: pads)
                } else {
                    accountErrors[id] = errorText
                }
                publishRoutes()
                isLoading = false
            }
        }
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
        for (accountID, pads) in padsByAccount where pads.contains(where: { $0.id == id }) {
            padsByAccount[accountID] = pads.filter { $0.id != id }
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
        if BrowserSettings.openLinksIn == .external {
            BrowserSettings.openExternally(url)
        } else {
            openWindow(id: "pad-browser", value: url)
        }
    }

    func deletePad(_ pad: Pad) async {
        let client = (router.account(forPadID: pad.id) ?? accounts.currentAccount)?.makeClient()
        guard let client else { return }
        do {
            try await client.deletePad(id: pad.id)
            NotificationCenter.default.post(name: .padDeleted, object: pad.id)
        } catch {
            deleteError = error.localizedDescription
        }
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Bulk

    var bulkConfirmTitle: String {
        switch bulkAction {
        case .endStarted: "End \(PadListLogic.startedPads(in: filtered.map(\.item)).count) started pads?"
        case .makePrivate: "Make \(PadListLogic.nonPrivatePads(in: filtered.map(\.item)).count) pads private?"
        case nil: ""
        }
    }

    func bulkConfirmButton(_ action: BulkPadAction) -> String {
        switch action {
        case .endStarted: "End Started Pads"
        case .makePrivate: "Make Private"
        }
    }

    func bulkConfirmMessage(_ action: BulkPadAction) -> String {
        switch action {
        case .endStarted:
            "This ends every started pad currently shown in the list, across all accounts. "
                + "Ending an interview can't be undone."
        case .makePrivate:
            "This marks every pad currently shown in the list as private, across all accounts."
        }
    }

    /// Run a bulk action over the visible pads, routing each pad to its own
    /// account's client, then refresh. Failures are counted, not fatal.
    func performBulk(_ action: BulkPadAction) async {
        let rows: [AccountScoped<Pad>] = switch action {
        case .endStarted: filtered.filter { $0.item.status == .active }
        case .makePrivate: filtered.filter { $0.item.isPrivate != true }
        }
        guard !rows.isEmpty else { return }
        isBulkRunning = true
        defer { isBulkRunning = false }
        var failures = 0
        for row in rows {
            let client = row.account.makeClient()
            do {
                switch action {
                case .endStarted: try await client.endPad(id: row.item.id)
                case .makePrivate: _ = try await client.updatePad(PadUpdate(id: row.item.id, isPrivate: true))
                }
            } catch {
                failures += 1
            }
        }
        if failures > 0 {
            bulkError = "\(failures) of \(rows.count) pads couldn't be updated."
        }
        await reload()
    }
}
