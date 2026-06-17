//
//  MockServer+Organization.swift
//  coderpad
//
//  Org directory, stats, and quota fixtures for the fake API. Split out of
//  MockServer.swift to keep each file within the line and body-length limits.
//

import Foundation

nonisolated extension MockFixtures {
    /// One demo org member. The two user-facing shapes (directory vs. stats) are
    /// projected from these below.
    private struct Person {
        let email: String
        let name: String
        let padsCreated: Int
    }

    /// Single source of truth for the demo org's members.
    private static let people: [Person] = [
        Person(email: "alex@demo.co", name: "Alex Park", padsCreated: 12),
        Person(email: "morgan@demo.co", name: "Morgan Lin", padsCreated: 9),
        Person(email: "casey@demo.co", name: "Casey Wu", padsCreated: 2),
        Person(email: "robin@demo.co", name: "Robin Patel", padsCreated: 0),
        Person(email: "demo@example.com", name: "Demo User", padsCreated: 1)
    ]

    /// Directory shape: `/api/organization` and `/api/organization/users` return
    /// `{email, name, teams}` — no `pads_created`.
    static func users() -> [[String: Any]] {
        people.map { ["email": $0.email, "name": $0.name, "teams": ["demo-team"]] }
    }

    /// Stats shape: `/api/organization/stats` returns `{email, name, pads_created}`
    /// per user — no `teams`.
    static func statsUsers() -> [[String: Any]] {
        people.map { ["email": $0.email, "name": $0.name, "pads_created": $0.padsCreated] }
    }

    static func organization() -> [String: Any] {
        [
            "status": "OK",
            "id": 9999,
            "organization_name": "Demo Org",
            "child_organizations": [],
            "user_count": users().count,
            "users": users(),
            // Deliberately not the New Pad/Question sheets' hardcoded "python3"
            // fallback, so the org-default pre-selection is visible in the demo.
            "organization_default_language": "go",
            // SSO enabled with a portal URL so the Organization view's sign-on row
            // and "Open sign-in portal" action are exercised in the demo.
            "single_sign_on_supported": true,
            "single_sign_in_url": "https://app.coderpad.io/sso/demo-org",
            "teams": [["id": "demo-team", "name": "Demo Team"]]
        ]
    }

    static func organizationStats(query: [String: String] = [:]) -> [String: Any] {
        let start = query["start_time"] ?? "2026-06-03T00:00:00.000-07:00"
        let end = query["end_time"] ?? "2026-06-10T00:00:00.000-07:00"
        return [
            "status": "OK",
            "start_time": start,
            "end_time": end,
            // Scale roughly with the requested window (~1 pad/day) so the picker
            // produces a visibly different count.
            "pads_created": padsCreatedForWindow(start: start, end: end),
            "users": statsUsers()
        ]
    }

    private static func padsCreatedForWindow(start: String, end: String) -> Int {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        func parse(_ value: String) -> Date? {
            fractional.date(from: value) ?? basic.date(from: value)
        }
        guard let startDate = parse(start), let endDate = parse(end) else { return 7 }

        return min(365, max(1, Int(endDate.timeIntervalSince(startDate) / 86400)))
    }

    static func quota() -> [String: Any] {
        [
            "status": "OK",
            "trial_expires_at": "2027-01-01T00:00:00.000-08:00",
            "pads_used": 24,
            "quota_reset_at": "2026-07-01T00:00:00.000-07:00",
            "unlimited": false,
            "overages_enabled": true,
            "pads_remaining": 96,
            "billing_cycle_pad_limit": 120
        ]
    }
}
