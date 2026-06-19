//
//  ScreenTestsView.swift
//  coderpad
//
//  The test-sessions list for the selected Screen campaign (#434). Shown in the Screen
//  section's detail column when a campaign is selected in the campaigns list (#448);
//  a session's report opens in its own window on double-click (#474). Read-only.
//

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
    /// The selected row ids. An `NSTableView`-backed `ListTable` (#439/#474) drives this
    /// as a set; a single selection drives the detail column's report.
    @State private var selectedIDs: Set<Int> = []
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
        ListTable(
            items: filtered,
            selection: $selectedIDs,
            scrollToID: nil,
            onScrolledToID: {},
            rowContent: { test in AnyView(ScreenTestRow(test: test).allowsHitTesting(false)) },
            onDoubleClick: { openTestWindow($0) },
            onReturn: { openTestWindow($0) },
            leadingActions: { _ in [] },
            trailingActions: { _ in [] },
            pasteboardItem: { _ in nil },
            menuItems: { testTableMenuItems($0) }
        )
        .overlay { statusOverlay }
        .task(id: campaign.id) { await load() }
        // The date range is a server-side filter, so changing it re-fetches (onChange,
        // not a second .task, so it doesn't double-fetch alongside the campaign task).
        .onChange(of: dateRange) { _, _ in Task { await load() } }
        .task {
            for await _ in AppRouter.reloads {
                await load()
            }
        }
        // This list lives in the detail column (#448); publish the candidate count so the
        // campaigns column can show it as the window subtitle while a campaign is selected
        // (#475) — see `AppNavigation.screenTestsSubtitle`. A test session's report opens
        // in its own window on double-click / Return (#474); there's no inline report here.
        .onChange(of: countSubtitle, initial: true) { _, new in nav.screenTestsSubtitle = new }
        // Deselecting the campaign tears this view down; reset the published candidate count.
        .onDisappear { nav.screenTestsSubtitle = "" }
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
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
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

    @ViewBuilder
    private var statusOverlay: some View {
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fromMs = dateRange.lowerBound.map { Int($0.timeIntervalSince1970 * 1000) }
            tests = try await client.listAllTests(campaignID: campaign.id, from: fromMs)
            loadError = nil
            selectedIDs = selectedIDs.filter { id in tests.contains { $0.id == id } }
        } catch {
            loadError = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Row actions (write paths, #437)

    /// The right-click menu for a row, gated by status: resend and cancel apply only to
    /// an invitation the candidate hasn't started yet ("waiting"); delete is always
    /// available behind a confirmation. "Open in New Window" mirrors the double-click.
    private func testTableMenuItems(_ test: ScreenTestSession) -> [RowMenuItem] {
        var items: [RowMenuItem] = [
            .button(title: String(localized: "Open in New Window")) { openTestWindow(test) },
            .separator
        ]
        if test.status == "waiting" {
            items.append(.button(title: String(localized: "Resend Invitation")) { Task { await resend(test) } })
            items.append(.button(title: String(localized: "Cancel Invitation")) { Task { await cancel(test) } })
            items.append(.separator)
        }
        items.append(.button(title: String(localized: "Delete Test Session"),
                             isDestructive: true) { testPendingDelete = test })
        return items
    }

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

/// One test-session row: candidate, status badge, score, and the most relevant date.
struct ScreenTestRow: View {
    let test: ScreenTestSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(candidate)
                    .font(.body)
                    .lineLimit(1)
                ScreenStatusBadge(status: test.status)
                Spacer(minLength: 0)
                if let score = test.report?.score {
                    Text("\(Int(score.rounded()))")
                        .font(.callout.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help("Overall score")
                }
            }
            if let dateText {
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var candidate: String {
        if let name = test.candidateName, !name.isEmpty { return name }
        if let email = test.candidateEmail, !email.isEmpty { return email }
        return String(localized: "Unknown candidate")
    }

    /// The most informative date: when the test ended, else when it was sent.
    private var dateText: String? {
        if let end = test.endDate {
            return String(localized: "Completed \(end.formatted(date: .abbreviated, time: .omitted))")
        }
        if let sent = test.sendDate {
            return String(localized: "Sent \(sent.formatted(date: .abbreviated, time: .omitted))")
        }
        return nil
    }
}

/// A small capsule badge for a Screen test session's status.
struct ScreenStatusBadge: View {
    let status: String

    var body: some View {
        Text(ScreenTestStatus.label(status))
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ScreenTestStatus.color(status).opacity(0.16), in: Capsule())
            .foregroundStyle(ScreenTestStatus.color(status))
            .overlay(Capsule().stroke(ScreenTestStatus.color(status).opacity(0.25), lineWidth: 0.5))
    }
}

/// Display helpers for the Screen test-session status strings (snake_case from the API).
enum ScreenTestStatus {
    static func label(_ status: String) -> String {
        switch status {
        case "waiting": String(localized: "Waiting")
        case "in_progress": String(localized: "In Progress")
        case "completed": String(localized: "Completed")
        case "aborted": String(localized: "Aborted")
        case "cancelled": String(localized: "Cancelled")
        // Unknown/new statuses: humanize the raw value rather than hiding it.
        default: status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func color(_ status: String) -> Color {
        switch status {
        case "completed": .green
        case "in_progress": .blue
        case "aborted": .red
        case "cancelled": .orange
        default: .secondary
        }
    }
}

#Preview("Test rows") {
    List {
        ScreenTestRow(test: ScreenTestSession(
            id: 1, status: "completed", report: ScreenReport(score: 87),
            candidateName: "Ada Lovelace", endTime: 1_700_000_000_000
        ))
        ScreenTestRow(test: ScreenTestSession(
            id: 2, status: "in_progress", candidateName: "Alan Turing", sendTime: 1_700_000_000_000
        ))
        ScreenTestRow(test: ScreenTestSession(
            id: 3, status: "waiting", candidateEmail: "grace@example.com", sendTime: 1_700_000_000_000
        ))
    }
    .frame(width: 460, height: 240)
}
