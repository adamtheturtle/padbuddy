//
//  PhoneContentView.swift
//  coderpad
//
//  A compact-width iOS shell for the main app. Regular-width iPad/macOS stay in
//  MainSplit; compact iPhone/iPad gets task-first tabs with a NavigationStack per tab.
//

#if os(iOS)
    import SwiftUI

    struct PhoneContentView: View {
        @State var store = AccountsStore.shared
        @State private var nav = AppNavigation.shared
        /// This window's published navigation state (injected by `ContentView`), the
        /// home of the per-scene Screen campaign selection (#888).
        @Environment(WindowNavigation.self) private var windowNav
        @State private var network = NetworkMonitor.shared
        @Environment(\.openAppSettings) var openSettings
        let directory: OrgDirectory
        let monitor: AccountHealthMonitor

        @State private var padSelection: Pad?
        @State private var questionSelection: Question?
        @State private var padPath: [PhoneRoute] = []
        @State private var questionPath: [PhoneRoute] = []
        @State private var screenPath: [PhoneRoute] = []
        @State private var padSearch = ""
        @State private var questionSearch = ""
        @State private var screenSearch = ""

        var body: some View {
            VStack(spacing: 0) {
                navigationStatusBanner(store: store, network: network, monitor: monitor)
                TabView(selection: $nav.section) {
                    padsTab
                    questionsTab
                    organizationTab

                    if AppSection.navigable.contains(.quota) {
                        quotaTab
                    }

                    if AppSection.navigable.contains(.screen) {
                        screenTab
                    }
                }
            }
            .task(id: NavigationSessionKey(accountID: store.currentAccountID, merged: store.isMergedView)) {
                nav.section = NavigationSessionLoader.availableSection(from: nav.section)
                await NavigationSessionLoader.load(
                    store: store,
                    directory: directory,
                    monitor: monitor,
                    active: nav.section
                )
            }
            .onChange(of: nav.section) { _, section in
                let available = NavigationSessionLoader.availableSection(from: section)
                nav.section = available
                Task {
                    await NavigationSessionLoader.warmInactiveSections(store: store, active: available)
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
            // removed - or the tab disappears from the TabView while `nav.section`
            // still points at it, leaving a blank selection (#1006). Mirrors the
            // regular-width sidebar's handlers.
            .onChange(of: quotaIsUnlimited) { _, unlimited in
                if unlimited, nav.section == .quota { nav.section = .pads }
            }
            .onChange(of: screenSectionAvailable) { _, available in
                if !available, nav.section == .screen { nav.section = .pads }
            }
        }

        /// Whether the current account's plan is unlimited (no Quota tab), read from
        /// the quota cache exactly like `Sidebar.quotaIsUnlimited`; reading it in
        /// `body` (via `onChange`) also makes the cache observable here, so the tab
        /// set re-evaluates when the session load reveals an unlimited plan.
        private var quotaIsUnlimited: Bool {
            guard !store.isMergedView, let id = store.currentAccountID else { return false }

            return QuotaCacheStore.shared.get(id)?.unlimited == true
        }

        /// Whether the Screen tab should appear, mirroring `Sidebar.screenSectionAvailable`.
        private var screenSectionAvailable: Bool {
            if store.isMergedView {
                return store.mergeableAccounts.contains { $0.makeScreenClient() != nil }
            }
            return store.currentAccount?.makeScreenClient() != nil
        }

        private func clearNavigationState() {
            padSelection = nil
            questionSelection = nil
            padPath = []
            questionPath = []
            screenPath = []
            windowNav.screenCampaignSelection = nil
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
                if path.isEmpty { padSelection = nil }
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
                if path.isEmpty { questionSelection = nil }
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
                .phoneAccountToolbar(accountMenu)
                .searchable(
                    text: $screenSearch,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search campaigns")
                )
                .navigationDestination(for: PhoneRoute.self) { routeDestination($0) }
            }
            .tabItem { Label(AppSection.screen.shortLabel, systemImage: AppSection.screen.systemImage) }
            .tag(AppSection.screen)
            // The campaigns list publishes its selection for a split-view detail column
            // that doesn't exist in the compact shell; mirror it into this tab's path so
            // a selected campaign pushes its test sessions (#837).
            .onChange(of: windowNav.screenCampaignSelection) { _, selection in
                syncScreenPath(with: selection)
            }
            .onChange(of: screenPath) { _, path in
                if path.isEmpty { windowNav.screenCampaignSelection = nil }
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
                .phoneAccountToolbar(accountMenu)

            case .question:
                SectionDetail(
                    section: .questions,
                    padSelection: $padSelection,
                    questionSelection: $questionSelection,
                    screenSearch: $screenSearch
                )
                .navigationTitle(questionSelection?.displayTitle ?? "Question")
                .navigationBarTitleDisplayMode(.inline)
                .phoneAccountToolbar(accountMenu)

            case .screenCampaign:
                SectionDetail(
                    section: .screen,
                    padSelection: $padSelection,
                    questionSelection: $questionSelection,
                    screenSearch: $screenSearch
                )
                .navigationTitle(windowNav.screenCampaignSelection?.name ?? String(localized: "Campaign"))
                .navigationBarTitleDisplayMode(.inline)
                .phoneAccountToolbar(accountMenu)
            }
        }
    }

    private extension PhoneContentView {
        private func syncPadPath(with selection: Pad?) {
            guard let selection else {
                padPath = []
                return
            }

            let route = PhoneRoute.pad(selection.id)
            if padPath.last != route { padPath = [route] }
        }

        private func syncQuestionPath(with selection: Question?) {
            guard let selection else {
                questionPath = []
                return
            }

            let route = PhoneRoute.question(selection.id)
            if questionPath.last != route { questionPath = [route] }
        }

        private func syncScreenPath(with selection: ScreenCampaign?) {
            guard let selection else {
                screenPath = []
                return
            }

            let route = PhoneRoute.screenCampaign(selection.id)
            if screenPath.last != route { screenPath = [route] }
        }
    }

    private enum PhoneRoute: Hashable {
        case pad(String)
        case question(Int)
        case screenCampaign(Int)
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
