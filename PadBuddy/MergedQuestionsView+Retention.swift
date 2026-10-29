import SwiftUI

extension MergedQuestionsView {
    var questionRecordLimit: Int {
        MergedListWindows.questions.recordsPerAccount
    }

    var hasPartialQuestionWindow: Bool {
        !limitedQuestionAccounts.isEmpty
    }

    func retainQuestions(_ values: [Question], account: UUID, isComplete: Bool) {
        let limit = questionRecordLimit
        questionsByAccount[account] = values.count <= limit ? values : Array(values.prefix(limit))
        if !isComplete || values.count > limit {
            limitedQuestionAccounts.insert(account)
        } else {
            limitedQuestionAccounts.remove(account)
        }
    }

    func prepareRetainedQuestions() {
        MergedListWindows.prepareQuestions()
        let clients = Dictionary(accounts.mergeableAccounts.map { ($0.id, $0.makeClient().taskIdentity) },
                                 uniquingKeysWith: { first, _ in first })
        let live = Set(clients.keys)
        questionsByAccount = questionsByAccount.filter { clients[$0.key] == retainedQuestionClients[$0.key] }
        retainedQuestionClients = clients
        limitedQuestionAccounts.formIntersection(live)
        for (id, values) in questionsByAccount {
            retainQuestions(values, account: id, isComplete: !limitedQuestionAccounts.contains(id))
        }
        questionsRevision += 1
    }

    func resolveRetainedQuestionSelection(loadComplete: Bool = false) {
        guard let request = pendingRetainedQuestion else { return }
        guard let account = accounts.mergeableAccounts.first(where: { $0.id == request.account }),
              request.clientIdentity == nil || request.clientIdentity == account.makeClient().taskIdentity else {
            pendingRetainedQuestion = nil
            return
        }

        refreshScoped()
        let rowID = Self.rowID(account: request.account, question: request.id)
        if row(forRowID: rowID) != nil {
            selectedRowIDs = [rowID]
            pendingScrollToRowID = rowID
        } else if limitedQuestionAccounts.contains(request.account) {
            let target = QuestionWindowID(account: request.account, id: request.id)
            if target.isValid {
                openWindow(id: "question", value: target)
            }
        } else if !loadComplete {
            return
        }
        pendingRetainedQuestion = nil
    }
}
