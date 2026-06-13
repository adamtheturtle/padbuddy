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
            }
        }
    }

    /// The combined-view content. Pads and Questions merge across accounts;
    /// Organization and Quota stay inherently per-account, so they show the first
    /// real account (the merged view is about the lists, not these single-org
    /// sections).
    @ViewBuilder
    private var mergedContent: some View {
        switch section {
        case .pads:
            MergedPadsView(selection: $padSelection, search: $padSearch).id("merged-pads")
        case .questions:
            MergedQuestionsView(selection: $questionSelection, search: $questionSearch).id("merged-questions")
        case .organization:
            if let account = store.mergeableAccounts.first {
                OrganizationView(client: account.makeClient()).id(account.id)
            }
        case .quota:
            if let account = store.mergeableAccounts.first {
                QuotaView(client: account.makeClient()).id(account.id)
            }
        }
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
            if let question = questionSelection, let client = questionClient(for: question) {
                QuestionDetailView(client: client, question: question).id(question.id)
            } else {
                ContentUnavailableView("Select a question", systemImage: "questionmark.bubble")
            }
        case .organization, .quota:
            ContentUnavailableView("Nothing selected", systemImage: "sidebar.squares.leading",
                                   description: Text("This section shows everything in the list."))
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

    private func questionClient(for question: Question) -> CoderPadClient? {
        if store.isMergedView {
            return (router.account(forQuestionID: question.id) ?? store.mergeableAccounts.first)?.makeClient()
        }
        return store.currentAccount?.makeClient()
    }
}
