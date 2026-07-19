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
import FastList
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
    /// This window's published navigation state (injected by `ContentView`), the
    /// home of the candidate-count subtitle this list publishes (#887).
    @Environment(WindowNavigation.self) private var windowNav
    /// Offline read-only state (#1855): the invite/resend/cancel/delete write paths
    /// disable rather than offering mutations that can only fail.
    @Environment(\.isReadOnly) var isReadOnly
    @Environment(\.openWindow) var openWindow
    @State var tests: [ScreenTestSession] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var statusFilter: String?
    /// Server-side date filter (#443): narrows the `GET /tests` fetch by a lower-bound
    /// date so large campaigns don't pull every historical session. Re-fetches on change.
    @State private var dateRange: ScreenTestDateRange = .all
    /// One reference instant per selected date-range session. Reloads reuse it;
    /// choosing a new range starts a fresh deterministic window (#1473, #1474).
    @State private var dateRangeReference = Date()
    /// The selected row ids. An `NSTableView`-backed `FastList` (#439/#474) drives this
    /// as a set; a single selection drives the detail column's report.
    @State var selectedIDs: Set<Int> = []
    /// Monotonic id of the newest `load()` call: date-range changes and reloads can
    /// overlap, and only the newest request may publish rows or errors, so an older
    /// slower response can't overwrite the current date range's list (#885).
    @State private var loadGeneration = 0
    @State private var showInvite = false
    /// Sessions with any mutation (resend, cancel, or delete) in flight: repeated
    /// commands can't email the same candidate twice (#900) or duplicate a
    /// destructive request (#1852, #1853), and one shared set means resend and
    /// cancel can't run concurrently against the same invitation (#1854).
    @State var mutatingIDs: Set<Int> = []
    @State var testPendingDelete: ScreenTestSession?
    @State var actionErrors: [ScreenActionFailure] = []
    @State var actionErrorPresented = false
    @State var showResentConfirmation = false
    /// Identifies this view instance as the subtitle's publisher, so a disappearing
    /// instance can only clear a subtitle it still owns (#805).
    private let subtitleOwnerToken = UUID()

    var body: some View {
        coreList
            .sheet(isPresented: $showInvite) {
                ScreenInviteSheet(client: client, campaign: campaign) {
                    Task { await load() }
                }
            }
            .modifier(ScreenTestActionAlerts(
                testPendingDelete: $testPendingDelete,
                actionErrors: $actionErrors,
                actionErrorPresented: $actionErrorPresented,
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
            .onChange(of: dateRange) { _, _ in
                dateRangeReference = Date()
                Task { await load() }
            }
            // Local filters can hide selected rows; drop those from the selection so
            // commands gated on it (Edit > Copy) never fire for invisible rows and
            // clobber the clipboard with an empty payload (#809). Filter changes are
            // rare user actions, so the O(N) prune stays off the render path - the
            // copy gate itself must remain the O(1) `selectedIDs` check (#395).
            .onChange(of: statusFilter) { _, _ in refreshDerived() }
            .onChange(of: search) { _, _ in refreshDerived() }
            .onReloadRequest { await load() }
            // This list lives in the detail column (#448); publish the candidate count so the
            // campaigns column can show it as the window subtitle while a campaign is selected
            // (#475) — see `WindowNavigation.screenTestsSubtitle`. A test session's report opens
            // in its own window on double-click / Return (#474); there's no inline report here.
            .onChange(of: countSubtitle, initial: true) { _, new in publishCountSubtitle(new) }
            // Deselecting the campaign tears this view down; reset the published candidate count.
            .onDisappear { publishCountSubtitle("") }
            .focusedSceneValue(\.focusedScreenInviteAction, ScreenInviteAction(id: campaign.id,
                                                                               accountID: accountID,
                                                                               contentFingerprint: campaign.hashValue) {
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
        // Publications are tagged with this view instance, and the deferred write
        // honors that tag: during a direct A -> B campaign switch, A's queued
        // disappearance clear runs after B's publish and must not blank it (#805).
        let owner = subtitleOwnerToken
        let windowNav = windowNav
        DispatchQueue.main.async {
            if subtitle.isEmpty {
                guard windowNav.screenTestsSubtitleOwner == owner else { return }

                windowNav.screenTestsSubtitleOwner = nil
                if !windowNav.screenTestsSubtitle.isEmpty { windowNav.screenTestsSubtitle = "" }
            } else {
                windowNav.screenTestsSubtitleOwner = owner
                if windowNav.screenTestsSubtitle != subtitle { windowNav.screenTestsSubtitle = subtitle }
            }
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
            .disabled(isReadOnly)
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

    /// The distinct normalized statuses present, for the filter menu. Cached rather
    /// than rebuilt from a fresh Set on every body pass (#1859).
    @State private var statuses: [String] = []

    /// Tests matching the status + search filters, most-recent activity first.
    /// Cached: body, count, selection, and copy paths all read it, and recomputing
    /// the O(n log n) filter+sort per render made large campaigns pay repeatedly for
    /// every state settle (#1858; the #395 lesson). Refreshed from every input
    /// mutation: load, row mutations, and the filter/search onChange handlers.
    @State private(set) var filtered: [ScreenTestSession] = []

    /// Recomputes ``filtered`` and ``statuses``, then prunes any selection the new
    /// filter hides (#809).
    func refreshDerived() {
        statuses = Array(Set(tests.map { Self.normalizedStatus($0.status) })).sorted()
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = tests
            .filter { test in
                (statusFilter == nil || Self.normalizedStatus(test.status) == statusFilter)
                    && (query.isEmpty || matchesQuery(test, query))
            }
            .sorted { lhs, rhs in
                (lhs.lastActivityDate ?? .distantPast) > (rhs.lastActivityDate ?? .distantPast)
            }
        pruneHiddenSelection()
    }

    /// Statuses are compared normalized - trimmed and lowercased - so API casing or
    /// whitespace variants of one status can't yield duplicate filter choices or
    /// miss semantically identical rows (#1857).
    private static func normalizedStatus(_ status: String) -> String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Locale-aware, case- and diacritic-insensitive matching (#1856):
    /// `lowercased()` comparisons mishandle locale-specific casing such as the
    /// Turkish dotless I.
    private func matchesQuery(_ test: ScreenTestSession, _ query: String) -> Bool {
        (test.candidateName?.localizedStandardContains(query) ?? false)
            || (test.candidateEmail?.localizedStandardContains(query) ?? false)
    }

    private var countSubtitle: String {
        guard !tests.isEmpty else { return "" }

        let count = filtered.count
        return count == 1
            ? String(localized: "\(count) candidate")
            : String(localized: "\(count) candidates")
    }

    /// The selected rows, in list order.
    ///
    /// Read by `selectedTest` (which the detail column and the toolbar action both
    /// consume), so the scan over the whole filtered campaign list ran several times
    /// per render for what is usually a handful of selected rows. Short-circuiting on
    /// an empty selection covers the common case; beyond that the membership test is
    /// already O(1) against the Set (#2466).
    private var selectedTestsInOrder: [ScreenTestSession] {
        guard !selectedIDs.isEmpty else { return [] }

        return filtered.filter { selectedIDs.contains($0.id) }
    }

    var selectedTest: ScreenTestSession? {
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

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        do {
            let bounds = dateRange.bounds(relativeTo: dateRangeReference)
            let result = try await client.listAllTestsResult(
                campaignID: campaign.id, from: bounds.from, until: bounds.until
            )
            guard generation == loadGeneration else { return }

            tests = result.tests
            loadError = result.diagnostic
            refreshDerived()
        } catch is CancellationError {
            // View/account replacement is expected task lifecycle, not a stale-data error.
        } catch {
            guard generation == loadGeneration else { return }

            loadError = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
    }
}

/// Same-file extension so the overlay can keep using the view's private state while
/// staying out of the struct body, which sits right at the lint length limit.
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
