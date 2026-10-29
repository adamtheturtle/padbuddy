import SwiftUI

extension MergedPadsView {
    var padRecordLimit: Int {
        MergedListWindows.pads.recordsPerAccount
    }

    var hasPartialPadWindow: Bool {
        !limitedPadAccounts.isEmpty
    }

    func retainPads(_ values: [Pad], account: UUID, isComplete: Bool) {
        let limit = padRecordLimit
        padsByAccount[account] = values.count <= limit ? values : Array(values.prefix(limit))
        if !isComplete || values.count > limit {
            limitedPadAccounts.insert(account)
        } else {
            limitedPadAccounts.remove(account)
        }
    }

    func prepareRetainedPads() {
        MergedListWindows.preparePads()
        let clients = Dictionary(accounts.mergeableAccounts.map { ($0.id, $0.makeClient().taskIdentity) },
                                 uniquingKeysWith: { first, _ in first })
        let live = Set(clients.keys)
        padsByAccount = padsByAccount.filter { clients[$0.key] == retainedPadClients[$0.key] }
        retainedPadClients = clients
        limitedPadAccounts.formIntersection(live)
        for (id, values) in padsByAccount {
            retainPads(values, account: id, isComplete: !limitedPadAccounts.contains(id))
        }
        padsRevision += 1
    }

    func openPadOutsideRetainedWindow(id: String, account: UUID) {
        guard accounts.mergeableAccounts.contains(where: { $0.id == account }) else { return }

        let target = PadWindowID(account: account, id: id)
        guard target.isValid else { return }

        PadOpenedStore.shared.record(id, account: account)
        openWindow(id: "pad", value: target)
    }

    /// Explicit owners can use targeted detail loading. Partial windows cannot prove bare-ID uniqueness.
    func selectRequestedPad(id: String, owner: UUID?) {
        pendingSelectPadSlug = nil
        pendingSelectPadAccountID = nil
        guard owner != nil || !hasPartialPadWindow else { return }

        let matches = scoped.filter { $0.item.id == id && (owner == nil || $0.account.id == owner) }
        if let row = matches.first, owner != nil || matches.count == 1 {
            selectedIDs = [row.id]
            pendingScrollToID = row.id
        } else if matches.isEmpty {
            if let owner, limitedPadAccounts.contains(owner) {
                openPadOutsideRetainedWindow(id: id, account: owner)
            } else {
                pendingSelectPadSlug = id
                pendingSelectPadAccountID = owner
            }
        }
    }
}
