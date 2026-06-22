//
//  MockServer+Organization.swift
//  coderpad
//
//  Org directory, stats, and quota fixtures for the fake API. Split out of
//  MockServer.swift to keep each file within the line and body-length limits.
//

import Foundation

nonisolated extension MockFixtures {
    // The demo organization is an affectionate nod to Fawlty Towers: a Torquay
    // hotel whose staff somehow run a steady stream of interviews. The data stays
    // shaped like a real CoderPad org so every screen has believable content; the
    // names are just there to raise a smile.
    static let orgName = "Fawlty Towers"
    static let orgDomain = "fawltytowers.co.uk"

    /// One interview team. Pads and people reference these by `id`, and the org
    /// payload lists them so the team filter can resolve ids to display names.
    static let teams: [(id: String, name: String)] = [
        ("team-frontdesk", "Front Desk"),
        ("team-dining", "Dining Room"),
        ("team-kitchen", "Kitchen"),
        ("team-housekeeping", "Housekeeping"),
        ("team-maintenance", "Maintenance")
    ]

    /// One demo org member. The two user-facing shapes (directory vs. stats) are
    /// projected from these below.
    private struct Person {
        let email: String
        let name: String
        let teamID: String
        let padsCreated: Int
    }

    /// Single source of truth for the demo org's members: the hotel's staff,
    /// ordered by how many pads they've run.
    private static let people: [Person] = [
        Person(email: "basil@fawltytowers.co.uk", name: "Basil Fawlty", teamID: "team-frontdesk", padsCreated: 41),
        Person(email: "sybil@fawltytowers.co.uk", name: "Sybil Fawlty", teamID: "team-frontdesk", padsCreated: 33),
        Person(email: "manuel@fawltytowers.co.uk", name: "Manuel", teamID: "team-dining", padsCreated: 27),
        Person(email: "terry@fawltytowers.co.uk", name: "Terry Hughes", teamID: "team-kitchen", padsCreated: 22),
        Person(email: "major@fawltytowers.co.uk", name: "Major Gowen", teamID: "team-frontdesk", padsCreated: 18),
        Person(email: "tibbs@fawltytowers.co.uk", name: "Miss Tibbs", teamID: "team-housekeeping", padsCreated: 14),
        Person(email: "gatsby@fawltytowers.co.uk", name: "Miss Gatsby", teamID: "team-housekeeping", padsCreated: 11),
        // The signed-in demo user, so "My Pads"/"My Questions" return real results.
        Person(email: demoUserEmail, name: demoUserName, teamID: "team-frontdesk", padsCreated: 8),
        Person(email: "oreilly@fawltytowers.co.uk", name: "Mr O'Reilly", teamID: "team-maintenance", padsCreated: 6),
        Person(email: "kurt@fawltytowers.co.uk", name: "Chef Kurt", teamID: "team-kitchen", padsCreated: 3),
        Person(email: "andre@fawltytowers.co.uk", name: "André", teamID: "team-dining", padsCreated: 0)
    ]

    /// Email and display name of the signed-in demo user — Polly, the one member of
    /// staff who reliably gets anything done. Kept here next to the org directory so
    /// the member, their pads, and their questions all line up.
    static let demoUserEmail = "polly@fawltytowers.co.uk"
    static let demoUserName = "Polly Sherman"

    /// Directory shape: `/api/organization` and `/api/organization/users` return
    /// `{email, name, teams}` — no `pads_created`.
    static func users() -> [[String: Any]] {
        people.map { ["email": $0.email, "name": $0.name, "teams": [$0.teamID]] }
    }

    /// Stats shape: `/api/organization/stats` returns `{email, name, pads_created}`
    /// per user — no `teams`.
    static func statsUsers() -> [[String: Any]] {
        people.map { ["email": $0.email, "name": $0.name, "pads_created": $0.padsCreated] }
    }

    private static func teamPayload() -> [[String: Any]] {
        teams.map { ["id": $0.id, "name": $0.name] }
    }

    static func organization() -> [String: Any] {
        [
            "status": "OK",
            "id": 9999,
            "organization_name": orgName,
            "child_organizations": [],
            "user_count": users().count,
            "users": users(),
            // Deliberately not the New Pad/Question sheets' hardcoded "python3"
            // fallback, so the org-default pre-selection is visible in the demo.
            "organization_default_language": "go",
            // SSO enabled with a portal URL so the Organization view's sign-on row
            // and "Open sign-in portal" action are exercised in the demo.
            "single_sign_on_supported": true,
            "single_sign_in_url": "https://app.coderpad.io/sso/fawlty-towers",
            "teams": teamPayload()
        ]
    }

    static func organizationStats(query: [String: String] = [:]) -> [String: Any] {
        let start = query["start_time"] ?? "2026-06-03T00:00:00.000-07:00"
        let end = query["end_time"] ?? "2026-06-10T00:00:00.000-07:00"
        return [
            "status": "OK",
            "start_time": start,
            "end_time": end,
            // Scale roughly with the requested window (~3 pads/day across the team)
            // so the picker produces a visibly different count.
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
        guard let startDate = parse(start), let endDate = parse(end) else { return 21 }

        return min(900, max(1, Int(endDate.timeIntervalSince(startDate) / 86400) * 3))
    }

    static func quota() -> [String: Any] {
        [
            "status": "OK",
            "trial_expires_at": "2027-01-01T00:00:00.000-08:00",
            "pads_used": 187,
            "quota_reset_at": "2026-07-01T00:00:00.000-07:00",
            "unlimited": false,
            "overages_enabled": true,
            "pads_remaining": 313,
            "billing_cycle_pad_limit": 500
        ]
    }
}
