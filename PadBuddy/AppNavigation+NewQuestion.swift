import Foundation

extension AppNavigation {
    @MainActor
    func routeNewQuestion() {
        let store = AccountsStore.shared
        guard let target = AppCreationAvailability.creationAccount(
            accounts: store.accounts, currentAccountID: store.currentAccountID, isMergedView: store.isMergedView,
            requestedAccountID: nil, isOffline: NetworkMonitor.shared.isOffline
        ) else {
            unsupportedDeepLink = UUID()
            return
        }

        store.currentAccountID = target.id
        showQuestions(QuestionsRequest(startCreating: true))
    }
}
