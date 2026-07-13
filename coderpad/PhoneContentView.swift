//
//  PhoneContentView.swift
//  coderpad
//
//  A compact-width iPhone shell for the main app. The Mac/iPad split view stays in
//  MainSplit; phone gets task-first tabs with a NavigationStack per tab.
//

#if os(iOS)
    import SwiftUI

    struct PhoneContentView: View {
        @State private var store = AccountsStore.shared
        @State private var nav = AppNavigation.shared
        @State private var network = NetworkMonitor.shared
        @Environment(\.openAppSettings) private var openSettings
        let directory: OrgDirectory
        let monitor: AccountHealthMonitor

        @State private var padSelection: Pad?
        @State private var questionSelection: Question?
        @State private var padPath: [PhoneRoute] = []
        @State private var questionPath: [PhoneRoute] = []
        @State private var padSearch = ""
        @State private var questionSearch = ""
        @State private var screenSearch = ""

        var body: some View {
            VStack(spacing: 0) {
                if network.isOffline {
                    OfflineBanner()
                } else if !store.isMergedView, let id = store.currentAccountID, monitor.isUnauthorized(id) {
                    UnauthorizedBanner(monitor: monitor)
                }

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
            .task(id: PhoneSessionKey(accountID: store.currentAccountID, merged: store.isMergedView)) {
                await loadSessionContext()
            }
            .onChange(of: nav.section) { _, section in
                guard AppSection.navigable.contains(section) else {
                    nav.section = .pads
                    return
                }
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
                .phoneAccountToolbar(accountMenu)
                .searchable(text: $padSearch, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("Search pads"))
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
                .searchable(text: $questionSearch, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("Search questions"))
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
            NavigationStack {
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
                .searchable(text: $screenSearch, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("Search campaigns"))
            }
            .tabItem { Label(AppSection.screen.shortLabel, systemImage: AppSection.screen.systemImage) }
            .tag(AppSection.screen)
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
            }
        }

        private var accountMenu: some View {
            Menu {
                accountMenuActions
            } label: {
                accountMenuLabel
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("Account and settings")
        }

        @ViewBuilder
        private var accountMenuActions: some View {
            if store.mergeableAccounts.count >= 2 {
                Button {
                    store.showAllAccounts = true
                } label: {
                    if store.isMergedView {
                        Label("All Accounts", systemImage: "checkmark")
                    } else {
                        Label("All Accounts", systemImage: "person.2")
                    }
                }
            }

            ForEach(store.accounts) { account in
                Button {
                    store.showAllAccounts = false
                    store.currentAccountID = account.id
                } label: {
                    accountMenuRow(for: account)
                }
            }

            if !store.accounts.isEmpty {
                Divider()
            }
            Button { openGeneralSettings() } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button { manageAccounts() } label: {
                Label("Manage Accounts...", systemImage: "person.crop.circle")
            }
            Button { startAddingAccount() } label: {
                Label("Add Account...", systemImage: "plus")
            }
        }

        @ViewBuilder
        private func accountMenuRow(for account: Account) -> some View {
            let isSelected = !store.isMergedView && account.id == store.currentAccount?.id
            let isUnauthorized = monitor.isUnauthorized(account.id)
            let title = isUnauthorized ? String(localized: "\(account.name) (bad key)") : account.name
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else if isUnauthorized {
                Label(title, systemImage: "exclamationmark.triangle.fill")
            } else if let symbol = account.iconSymbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }

        @ViewBuilder
        private var accountMenuLabel: some View {
            if store.isMergedView {
                Image(systemName: "person.2.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.purple)
            } else if let account = store.currentAccount {
                toolbarAccountAvatar(for: account)
                    .overlay(alignment: .bottomTrailing) {
                        if monitor.isUnauthorized(account.id) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                                .background(Circle().fill(.background).padding(-1))
                        }
                    }
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }

        @ViewBuilder
        private func toolbarAccountAvatar(for account: Account) -> some View {
            ZStack {
                Circle()
                    .fill(.primary.opacity(0.06))
                    .overlay(Circle().stroke(.primary.opacity(0.12), lineWidth: 1))
                if let symbol = account.iconSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.86))
                } else {
                    Text(accountInitials(for: account))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.86))
                }
            }
            .frame(width: 28, height: 28)
        }

        private func accountInitials(for account: Account) -> String {
            let words = account.name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            let initials = words.prefix(2).compactMap(\.first)
            return initials.isEmpty ? "?" : String(initials).uppercased()
        }

        private func openGeneralSettings() {
            SettingsNavigation.shared.selectedTab = .general
            openSettings()
        }

        private func startAddingAccount() {
            let navigation = SettingsNavigation.shared
            navigation.selectedTab = .accounts
            navigation.startAddingAccount = true
            openSettings()
        }

        private func manageAccounts() {
            SettingsNavigation.shared.selectedTab = .accounts
            openSettings()
        }

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

        @MainActor
        private func loadSessionContext() async {
            if store.isMergedView {
                await directory.loadMerged(for: store.mergeableAccounts)
                await monitor.checkCurrentAccount()
                monitor.start()
            } else if let account = store.currentAccount {
                async let warmed: Void = prefetchInactiveSections(account: account, active: nav.section)
                await directory.load(for: account)
                await monitor.checkCurrentAccount()
                monitor.start()
                await warmed
            }
        }

        private func prefetchInactiveSections(account: Account, active: AppSection) async {
            guard account.isMock || !account.apiKey.isEmpty else { return }

            let client = account.makeClient()
            let id = account.id

            if active != .pads {
                var latest: [Pad] = []
                do {
                    for try await snapshot in client.listPadsIncrementally() {
                        latest = snapshot
                        PadsCacheStore.shared.set(id, pads: snapshot, persist: false)
                    }
                    PadsCacheStore.shared.set(id, pads: latest)
                } catch {
                    if !latest.isEmpty { PadsCacheStore.shared.set(id, pads: latest) }
                }
            }

            if active != .questions, let questions = try? await client.listQuestions(sort: "updated_at,desc") {
                QuestionsCacheStore.shared.set(id, questions: questions)
            }

            if let quota = try? await client.quota() {
                QuotaCacheStore.shared.set(id, quota: quota)
            }
        }
    }

    private enum PhoneRoute: Hashable {
        case pad(String)
        case question(Int)
    }

    private struct PhoneSessionKey: Hashable {
        let accountID: UUID?
        let merged: Bool
    }


    private extension View {
        func phoneAccountToolbar<Menu: View>(_ menu: Menu) -> some View {
            toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    menu
                }
            }
        }
    }
#endif
