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
    @Binding var screenSearch: String

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

            case .quota: QuotaView(client: client, accountID: account.id).id(account.id)

            // The Screen row only shows when a Screen client exists (#432), but guard
            // anyway; the campaigns list is the content column (#433).
            case .screen:
                if let screen = account.makeScreenClient() {
                    ScreenCampaignsView(client: screen, search: $screenSearch).id(account.id)
                } else {
                    ScreenSectionPlaceholder()
                }
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
        // the view as before.
        mergedSection
            .id("merged-\(section.rawValue)")
    }

    /// The section branches, each erased to `AnyView` via a per-branch property. Building
    /// all five view initializers - several taking `@Binding` projections - in one switch
    /// expression tips this getter over the type-checker's 250ms budget on the iOS SDK, and
    /// warnings-as-errors turns that overrun into a build failure. Splitting each branch out
    /// so no single expression type-checks more than one initializer keeps every piece well
    /// under the limit. The `AnyView` cost is negligible: this container is rebuilt only when
    /// the user switches sections.
    private var mergedSection: AnyView {
        switch section {
        case .pads: mergedPads
        case .questions: mergedQuestions
        case .organization: AnyView(MergedOrganizationView())
        case .quota: AnyView(MergedQuotaView())
        // Campaigns aggregated across every Screen-enabled account (#442); the row
        // only appears when at least one mergeable account has a Screen key.
        case .screen: mergedScreen
        }
    }

    private var mergedPads: AnyView {
        AnyView(MergedPadsView(selection: $padSelection, search: $padSearch))
    }

    private var mergedQuestions: AnyView {
        AnyView(MergedQuestionsView(selection: $questionSelection, search: $questionSearch))
    }

    private var mergedScreen: AnyView {
        AnyView(MergedScreenView(search: $screenSearch))
    }
}

struct SectionDetail: View {
    @State private var store = AccountsStore.shared
    /// This window's merged routing and published navigation state (injected by
    /// `ContentView`), so the detail pane follows its own window's selections rather
    /// than whichever window published last (#888, #911).
    @Environment(MergedRouting.self) private var router
    @Environment(WindowNavigation.self) private var windowNav
    let section: AppSection
    @Binding var padSelection: Pad?
    @Binding var questionSelection: Question?
    @Binding var screenSearch: String

    var body: some View {
        switch section {
        case .pads:
            if let pad = padSelection {
                if let client = padClient(for: pad) {
                    PadDetailView(client: client, pad: pad)
                        .advertisesPadActivity(url: pad.webURL, title: pad.title)
                        .id(padDetailID(for: pad))
                } else {
                    unresolvedRoutePlaceholder(systemImage: "doc.text")
                }
            } else {
                ContentUnavailableView("Select a pad", systemImage: "doc.text")
            }

        case .questions:
            if let question = questionSelection {
                if let account = questionAccount(for: question) {
                    QuestionDetailView(client: account.makeClient(), question: question, accountID: account.id)
                        .id(questionDetailID(for: question))
                } else {
                    unresolvedRoutePlaceholder(systemImage: "questionmark.bubble")
                }
            } else {
                ContentUnavailableView("Select a question", systemImage: "questionmark.bubble")
            }

        case .organization, .quota:
            ContentUnavailableView("Nothing selected", systemImage: "sidebar.squares.leading",
                                   description: Text("This section shows everything in the list."))

        case .screen:
            // The selected campaign's test sessions fill the detail column (#448); a
            // session's report opens in its own window on double-click (#474). When no
            // campaign is selected, prompt to pick one.
            if let campaign = windowNav.screenCampaignSelection, let screen = screenClient {
                ScreenTestsView(client: screen, campaign: campaign, search: $screenSearch,
                                accountID: store.isMergedView ? router.selectedScreenAccountID : nil)
                    .id(screenTestsID(for: campaign))
            } else {
                ScreenDetailPlaceholder()
            }
        }
    }

    /// The Screen client for the selected test's report: in the combined view, the
    /// account whose campaign is drilled into (routed via `MergedRouting`, since
    /// campaign/test ids are per-org); otherwise the single current account (#442).
    private var screenClient: ScreenClient? {
        if store.isMergedView {
            return router.selectedScreenAccountID
                .flatMap { id in store.accounts.first { $0.id == id } }?
                .makeScreenClient()
        }
        return store.currentAccount?.makeScreenClient()
    }

    /// The Screen tests-list identity, namespaced by the routed account in the combined
    /// view so switching between two accounts' campaigns that share a per-org id
    /// recreates the detail pane (and re-fetches) instead of reusing stale state
    /// (mirrors `questionDetailID`).
    private func screenTestsID(for campaign: ScreenCampaign) -> String {
        if store.isMergedView, let account = router.selectedScreenAccountID {
            return "\(account.uuidString):\(campaign.id)"
        }
        return String(campaign.id)
    }

    /// Shown when a merged selection's source account can't be resolved. Never
    /// guess an account instead: the detail is fully actionable, question ids are
    /// per-org, and pad credentials are account-specific, so a guessed first
    /// account could edit or delete an unrelated item in the wrong org (#912).
    /// Routes rebuild as the merged list publishes, so reselecting recovers.
    private func unresolvedRoutePlaceholder(systemImage: String) -> some View {
        ContentUnavailableView {
            Label("Account Unavailable", systemImage: systemImage)
        } description: {
            Text("The account this item belongs to couldn't be determined. Select it in the list again.")
        }
    }

    /// The client a selected pad's detail should use. Pad slugs are only unique per
    /// server, so two custom servers can share one; in the combined view prefer the
    /// account the list published for the *selected* pad, then the (collision-prone)
    /// route map (#758). Never falls back to an arbitrary account (#912).
    private func padClient(for pad: Pad) -> CoderPadClient? {
        if store.isMergedView {
            let account = router.selectedPadAccountID.flatMap { id in store.accounts.first { $0.id == id } }
                ?? router.account(forPadID: pad.id)
            return account?.makeClient()
        }
        return store.currentAccount?.makeClient()
    }

    /// The pad detail view's identity. Namespaced by the selected account in the
    /// combined view so switching between two accounts' pads that share a slug
    /// (possible across custom servers, #758) recreates the detail pane instead of
    /// reusing stale state - the pad counterpart to `questionDetailID`.
    private func padDetailID(for pad: Pad) -> String {
        if store.isMergedView, let account = router.selectedPadAccountID {
            return "\(account.uuidString):\(pad.id)"
        }
        return pad.id
    }

    /// The account a selected question belongs to. Per-org question ids collide
    /// across accounts, so in the combined view prefer the account the list
    /// published for the *selected* question, then the (collision-prone) id map.
    /// Never falls back to an arbitrary account (#912).
    private func questionAccount(for question: Question) -> Account? {
        if store.isMergedView {
            return router.selectedQuestionAccountID.flatMap { id in store.accounts.first { $0.id == id } }
                ?? router.account(forQuestionID: question.id)
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
