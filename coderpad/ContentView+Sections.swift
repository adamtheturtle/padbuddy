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
    @Environment(\.openAppSettings) private var openSettings
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

            case .organization: OrganizationView(client: client, accountID: account.id).id(account.id)

            case .quota: QuotaView(client: client, accountID: account.id).id(account.id)

            // The Screen row only shows when a Screen client exists (#432), but guard
            // anyway; the campaigns list is the content column (#433).
            case .screen:
                if let screen = account.makeScreenClient() {
                    ScreenCampaignsView(client: screen, accountID: account.id, search: $screenSearch).id(account.id)
                } else {
                    ScreenSectionPlaceholder()
                }
            }
        } else {
            noAccountContent
        }
    }

    private var noAccountContent: some View {
        if store.accounts.isEmpty {
            ContentUnavailableView {
                Label("No accounts configured", systemImage: "person.crop.circle.badge.plus")
            } description: {
                Text("Add a CoderPad account to load this section.")
            } actions: {
                Button("Add Account") { startAddingAccount() }
            }
        } else {
            ContentUnavailableView {
                Label("No account selected", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Choose one of your saved accounts in Settings.")
            } actions: {
                Button("Manage Accounts") { manageAccounts() }
            }
        }
    }

    private func startAddingAccount() {
        SettingsNavigation.shared.selectedTab = .accounts
        SettingsNavigation.shared.startAddingAccount = true
        openSettings()
    }

    private func manageAccounts() {
        SettingsNavigation.shared.selectedTab = .accounts
        openSettings()
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
                if let account = padAccount(for: pad) {
                    let client = account.makeClient()
                    PadDetailView(client: client, pad: pad,
                                  usesMockHistoryTransport: account.isMock)
                        // Resolved against the routed account's server, not `webURL`
                        // alone: a self-hosted pad whose response carries no absolute
                        // URL advertised nothing, so Handoff and continuity silently
                        // did not work for it (#2298).
                        .advertisesPadActivity(url: pad.webURL(fallbackBase: client.baseURL),
                                               title: pad.title)
                        .id(padDetailID(for: pad))
                } else {
                    unresolvedRoutePlaceholder(systemImage: "doc.text") { padSelection = nil }
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
                    unresolvedRoutePlaceholder(systemImage: "questionmark.bubble") { questionSelection = nil }
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
            let campaignAccountID = store.isMergedView ? router.selectedScreenAccountID : store.currentAccountID
            if let campaign = windowNav.screenCampaign(for: campaignAccountID), let screen = screenClient {
                ScreenTestsView(client: screen, campaign: campaign, search: $screenSearch,
                                accountID: store.isMergedView
                                    ? router.selectedScreenAccountID
                                    : store.currentAccountID)
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

    /// The Screen tests-list identity, namespaced by the owning account so switching
    /// between two accounts' campaigns that share a per-org id recreates the detail
    /// pane (and re-fetches) instead of reusing stale state (mirrors
    /// `questionDetailID`).
    ///
    /// Only the combined view was namespaced. Campaign ids are per-org, so switching
    /// between two single accounts whose campaigns happened to share an id kept the
    /// same identity and reused `ScreenTestsView`'s state — showing the previous
    /// account's sessions (#2297).
    private func screenTestsID(for campaign: ScreenCampaign) -> String {
        let account = store.isMergedView ? router.selectedScreenAccountID : store.currentAccountID
        guard let account else { return String(campaign.id) }

        return "\(account.uuidString):\(campaign.id)"
    }

    /// Shown when a merged selection's source account can't be resolved. Never
    /// guess an account instead: the detail is fully actionable, question ids are
    /// per-org, and pad credentials are account-specific, so a guessed first
    /// account could edit or delete an unrelated item in the wrong org (#912).
    /// Routes rebuild as the merged list publishes, so reselecting recovers.
    private func unresolvedRoutePlaceholder(systemImage: String,
                                            clearSelection: @escaping () -> Void) -> some View {
        ContentUnavailableView {
            Label("Account Unavailable", systemImage: systemImage)
        } description: {
            Text("The account this item belongs to could not be determined. Select it in the list again.")
        } actions: {
            // The selection is retained deliberately - routes republish as the merged
            // list loads, so a transient gap resolves itself and clearing would throw
            // away a valid selection mid-load. But when the account really is gone the
            // detail stays on this placeholder with nothing to act on, so there has to
            // be a way out that doesn't require finding the row again (#2299).
            Button("Clear Selection", action: clearSelection)
        }
    }

    /// The account a selected pad's detail should use. Pad slugs are only unique per
    /// server, so two custom servers can share one; in the combined view prefer the
    /// account the list published for the *selected* pad, then the route map (#758).
    /// That map is not a guess: `account(forPadID:)` returns nil unless exactly one
    /// merged account holds the slug (#1215), so an ambiguous slug resolves to the
    /// unavailable placeholder rather than the wrong account. Never falls back to an
    /// arbitrary account (#912).
    private func padAccount(for pad: Pad) -> Account? {
        if store.isMergedView {
            let account = router.selectedPadAccountID.flatMap { id in store.accounts.first { $0.id == id } }
                ?? router.account(forPadID: pad.id)
            return account
        }
        return store.currentAccount
    }

    /// The pad detail view's identity, namespaced by the owning account so switching
    /// between two accounts' pads that share a slug (possible across custom servers,
    /// #758) recreates the detail pane instead of reusing stale state - the pad
    /// counterpart to `questionDetailID`.
    ///
    /// Only the combined view was namespaced. Selections are cleared when the current
    /// account changes, but that runs after the change, and an un-namespaced identity
    /// let the surviving frame pair the old selection with the new account's client
    /// (#2294) - the same gap `screenTestsID` had (#2297).
    private func padDetailID(for pad: Pad) -> String {
        let account = store.isMergedView ? router.selectedPadAccountID : store.currentAccountID
        guard let account else { return pad.id }

        return "\(account.uuidString):\(pad.id)"
    }

    /// The account a selected question belongs to. Per-org question ids collide
    /// across accounts, so in the combined view prefer the account the list
    /// published for the *selected* question, then the id map - which returns nil
    /// unless exactly one merged account holds the id (#1215), so a collision
    /// resolves to the unavailable placeholder rather than the wrong organization.
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
        let account = store.isMergedView ? router.selectedQuestionAccountID : store.currentAccountID
        guard let account else { return String(question.id) }

        return "\(account.uuidString):\(question.id)"
    }
}
