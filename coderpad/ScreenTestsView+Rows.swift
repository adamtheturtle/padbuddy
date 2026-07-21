//
//  ScreenTestsView+Rows.swift
//  coderpad
//
//  Row, badge, and status-display helpers for the Screen test-sessions list
//  (see `ScreenTestsView`). Split out to keep each file under the length limit.
//

import SwiftUI

extension ScreenTestSession {
    var screenCandidateDisplay: String {
        if let name = candidateName, !name.isEmpty { return name }
        if let email = candidateEmail, !email.isEmpty { return email }
        return String(localized: "Unknown candidate")
    }

    var screenURL: URL? {
        // Validate each candidate independently (#806): a present-but-malformed
        // recruiter `url` must not suppress a valid candidate `test_url` fallback.
        Self.webURL(from: url) ?? Self.webURL(from: testURL)
    }

    /// Parses a candidate link, accepting only a well-formed absolute web URL.
    private static func webURL(from string: String?) -> URL? {
        guard let string,
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host() != nil
        else { return nil }

        return url
    }

    var screenCopyText: String {
        [
            String(id),
            screenCandidateDisplay,
            candidateEmail ?? "",
            ScreenTestStatus.label(status),
            report?.score.map { String(Int($0.rounded())) } ?? "",
            lastActivityDate?.formatted(date: .abbreviated, time: .shortened) ?? "",
            screenURL?.absoluteString ?? ""
        ].joined(separator: "\t")
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
    /// An end date only reads "Completed" when the session actually completed:
    /// aborted/expired sessions end too, and labeling their end date "Completed"
    /// misrepresents what happened (#1012).
    private var dateText: String? {
        if let end = test.endDate {
            let day = end.formatted(SharedDateStyles.day)
            return test.status == "completed"
                ? String(localized: "Completed \(day)")
                : String(localized: "Ended \(day)")
        }
        if let sent = test.sendDate {
            return String(localized: "Sent \(sent.formatted(SharedDateStyles.day))")
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
    // Build the sample sessions in their own statements to keep the List
    // ViewBuilder expression under the 250ms type-check budget.
    let completed = ScreenTestSession(
        id: 1, status: "completed", report: ScreenReport(score: 87),
        candidateName: "Ada Lovelace", endTime: 1_700_000_000_000
    )
    let inProgress = ScreenTestSession(
        id: 2, status: "in_progress", candidateName: "Alan Turing", sendTime: 1_700_000_000_000
    )
    let waiting = ScreenTestSession(
        id: 3, status: "waiting", candidateEmail: "grace@example.com", sendTime: 1_700_000_000_000
    )
    List {
        ScreenTestRow(test: completed)
        ScreenTestRow(test: inProgress)
        ScreenTestRow(test: waiting)
    }
    .frame(width: 460, height: 240)
}
