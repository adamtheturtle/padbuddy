//
//  CommandPalette+Activation.swift
//  coderpad
//

import Foundation

@MainActor private var commandPaletteActivationsInFlight: Set<String> = []

@MainActor
extension CommandPaletteBuilder {
    static func activatePad(
        _ id: String, in account: UUID, clientIdentity: ClientTaskIdentity
    ) {
        let key = "pad:\(account.uuidString):\(id)"
        guard let target = currentAccount(account, identity: clientIdentity),
              commandPaletteActivationsInFlight.insert(key).inserted else { return }

        let client = target.makeClient()
        Task { @MainActor in
            defer { commandPaletteActivationsInFlight.remove(key) }
            do {
                let pad = try await client.getPad(id: id)
                guard currentAccount(account, identity: clientIdentity) != nil else { return }
                guard pad.id == id else {
                    PadsCacheStore.shared.removePad(id: id, account: account, via: clientIdentity)
                    return
                }

                PadsCacheStore.shared.updatePad(pad, account: account, via: client)
                routePad(id, in: account, clientIdentity: clientIdentity)
            } catch {
                guard Self.isMissingRecord(error),
                      currentAccount(account, identity: clientIdentity) != nil else { return }

                PadsCacheStore.shared.removePad(id: id, account: account, via: clientIdentity)
            }
        }
    }

    private static func routePad(
        _ id: String, in account: UUID, clientIdentity: ClientTaskIdentity
    ) {
        guard currentAccount(account, identity: clientIdentity) != nil else { return }

        if AccountsStore.shared.isMergedView {
            AppNavigation.shared.sectionRequest = .pads
            AppNavigation.shared.selectMergedFavoritePad(
                account: account, id: id, clientIdentity: clientIdentity
            )
            return
        }
        if AccountsStore.shared.currentAccountID != account {
            AccountsStore.shared.currentAccountID = account
        }
        AppNavigation.shared.showPads(PadsRequest(
            selectPadID: id, selectPadAccountID: account, selectPadClientIdentity: clientIdentity
        ))
    }

    static func activateQuestion(
        _ id: Int, in account: UUID, clientIdentity: ClientTaskIdentity
    ) {
        let key = "question:\(account.uuidString):\(id)"
        guard let target = currentAccount(account, identity: clientIdentity),
              commandPaletteActivationsInFlight.insert(key).inserted else { return }

        let client = target.makeClient()
        Task { @MainActor in
            defer { commandPaletteActivationsInFlight.remove(key) }
            do {
                let question = try await client.getQuestion(id: id)
                guard currentAccount(account, identity: clientIdentity) != nil else { return }
                guard question.id == id else {
                    QuestionsCacheStore.shared.removeQuestion(
                        id: id, account: account, via: clientIdentity
                    )
                    return
                }

                QuestionsCacheStore.shared.updateQuestion(question, account: account, via: client)
                AppNavigation.shared.showQuestion(
                    id: id, account: account, clientIdentity: clientIdentity
                )
            } catch {
                guard Self.isMissingRecord(error),
                      currentAccount(account, identity: clientIdentity) != nil else { return }

                QuestionsCacheStore.shared.removeQuestion(
                    id: id, account: account, via: clientIdentity
                )
            }
        }
    }

    private static func currentAccount(
        _ id: UUID, identity: ClientTaskIdentity
    ) -> Account? {
        AccountsStore.shared.accounts.first {
            $0.id == id && $0.makeClient().taskIdentity == identity
        }
    }

    nonisolated static func isMissingRecord(_ error: any Error) -> Bool {
        guard case let CoderPadError.http(status, _) = error else { return false }

        return status == 404 || status == 410
    }
}
