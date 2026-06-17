//
//  ScreenTestsView.swift
//  coderpad
//
//  The test-sessions list for a selected Screen campaign (#434). Pushed into the
//  Screen section's middle column from the campaigns list (campaigns → tests share
//  that column; the detail column shows the selected test's report, #435). Read-only.
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
    @State private var nav = AppNavigation.shared
    @State private var tests: [ScreenTestSession] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var statusFilter: String?
    @State private var selectedID: Int?
    @State private var showInvite = false

    var body: some View {
        List(selection: $selectedID) {
            ForEach(filtered) { test in
                ScreenTestRow(test: test).tag(test.id)
            }
        }
        .overlay { statusOverlay }
        .reportsSectionCount(countSubtitle)
        .navigationTitle(campaign.name)
        .task(id: campaign.id) { await load() }
        .task {
            for await _ in AppRouter.reloads {
                await load()
            }
        }
        .onAppear { selectedID = nav.screenTestSelection?.id }
        .onChange(of: selectedID) { _, id in
            nav.screenTestSelection = id.flatMap { tid in tests.first { $0.id == tid } }
        }
        // Leaving this campaign (popping back to the campaigns list) clears the
        // detail column's test selection so it doesn't show a stale report.
        .onDisappear { nav.screenTestSelection = nil }
        .sheet(isPresented: $showInvite) {
            ScreenInviteSheet(client: client, campaign: campaign) {
                Task { await load() }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { showInvite = true } label: {
                    Label("Invite Candidate", systemImage: "person.badge.plus")
                }
                .help("Invite a candidate to this campaign.")
            }
            ToolbarItem {
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
            ToolbarItem {
                Button { Task { await load() } } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help("Reload test sessions.")
                .disabled(isLoading)
            }
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
            ? String(localized: "\(count) test session")
            : String(localized: "\(count) test sessions")
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
            tests = try await client.listAllTests(campaignID: campaign.id)
            loadError = nil
            if let id = selectedID, !tests.contains(where: { $0.id == id }) {
                selectedID = nil
            }
        } catch {
            loadError = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        }
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
