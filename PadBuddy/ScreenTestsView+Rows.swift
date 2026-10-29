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
        if let name = candidateName, !name.isEmpty {
            return name
        }
        if let email = candidateEmail, !email.isEmpty {
            return email
        }
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
              !containsUnsafeURLScalar(string),
              let url = URL(string: string),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false,
              components.user == nil, components.password == nil,
              let decoded = url.absoluteString.removingPercentEncoding,
              !containsUnsafeURLScalar(url.absoluteString),
              !containsUnsafeURLScalar(decoded)
        else { return nil }

        return url
    }

    private static func containsUnsafeURLScalar(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .surrogate, .unassigned:
                true
            default:
                false
            }
        }
    }

    var screenCopyText: String {
        [
            String(id),
            screenCandidateDisplay,
            candidateEmail ?? "",
            ScreenTestStatus.label(status),
            report?.score.flatMap(ScreenScoreFormatting.integerText) ?? "",
            lastActivityDate?.formatted(date: .abbreviated, time: .shortened) ?? "",
            screenURL?.absoluteString ?? ""
        ].joined(separator: "\t")
    }
}

/// One test-session row: candidate, status badge, score, and the most relevant date.
struct ScreenTestRow: View {
    let test: ScreenTestSession

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AvatarCircle(label: candidate, diameter: 32, tint: .accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(candidate)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    ScreenStatusBadge(status: test.status)
                    Spacer(minLength: 0)
                    if let scoreText {
                        Label(scoreText, systemImage: "chart.bar.fill")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                            .help("Overall score")
                    }
                }
                HStack(spacing: 10) {
                    if let candidateEmail {
                        Label(candidateEmail, systemImage: "envelope")
                            .lineLimit(1)
                    }
                    if let dateText {
                        Label(dateText, systemImage: "clock")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var candidate: String {
        if let name = test.candidateName, !name.isEmpty {
            return name
        }
        if let email = test.candidateEmail, !email.isEmpty {
            return email
        }
        return String(localized: "Unknown candidate")
    }

    /// Show the email as supporting identity only when the primary label is a
    /// real name. When there is no name, `candidate` already uses the email and
    /// repeating it on the second line would add noise.
    private var candidateEmail: String? {
        guard test.candidateName?.isEmpty == false,
              let email = test.candidateEmail, !email.isEmpty else { return nil }

        return email
    }

    private var scoreText: String? {
        test.report?.score.map(ScreenScoreFormatting.percentText)
    }

    private var accessibilityLabel: String {
        var parts = [candidate]
        if let candidateEmail {
            parts.append(candidateEmail)
        }
        parts.append(ScreenTestStatus.label(test.status))
        if let scoreText {
            parts.append(String(localized: "Overall score \(scoreText)"))
        }
        if let dateText {
            parts.append(dateText)
        }
        return parts.joined(separator: ", ")
    }

    /// The most informative date: when the test ended, else when it was sent.
    /// An end date only reads "Completed" when the session actually completed:
    /// aborted/expired sessions end too, and labeling their end date "Completed"
    /// misrepresents what happened (#1012).
    var dateText: String? {
        if let end = test.endDate {
            let day = end.formatted(SharedDateStyles.day)
            return ScreenTestStatusPolicy.normalized(test.status) == "completed"
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
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(ScreenTestStatus.label(status))
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ScreenTestStatus.color(status).opacity(ChipContrast.fill(0.16, contrast)), in: Capsule())
            .foregroundStyle(ScreenTestStatus.color(status))
            .overlay(Capsule().stroke(ScreenTestStatus.color(status).opacity(ChipContrast.stroke(0.25, contrast)),
                                      lineWidth: ChipContrast.lineWidth(contrast)))
    }
}

/// Display helpers for the Screen test-session status strings (snake_case from the API).
enum ScreenTestStatus {
    static let maximumUnknownLabelLength = 32

    static func label(_ status: String) -> String {
        let normalized = ScreenTestStatusPolicy.normalized(status)
        return switch normalized {
        case "waiting": String(localized: "Waiting")
        case "in_progress": String(localized: "In Progress")
        case "completed": String(localized: "Completed")
        case "aborted": String(localized: "Aborted")
        case "cancelled": String(localized: "Cancelled")
        // Unknown/new statuses: humanize the raw value rather than hiding it.
        case "": String(localized: "Unknown")
        default: String(normalized.replacingOccurrences(of: "_", with: " ").capitalized
                .prefix(maximumUnknownLabelLength))
        }
    }

    static func color(_ status: String) -> Color {
        switch ScreenTestStatusPolicy.normalized(status) {
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
    // The memberwise inits validate their ids and scores, so the samples are optional.
    let completed = try? ScreenTestSession(
        id: 1, status: "completed", report: try? ScreenReport(score: 87),
        candidateName: "Ada Lovelace", endTime: 1_700_000_000_000
    )
    let inProgress = try? ScreenTestSession(
        id: 2, status: "in_progress", candidateName: "Alan Turing", sendTime: 1_700_000_000_000
    )
    let waiting = try? ScreenTestSession(
        id: 3, status: "waiting", candidateEmail: "grace@example.com", sendTime: 1_700_000_000_000
    )
    List {
        if let completed {
            ScreenTestRow(test: completed)
        }
        if let inProgress {
            ScreenTestRow(test: inProgress)
        }
        if let waiting {
            ScreenTestRow(test: waiting)
        }
    }
    .frame(width: 460, height: 240)
}
