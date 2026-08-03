//
//  PhoneContentView.swift
//  coderpad
//
//  A compact-width iOS shell for the main app. Regular-width iPad/macOS stay in
//  MainSplit; compact iPhone/iPad gets task-first tabs with a NavigationStack per tab.
//

#if os(iOS)
    import SwiftUI

    struct PhoneContentView: View { // swiftlint:disable:this type_body_length
        @State var store = AccountsStore.shared
        /// This window's published navigation state (injected by `ContentView`): the
        /// per-scene Screen campaign selection (#888) and visible section (#907).
        @Environment(WindowNavigation.self) var windowNav
        /// The owner of the current merged selection, so a route identifies which
        /// account's pad/question/campaign it is (#2313, #2314, #2319).
        @Environment(MergedRouting.self) var mergedRouting
        @State private var network = NetworkMonitor.shared
        @Environment(\.openAppSettings) var openSettings
        let directory: OrgDirectory
        let monitor: AccountHealthMonitor

        @State var padSelection: Pad?
        @State var questionSelection: Question?
        @State var padPath: [PhoneRoute] = []
        @State var questionPath: [PhoneRoute] = []
        @State var screenPath: [PhoneRoute] = []
        /// A pending move off Quota, held so a transient reading cancels it (#2247).
        @State private var leaveQuotaTask: Task<Void, Never>?
        /// A pending move off Screen, held so a transient credential dip cancels it
        /// (#2252).
        @State private var leaveScreenTask: Task<Void, Never>?
        @State var padSearch = ""
        @State var questionSearch = ""
        @State var screenSearch = ""

        var body: some View {
            // The visible section is this window's own (#907); the shared
            // AppNavigation keeps only the request mailbox.
            @Bindable var windowNav = windowNav
            return VStack(spacing: 0) {
                navigationStatusBanner(store: store, network: network, monitor: monitor,
                                       section: windowNav.section)
                TabView(selection: $windowNav.section) {
                    padsTab
                    questionsTab
                    organizationTab

                    if !quotaIsUnlimited {
                        quotaTab
                    }

                    if screenSectionAvailable {
                        screenTab
                    }
                }
            }
            .task(id: NavigationSessionKey(accountID: store.currentAccountID, merged: store.isMergedView)) {
                windowNav.section = NavigationSessionLoader.availableSection(from: windowNav.section)
                await NavigationSessionLoader.load(
                    store: store,
                    directory: directory,
                    monitor: monitor,
                    active: windowNav.section
                )
            }
            .onChange(of: windowNav.section) { _, section in
                let available = NavigationSessionLoader.availableSection(from: section)
                windowNav.section = available
                Task {
                    await NavigationSessionLoader.warmInactiveSections(
                        store: store,
                        active: available,
                        warmQuota: !quotaIsUnlimited
                    )
                }
            }
            // Switching accounts (or into/out of All Accounts) swaps every tab's
            // data source, so pop each tab's pushed detail and drop its selection:
            // a route left on the stack kept showing the previous account's pad or
            // question over the new account's list (#698). MainSplit clears its
            // selections the same way.
            .onChange(of: store.currentAccountID) { _, _ in clearNavigationState() }
            .onChange(of: store.isMergedView) { _, _ in clearNavigationState() }
            // Step away when the active section becomes unavailable for the *same*
            // account - quota resolving to unlimited, or the Screen key being
            // removed - or the tab disappears from the TabView while the section
            // still points at it, leaving a blank selection (#1006). Mirrors the
            // regular-width sidebar's handlers.
            // Settled before moving the user, so a stale cache answer doesn't take the
            // quota page away for a condition that resolves a moment later (#2247).
            .onChange(of: quotaIsUnlimited) { _, unlimited in
                leaveQuotaTask?.cancel()
                guard unlimited, windowNav.section == .quota else {
                    leaveQuotaTask = nil
                    return
                }

                leaveQuotaTask = Task { @MainActor in
                    try? await Task.sleep(for: SectionAvailabilitySettling.grace)
                    guard !Task.isCancelled, quotaIsUnlimited, windowNav.section == .quota else { return }

                    windowNav.section = .pads
                }
            }
            // Settled before discarding anything: Screen availability depends on a
            // keychain read that can dip during an account refresh, and reacting to the
            // first false reading threw away the user's drill-down for a condition that
            // resolved a moment later (#2252).
            .onChange(of: screenSectionAvailable) { _, available in
                leaveScreenTask?.cancel()
                guard !available else {
                    leaveScreenTask = nil
                    return
                }

                leaveScreenTask = Task { @MainActor in
                    try? await Task.sleep(for: SectionAvailabilitySettling.grace)
                    guard !Task.isCancelled, !screenSectionAvailable else { return }

                    if windowNav.section == .screen {
                        windowNav.section = .pads
                    }
                    // Drop the Screen stack and selection too: left intact, re-enabling
                    // Screen reopened a stale campaign from the previous configuration
                    // (#1669).
                    screenPath = []
                    windowNav.publishScreenCampaign(nil, accountID: nil)
                    windowNav.screenTestsSubtitle = ""
                    windowNav.screenTestsSubtitleOwner = nil
                }
            }
            .onDisappear {
                leaveQuotaTask?.cancel()
                leaveScreenTask?.cancel()
                leaveQuotaTask = nil
                leaveScreenTask = nil
            }
        }

        private var padsTab: some View {
            NavigationStack(path: $padPath) {
                SectionContent(
                    section: .pads,
                    padSelection: $padSelection,
                    questionSelection: $questionSelection,
                    padSearch: $padSearch,
                    questionSearch: $questionSearch,
                    screenSearch: $screenSearch
                )
                .navigationTitle("Pads")
                .toolbarTitleDisplayMode(.large)
                .phoneAccountToolbar(accountMenu)
                .searchable(
                    text: $padSearch,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search pads")
                )
                .navigationDestination(for: PhoneRoute.self) { routeDestination($0) }
            }
            .tabItem { Label(AppSection.pads.shortLabel, systemImage: AppSection.pads.systemImage) }
            .tag(AppSection.pads)
            .onChange(of: padSelection) { _, selection in
                syncPadPath(with: selection)
            }
            .onChange(of: padPath) { _, path in
                if path.isEmpty {
                    padSelection = nil
                }
            }
        }

        private var questionsTab: some View {
            NavigationStack(path: $questionPath) {
                SectionContent(
                    section: .questions,
                    padSelection: $padSelection,
                    questionSelection: $questionSelection,
                    padSearch: $padSearch,
                    questionSearch: $questionSearch,
                    screenSearch: $screenSearch
                )
                .navigationTitle("Questions")
                .toolbarTitleDisplayMode(.large)
                .phoneAccountToolbar(accountMenu)
                .searchable(
                    text: $questionSearch,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search questions")
                )
                .navigationDestination(for: PhoneRoute.self) { routeDestination($0) }
            }
            .tabItem { Label(AppSection.questions.shortLabel, systemImage: AppSection.questions.systemImage) }
            .tag(AppSection.questions)
            .onChange(of: questionSelection) { _, selection in
                syncQuestionPath(with: selection)
            }
            .onChange(of: questionPath) { _, path in
                if path.isEmpty {
                    questionSelection = nil
                }
            }
        }

        private var organizationTab: some View {
            NavigationStack {
                SectionContent(
                    section: .organization,
                    padSelection: $padSelection,
                    questionSelection: $questionSelection,
                    padSearch: $padSearch,
                    questionSearch: $questionSearch,
                    screenSearch: $screenSearch
                )
                .navigationTitle("Organization")
                .toolbarTitleDisplayMode(.large)
                .phoneAccountToolbar(accountMenu)
            }
            .tabItem { Label(AppSection.organization.shortLabel, systemImage: AppSection.organization.systemImage) }
            .tag(AppSection.organization)
        }

        private var quotaTab: some View {
            NavigationStack {
                SectionContent(
                    section: .quota,
                    padSelection: $padSelection,
                    questionSelection: $questionSelection,
                    padSearch: $padSearch,
                    questionSearch: $questionSearch,
                    screenSearch: $screenSearch
                )
                .navigationTitle("Quota")
                .toolbarTitleDisplayMode(.large)
                .phoneAccountToolbar(accountMenu)
            }
            .tabItem { Label(AppSection.quota.shortLabel, systemImage: AppSection.quota.systemImage) }
            .tag(AppSection.quota)
        }

        private var screenTab: some View {
            NavigationStack(path: $screenPath) {
                SectionContent(
                    section: .screen,
                    padSelection: $padSelection,
                    questionSelection: $questionSelection,
                    padSearch: $padSearch,
                    questionSearch: $questionSearch,
                    screenSearch: $screenSearch
                )
                .navigationTitle("Screen")
                .toolbarTitleDisplayMode(.large)
                .phoneAccountToolbar(accountMenu)
                .searchable(
                    text: $screenSearch,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    // Once a campaign is pushed the same field filters its
                    // candidates, so the prompt must say so (#1667).
                    prompt: screenPath.isEmpty ? Text("Search campaigns") : Text("Search candidates")
                )
                .navigationDestination(for: PhoneRoute.self) { routeDestination($0) }
            }
            .tabItem { Label(AppSection.screen.shortLabel, systemImage: AppSection.screen.systemImage) }
            .tag(AppSection.screen)
            // The campaigns list publishes its selection for a split-view detail column
            // that doesn't exist in the compact shell; mirror it into this tab's path so
            // a selected campaign pushes its test sessions (#837). Only while Screen is
            // the active tab: every tab stays constructed, and a background update
            // pushing this stack surprised users with an already-pushed detail on their
            // next visit (#1687). Activating the tab reconciles the path below.
            .onChange(of: windowNav.screenCampaignSelection) { _, _ in
                guard windowNav.section == .screen else { return }

                syncScreenPath(with: windowNav.screenCampaign(for: screenSelectionAccountID))
            }
            .onChange(of: windowNav.section) { _, section in
                guard section == .screen else { return }

                syncScreenPath(with: windowNav.screenCampaign(for: screenSelectionAccountID))
            }
            .onChange(of: screenPath) { _, path in
                if path.isEmpty {
                    windowNav.publishScreenCampaign(nil, accountID: nil)
                }
            }
        }

        @ViewBuilder
        private func routeDestination(_ route: PhoneRoute) -> some View {
            switch route {
            case .pad:
                SectionDetail(
                    section: .pads,
                    padSelection: $padSelection,
                    questionSelection: $questionSelection,
                    screenSearch: $screenSearch
                )
                .navigationTitle(padSelection?.title.isEmpty == false ? padSelection?.title ?? "Pad" : "Pad")
                .navigationBarTitleDisplayMode(.inline)

            case .question:
                SectionDetail(
                    section: .questions,
                    padSelection: $padSelection,
                    questionSelection: $questionSelection,
                    screenSearch: $screenSearch
                )
                .navigationTitle(questionSelection?.displayTitle ?? "Question")
                .navigationBarTitleDisplayMode(.inline)

            case .screenCampaign:
                SectionDetail(
                    section: .screen,
                    padSelection: $padSelection,
                    questionSelection: $questionSelection,
                    screenSearch: $screenSearch
                )
                .navigationTitle(
                    windowNav.screenCampaign(for: screenSelectionAccountID)?.name ?? String(localized: "Campaign")
                )
                .navigationBarTitleDisplayMode(.inline)
                .phoneAccountToolbar(accountMenu)
            }
        }
    }

    private extension PhoneContentView {
        /// Which account owns the current selection: in the combined view the merged
        /// router knows, otherwise it is simply the current account.
        private func owningAccountID(_ selected: KeyPath<MergedRouting, UUID?>) -> UUID? {
            store.isMergedView ? mergedRouting[keyPath: selected] : store.currentAccountID
        }

        private func syncPadPath(with selection: Pad?) {
            guard let selection else {
                padPath = []
                return
            }

            let route = PhoneRoute.pad(selection.id, account: owningAccountID(\.selectedPadAccountID))
            if padPath.last != route {
                padPath = [route]
            }
        }

        private func syncQuestionPath(with selection: Question?) {
            guard let selection else {
                questionPath = []
                return
            }

            let route = PhoneRoute.question(selection.id, account: owningAccountID(\.selectedQuestionAccountID))
            if questionPath.last != route {
                questionPath = [route]
            }
        }

        private func syncScreenPath(with selection: ScreenCampaign?) {
            guard let selection else {
                screenPath = []
                return
            }

            let route = PhoneRoute.screenCampaign(selection.id,
                                                  account: owningAccountID(\.selectedScreenAccountID))
            if screenPath.last != route {
                screenPath = [route]
            }
        }
    }

    /// A pushed detail, identified by its item *and* the account that owns it.
    ///
    /// The account used to be omitted. Pad slugs collide across custom servers and
    /// question and campaign ids collide across organizations, so switching a merged
    /// selection to the same id in a different account produced an equal route: the
    /// path never changed, and the pushed view kept the previous account's title and
    /// content (#2313, #2314, #2319).
    enum PhoneRoute: Hashable {
        case pad(String, account: UUID?)
        case question(Int, account: UUID?)
        case screenCampaign(Int, account: UUID?)
    }

    private extension View {
        func phoneAccountToolbar(_ menu: some View) -> some View {
            toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    menu
                }
            }
        }
    }
#endif
