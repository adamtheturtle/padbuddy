//
//  ContentView+Sections.swift
//  coderpad
//
//  The content and detail columns of the main split. Each resolves the right
//  view for the active section, branching between the single-account views and
//  the combined "All Accounts" views (and, in the detail, routing the selected
//  pad/question to its source account's client via `MergedRouting`).
//

import SwiftUI

struct SectionContent: View {
    @State private var store = AccountsStore.shared
    let section: AppSection
    @Binding var padSelection: Pad?
    @Binding var questionSelection: Question?
    @Binding var padSearch: String
    @Binding var questionSearch: String

    var body: some View {
        if store.isMergedView {
            mergedContent
        } else if let account = store.currentAccount {
            let client = account.makeClient()
            switch section {
            case .pads:
                PadsView(client: client, selection: $padSelection, search: $padSearch).id(account.id)

            case .questions:
                QuestionsView(client: client, selection: $questionSelection, search: $questionSearch)
                    .id(account.id)

            case .organization: OrganizationView(client: client).id(account.id)

            case .quota: QuotaView(client: client).id(account.id)

            // Phase 1 scaffolding (#432): list/detail content lands in #433+.
            case .screen: ScreenSectionPlaceholder().id(account.id)
            }
        }
    }

    /// The combined-view content. Every section merges across accounts: Pads and
    /// Questions into one list; Organization into an aggregate-plus-breakdown
    /// overview; and Quota into a per-account stack (quota numbers are per-org, so
    /// they're shown side by side rather than summed).
    private var mergedContent: some View {
        // One `.id()` on the whole switch rather than per case: each section still gets a
        // distinct, stable identity ("merged-<section>"), so switching sections recreates
        // the view as before — but the four branches no longer each carry a modifier,
        // which keeps this getter's type-check comfortably under the limit.
        Group {
            switch section {
            case .pads:
                MergedPadsView(selection: $padSelection, search: $padSearch)
            case .questions:
                MergedQuestionsView(selection: $questionSelection, search: $questionSearch)
            case .organization:
                MergedOrganizationView()
            case .quota:
                MergedQuotaView()
            // Screen is per-account only for now (#432), so it's excluded from the
            // combined view — its row never appears there, but the switch is exhaustive.
            case .screen:
                EmptyView()
            }
        }
        .id("merged-\(section.rawValue)")
    }
}

struct SectionDetail: View {
    @State private var store = AccountsStore.shared
    @State private var router = MergedRouting.shared
    let section: AppSection
    @Binding var padSelection: Pad?
    @Binding var questionSelection: Question?

    var body: some View {
        switch section {
        case .pads:
            if let pad = padSelection, let client = padClient(for: pad) {
                PadDetailView(client: client, pad: pad).id(pad.id)
            } else {
                ContentUnavailableView("Select a pad", systemImage: "doc.text")
            }

        case .questions:
            if let question = questionSelection, let account = questionAccount(for: question) {
                QuestionDetailView(client: account.makeClient(), question: question, accountID: account.id)
                    .id(questionDetailID(for: question))
            } else {
                ContentUnavailableView("Select a question", systemImage: "questionmark.bubble")
            }

        case .organization, .quota:
            ContentUnavailableView("Nothing selected", systemImage: "sidebar.squares.leading",
                                   description: Text("This section shows everything in the list."))

        case .screen:
            ScreenDetailPlaceholder()
        }
    }

    /// The client a selected pad's detail should use: in the combined view, the
    /// account that pad came from (resolved through `MergedRouting`); otherwise the
    /// single current account.
    private func padClient(for pad: Pad) -> CoderPadClient? {
        if store.isMergedView {
            return (router.account(forPadID: pad.id) ?? store.mergeableAccounts.first)?.makeClient()
        }
        return store.currentAccount?.makeClient()
    }

    /// The account a selected question belongs to. Per-org question ids collide
    /// across accounts, so in the combined view prefer the account the list
    /// published for the *selected* question; fall back to the (collision-prone)
    /// id map, then the first merged account.
    private func questionAccount(for question: Question) -> Account? {
        if store.isMergedView {
            return router.selectedQuestionAccountID.flatMap { id in store.accounts.first { $0.id == id } }
                ?? router.account(forQuestionID: question.id)
                ?? store.mergeableAccounts.first
        }
        return store.currentAccount
    }

    /// The detail view's identity. Namespaced by the selected account in the
    /// combined view so switching between two accounts' questions that share a
    /// per-org id recreates the detail pane instead of reusing stale state.
    private func questionDetailID(for question: Question) -> String {
        if store.isMergedView, let account = router.selectedQuestionAccountID {
            return "\(account.uuidString):\(question.id)"
        }
        return String(question.id)
    }
}
