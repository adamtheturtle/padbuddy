import Foundation

/// The pad and credential identity that armed a destructive confirmation.
struct PadMutationTarget {
    let pad: Pad
    let context: AccountClientContext

    init(pad: Pad, client: CoderPadClient, accountID: UUID?) {
        self.pad = pad
        context = AccountClientContext(client: client, targetAccountID: accountID)
    }

    func resolve(padID: String, client: CoderPadClient, accounts: [Account]) -> Account? {
        guard pad.id == padID, client.taskIdentity == context.clientIdentity else { return nil }

        return context.resolve(in: accounts)
    }
}
