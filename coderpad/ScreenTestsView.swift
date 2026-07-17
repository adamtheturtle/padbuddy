//
//  ScreenTestsView.swift
//  coderpad
//
//  The test-sessions list for the selected Screen campaign (#434). Shown in the Screen
//  section's detail column when a campaign is selected in the campaigns list (#448);
//  a session's report opens in its own window on double-click (#474). Read-only.
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

/// The test sessions for one campaign (`GET /tests`, all pages via
/// `ScreenClient.listAllTests(campaignID:)`). Rows show the candidate, a status
/// badge, the overall score, and the most relevant date; the list filters by status
/// and the shared search field (candidate), sorted by most-recent activity.
struct ScreenTestsView: View {
    let client: ScreenClient
    let campaign: ScreenCampaign
    @Binding var search: String
    /// The account this campaign belongs to in the combined "All Accounts" view
    /// (#442), so opening a session in its own window addresses the right account
    /// even though there's no single "current" account when merged. `nil` in the
    /// single-account view, where the current account owns every session. (No
    /// `= nil`: the synthesized memberwise init defaults an optional to nil, and
    /// SwiftLint's `implicit_optional_initialization` forbids the explicit form.)
    var accountID: UUID?
    @State private var nav = AppNavigation.shared
    @State private var accounts = AccountsStore.shared
    @Environment(\.openWindow) private var openWindow
    @State private var tests: [ScreenTestSession] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var statusFilter: String?
    /// Server-side date filter (#443): narrows the `GET /tests` fetch by a lower-bound
    /// date so large campaigns don't pull every historical session. Re-fetches on change.
    @State private var dateRange: ScreenTestDateRange = .all
    /// The selected row ids. An `NSTableView`-backed `FastList` (#439/#474) drives this
    /// as a set; a single selection drives the detail column's report.
    @State private var selectedIDs: Set<Int> = []
    /// Monotonic id of the newest `load()` call: date-range changes and reloads can
    /// overlap, and only the newest request may publish rows or errors, so an older
    /// slower response can't overwrite the current date range's list (#885).
    @State private var loadGeneration = 0
    @State private var showInvite = false
    @State private var testPendingDelete: ScreenTestSession?
    @State private var actionError: String?
    @State private var showResentConfirmation = false

    var body: some View {
        coreList
            .sheet(isPresented: $showInvite) {
                ScreenInviteSheet(client: client, campaign: campaign) {
                    Task { await load() }
                }
            }
            .modifier(ScreenTestActionAlerts(
                testPendingDelete: $testPendingDelete,
                actionError: $actionError,
                showResentConfirmation: $showResentConfirmation,
                onDelete: { test in Task { await delete(test) } }
            ))
            .toolbar(id: "screen-tests") { toolbarContent }
    }

    /// The list plus its data/selection lifecycle, split out of `body` so each getter
    /// stays under the Release build's 250ms type-check budget — the full modifier chain
    /// (list + sheet + dialog + alerts + toolbar) blew it on Xcode 26.5 (#443).
    private var coreList: some View {
        // NSTableView-backed (#439/#474): instant selection on large lists, and a native
        // double-click (and Return) opens the session in its own window.
        FastList(filtered, selection: $selectedIDs) { test in
            ScreenTestRow(test: test).allowsHitTesting(false)
        }
        .onDoubleClick { openTestWindow($0) }
        .onReturnKey { openTestWindow($0) }
        .rowContextMenu { testTableMenuItems($0) }
        #if os(macOS)
            .onRowDrag { testPasteboardItem($0) }
        #endif
            .overlay { statusOverlay }
            // A refresh failure over previously loaded sessions must not pose as
            // current candidate data (#803): keep the rows but flag them stale.
            .safeAreaInset(edge: .top, spacing: 0) {
                if let loadError, !tests.isEmpty {
                    StaleRefreshBanner(message: loadError) { Task { await load() } }
                        .padding(8)
                }
            }
            .task(id: campaign.id) { await load() }
            // The date range is a server-side filter, so changing it re-fetches (onChange,
            // not a second .task, so it doesn't double-fetch alongside the campaign task).
            .onChange(of: dateRange) { _, _ in Task { await load() } }
            // Local filters can hide selected rows; drop those from the selection so
            // commands gated on it (Edit > Copy) never fire for invisible rows and
            // clobber the clipboard with an empty payload (#809). Filter changes are
            // rare user actions, so the O(N) prune stays off the render path - the
            // copy gate itself must remain the O(1) `selectedIDs` check (#395).
            .onChange(of: statusFilter) { _, _ in pruneHiddenSelection() }
            .onChange(of: search) { _, _ in pruneHiddenSelection() }
            .task {
                for await _ in AppRouter.reloads {
                    await load()
                }
            }
            // This list lives in the detail column (#448); publish the candidate count so the
            // campaigns column can show it as the window subtitle while a campaign is selected
            // (#475) — see `AppNavigation.screenTestsSubtitle`. A test session's report opens
            // in its own window on double-click / Return (#474); there's no inline report here.
            .onChange(of: countSubtitle, initial: true) { _, new in publishCountSubtitle(new) }
            // Deselecting the campaign tears this view down; reset the published candidate count.
            .onDisappear { publishCountSubtitle("") }
            .focusedSceneValue(\.focusedScreenInviteAction, ScreenInviteAction(id: campaign.id) {
                showInvite = true
            })
            .focusedSceneValue(\.focusedScreenTestAction, selectedTestAction)
        #if os(macOS)
            .onCopyCommand(perform: copyLinkCommand(hasSelection: !selectedIDs.isEmpty) {
                selectedTestCopyText
            })
        #endif
    }

    private func publishCountSubtitle(_ subtitle: String) {
        guard nav.screenTestsSubtitle != subtitle else { return }

        DispatchQueue.main.async {
            if nav.screenTestsSubtitle != subtitle { nav.screenTestsSubtitle = subtitle }
        }
    }

    /// Extracted from `body` so its getter stays under the Release build's 250ms
    /// type-check budget (warnings-as-errors); adding the date-range item tipped the
    /// inline toolbar over on Xcode 26.5 (#443).
    @ToolbarContentBuilder
    private var toolbarContent: some CustomizableToolbarContent {
        ToolbarItem(id: "invite", placement: .automatic) {
            Button { showInvite = true } label: {
                Label("Invite Candidate", systemImage: "person.badge.plus")
            }
            .help("Invite a candidate to this campaign.")
        }
        ToolbarItem(id: "status-filter", placement: .automatic) {
            Menu {
                Picker("Status", selection: $statusFilter) {
                    Text("All Statuses").tag(String?.none)
                    ForEach(statuses, id: \.self) { status in
                        Text(ScreenTestStatus.label(status)).tag(String?.some(status))
                    }
                }
            } label: {
                Label("Filter by Status", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Filter test sessions by status.")
        }
        ToolbarItem(id: "date-range", placement: .automatic) {
            Menu {
                Picker("Date Range", selection: $dateRange) {
                    ForEach(ScreenTestDateRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Date Range", systemImage: "calendar")
            }
            .help("Only fetch test sessions active within a recent window.")
        }
        ToolbarItem(id: "reload", placement: .automatic) {
            Button { Task { await load() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .help("Reload test sessions.")
            .disabled(isLoading)
        }
    }

    /// The distinct statuses present, for the filter menu.
    private var statuses: [String] {
        Array(Set(tests.map(\.status))).sorted()
    }

    /// Tests matching the status + search filters, most-recent activity first.
    private var filtered: [ScreenTestSession] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tests
            .filter { test in
                (statusFilter == nil || test.status == statusFilter)
                    && (query.isEmpty || matchesQuery(test, query))
            }
            .sorted { lhs, rhs in
                (lhs.lastActivityDate ?? .distantPast) > (rhs.lastActivityDate ?? .distantPast)
            }
    }

    private func matchesQuery(_ test: ScreenTestSession, _ query: String) -> Bool {
        (test.candidateName?.lowercased().contains(query) ?? false)
            || (test.candidateEmail?.lowercased().contains(query) ?? false)
    }

    private var countSubtitle: String {
        guard !tests.isEmpty else { return "" }

        let count = filtered.count
        return count == 1
            ? String(localized: "\(count) candidate")
            : String(localized: "\(count) candidates")
    }

    private var selectedTestsInOrder: [ScreenTestSession] {
        filtered.filter { selectedIDs.contains($0.id) }
    }

    private var selectedTest: ScreenTestSession? {
        selectedTestsInOrder.first
    }

    private var selectedTestCopyText: String {
        selectedTestsInOrder.map(\.screenCopyText).joined(separator: "\n")
    }

    /// Drops selected rows the status/search filter has hidden (#809), mirroring the
    /// prune `load()` applies against fresh server data.
    private func pruneHiddenSelection() {
        let visible = Set(filtered.map(\.id))
        let pruned = selectedIDs.intersection(visible)
        if pruned != selectedIDs { selectedIDs = pruned }
    }

    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        do {
            let fromMs = dateRange.lowerBound.map { Int($0.timeIntervalSince1970 * 1000) }
            let fetched = try await client.listAllTests(campaignID: campaign.id, from: fromMs)
            guard generation == loadGeneration else { return }

            tests = fetched
            loadError = nil
            pruneHiddenSelection()
        } catch {
            guard generation == loadGeneration else { return }

            loadError = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
    }

    // MARK: Row actions (write paths, #437)

    /// The right-click menu for a row, gated by status: resend and cancel apply only to
    /// an invitation the candidate hasn't started yet ("waiting"); delete is always
    /// available behind a confirmation. "Open in New Window" mirrors the double-click.
    private func testTableMenuItems(_ test: ScreenTestSession) -> [MenuItem] {
        var items: [MenuItem] = [
            .button(title: String(localized: "Open in New Window")) { openTestWindow(test) },
            .button(title: String(localized: "Copy Test Session")) { Clipboard.copy(test.screenCopyText) },
            .separator
        ]
        if test.status == "waiting" {
            items.append(.button(title: String(localized: "Resend Invitation")) { Task { await resend(test) } })
            items.append(.button(title: String(localized: "Cancel Invitation")) { Task { await cancel(test) } })
            items.append(.separator)
        }
        items.append(.button(title: String(localized: "Delete Test Session"), role: .destructive) {
            testPendingDelete = test
        })
        return items
    }

    private var selectedTestAction: ScreenTestAction? {
        guard let selectedTest else { return nil }

        return ScreenTestAction(id: selectedTest.id, status: selectedTest.status) {
            Clipboard.copy(selectedTest.screenCopyText)
        } openWindow: {
            openTestWindow(selectedTest)
        } resend: {
            Task { await resend(selectedTest) }
        } cancel: {
            Task { await cancel(selectedTest) }
        } delete: {
            testPendingDelete = selectedTest
        }
    }

    #if os(macOS)
        private func testPasteboardItem(_ test: ScreenTestSession) -> NSPasteboardItem? {
            let item = NSPasteboardItem()
            if let url = test.screenURL {
                item.setString(url.absoluteString, forType: .URL)
            }
            item.setString(test.screenCopyText, forType: .string)
            return item
        }
    #endif

    /// Opens a test session's report in its own window (#474). The owning account is
    /// the explicit `accountID` in the combined view (#442), else the current account.
    private func openTestWindow(_ test: ScreenTestSession) {
        let owner = accountID ?? accounts.currentAccountID
        openWindow(id: "screen-test", value: ScreenTestWindowID(account: owner, id: test.id))
    }

    private func resend(_ test: ScreenTestSession) async {
        do {
            try await client.resendTest(id: test.id)
            showResentConfirmation = true
        } catch {
            actionError = message(for: error)
        }
    }

    private func cancel(_ test: ScreenTestSession) async {
        do {
            try await client.cancelTest(id: test.id)
            await load()
        } catch {
            actionError = message(for: error)
        }
    }

    private func delete(_ test: ScreenTestSession) async {
        do {
            try await client.deleteTest(id: test.id)
            selectedIDs.remove(test.id)
            await load()
        } catch {
            actionError = message(for: error)
        }
    }

    private func message(for error: any Error) -> String {
        (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
    }
}

// Same-file extension so the overlay can keep using the view's private state while
// staying out of the struct body, which sits right at the lint length limit.
private extension ScreenTestsView {
    @ViewBuilder
    var statusOverlay: some View {
        if let loadError, tests.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load test sessions", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        } else if tests.isEmpty, isLoading {
            ProgressView()
        } else if filtered.isEmpty {
            ContentUnavailableView {
                Label("No test sessions", systemImage: "person.crop.rectangle.stack")
            } description: {
                Text(tests.isEmpty
                    ? "No one has been invited to this campaign yet."
                    : "No test session matches your filters.")
            }
        }
    }
}
