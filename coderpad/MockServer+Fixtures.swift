//
//  MockServer+Fixtures.swift
//  coderpad
//
//  The fake API's canned fixture state and the merge logic that layers
//  session edits over the seed data. Split out of MockServer.swift to keep
//  each file within the line and body-length limits.
//

import Foundation

nonisolated enum MockFixtures {
    // Session edits (created / updated / deleted pads and questions) and the
    // `allPads()` / `allQuestions()` merge over these seeds now live on `MockState`,
    // one instance per API key, so concurrent tests don't share mutable state.
    // Everything below is immutable seed data, safe to read from any thread.

    static func seedPads() -> [[String: Any]] {
        [
            // Two environments: an active single-file Python and a multi-file
            // JavaScript. Exercises the stacked Code cards, the Active flag, and
            // the multi-file "N files" count.
            pad(id: "DEMOABC1", title: "Onsite: Jane Doe",
                language: "python3", ownerEmail: "alex@demo.co",
                state: "started", isPrivate: false, executionEnabled: true,
                participants: ["Jane Doe", "Alex Park"],
                createdAt: "2026-06-08T15:00:00Z", updatedAt: "2026-06-09T22:00:00Z",
                environmentIDs: [1, 2], activeEnvironmentID: 1),
            pad(id: "DEMOXYZ2", title: "Phone screen: Sam Lee",
                language: "javascript", ownerEmail: "morgan@demo.co",
                state: "ended", isPrivate: true, executionEnabled: true,
                participants: ["Sam Lee", "Morgan Lin"],
                createdAt: "2026-06-05T17:30:00Z", updatedAt: "2026-06-06T19:00:00Z",
                endedAt: "2026-06-06T19:00:00Z",
                notes: "Strong on arrays, hesitant on recursion.\nFollow up on the time-complexity discussion.",
                // Stand-in whiteboard image so the demo can show the Whiteboard
                // card; a real pad's `drawing` is a CoderPad-hosted PNG URL.
                drawing: "https://placehold.co/900x560/png?text=Whiteboard+sketch",
                environmentIDs: [1, 2], activeEnvironmentID: 2),
            // Three environments with the active one in the middle, so the Active
            // flag is clearly not just "the first card".
            pad(id: "DEMOPLY3", title: "Live coding: backend",
                language: "go", ownerEmail: "alex@demo.co",
                state: "started", isPrivate: false, executionEnabled: false,
                participants: ["Casey Wu", "Alex Park"],
                createdAt: "2026-06-09T18:00:00Z", updatedAt: "2026-06-09T18:20:00Z",
                environmentIDs: [1, 4, 2], activeEnvironmentID: 4),
            pad(id: "DEMOOLD4", title: "Q1 take-home draft",
                language: "rust", ownerEmail: "morgan@demo.co",
                state: "pending", isPrivate: true, executionEnabled: true,
                participants: [],
                createdAt: "2026-05-12T10:00:00Z", updatedAt: "2026-05-12T10:00:00Z",
                environmentIDs: [1, 2], activeEnvironmentID: 1),
            // A single environment, so its language chip alone names it and the
            // lone Code card carries no active badge.
            pad(id: "DEMOSWFT5", title: "iOS sample pad",
                language: "swift", ownerEmail: "demo@example.com",
                state: "started", isPrivate: false, executionEnabled: true,
                participants: ["Demo User"],
                createdAt: "2026-06-09T09:00:00Z", updatedAt: "2026-06-10T08:00:00Z",
                environmentIDs: [3], activeEnvironmentID: 3)
        ]
    }

    static func pad(id: String,
                    title: String,
                    language: String,
                    ownerEmail: String,
                    state: String,
                    isPrivate: Bool = false,
                    executionEnabled: Bool = true,
                    participants: [String] = [],
                    createdAt: String = "2026-06-10T08:00:00Z",
                    updatedAt: String = "2026-06-10T08:00:00Z",
                    endedAt: String? = nil,
                    notes: String? = nil,
                    drawing: String? = nil,
                    environmentIDs: [Int] = [1, 2],
                    activeEnvironmentID: Int = 1) -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "state": state,
            "owner_email": ownerEmail,
            "language": language,
            "private": isPrivate,
            "execution_enabled": executionEnabled,
            // The live API exposes the interviewer-access lock on every pad.
            "restrict_interviewer_access": false,
            "participants": participants,
            "url": "https://app.coderpad.io/\(id)",
            "playback": "https://app.coderpad.io/\(id)/playback",
            "events": "https://app.coderpad.io/api/pads/\(id)/events",
            // Firebase history URL: present on every live pad, mirroring the API.
            "history": "https://coderpad-1.firebaseio.com/\(id)/history.json",
            // The list response carries `contents`/`drawing` keys, null until the
            // pad has editor content or a whiteboard drawing.
            "contents": NSNull(),
            "drawing": drawing as Any? ?? NSNull(),
            "created_at": createdAt,
            "updated_at": updatedAt,
            "type": "live",
            "active_environment_id": activeEnvironmentID,
            "pad_environment_ids": environmentIDs,
            "question_ids": [101],
            "team": ["id": "demo-team", "name": "Demo Team"]
        ]
        if let endedAt { dict["ended_at"] = endedAt } else { dict["ended_at"] = NSNull() }
        if let notes { dict["notes"] = notes } else { dict["notes"] = NSNull() }
        return dict
    }

    /// A distinct, plausible timeline per seed pad, so the demo shows histories
    /// that fit each pad's state and participants rather than one canned list.
    /// Exercises the full range the timeline can render: question-added and
    /// spectator-join (both via `metadata`), multiple runs, edits, a terminal
    /// `ended` event for the ended pad, and a deliberately thin one-event log for
    /// the untouched draft.
    static func events(forPad id: String) -> [[String: Any]] {
        switch id {
        case "DEMOABC1": onsiteEvents()
        case "DEMOXYZ2": phoneScreenEvents()
        case "DEMOPLY3": backendEvents()
        case "DEMOOLD4": draftEvents()
        default: sampleEvents()
        }
    }

    // The active onsite: a question added, the candidate joining, then editing
    // and running twice — the grouped "×2" run path.
    private static func onsiteEvents() -> [[String: Any]] {
        [
            event("Pad started", "started", "Alex Park", "alex@demo.co", "2026-06-08T15:00:00Z"),
            event("Question added", "added_question", "Alex Park", "alex@demo.co", "2026-06-08T15:01:10Z",
                  metadata: "101"),
            event("Jane Doe joined the pad", "joined", "Jane Doe", nil, "2026-06-08T15:02:38Z"),
            event("Code edited", "edited", "Jane Doe", nil, "2026-06-08T15:20:04Z"),
            event("Code executed", "ran", "Jane Doe", nil, "2026-06-08T15:34:12Z", metadata: "python3"),
            event("Code executed", "ran", "Jane Doe", nil, "2026-06-08T15:41:55Z", metadata: "python3")
        ]
    }

    // The ended phone screen: a complete arc that finishes with `ended`.
    private static func phoneScreenEvents() -> [[String: Any]] {
        [
            event("Pad started", "started", "Morgan Lin", "morgan@demo.co", "2026-06-05T17:30:00Z"),
            event("Sam Lee joined the pad", "joined", "Sam Lee", nil, "2026-06-05T17:31:20Z"),
            event("Code executed", "ran", "Sam Lee", nil, "2026-06-05T17:45:09Z", metadata: "javascript"),
            event("Sam Lee left the pad", "left", "Sam Lee", nil, "2026-06-05T18:55:40Z"),
            event("Pad ended", "ended", "Morgan Lin", "morgan@demo.co", "2026-06-06T19:00:00Z")
        ]
    }

    // The active backend pad has execution disabled, so no runs — instead it
    // shows a spectator joining (via `metadata`) alongside the candidate.
    private static func backendEvents() -> [[String: Any]] {
        [
            event("Pad started", "started", "Alex Park", "alex@demo.co", "2026-06-09T18:00:00Z"),
            event("Question added", "added_question", "Alex Park", "alex@demo.co", "2026-06-09T18:02:30Z",
                  metadata: "101"),
            event("Casey Wu joined the pad", "joined", "Casey Wu", nil, "2026-06-09T18:05:11Z"),
            event("Morgan Lin joined the pad", "joined", "Morgan Lin", "morgan@demo.co", "2026-06-09T18:10:47Z",
                  metadata: "spectator"),
            event("Code edited", "edited", "Casey Wu", nil, "2026-06-09T18:18:02Z")
        ]
    }

    // The untouched pending take-home draft: a single creation event, so the
    // timeline shows a believably thin history rather than a full session.
    private static func draftEvents() -> [[String: Any]] {
        [event("Pad started", "started", "Morgan Lin", "morgan@demo.co", "2026-05-12T10:00:00Z")]
    }

    // The single-participant sample pad.
    private static func sampleEvents() -> [[String: Any]] {
        [
            event("Pad started", "started", "Demo User", "demo@example.com", "2026-06-09T09:00:00Z"),
            event("Demo User joined the pad", "joined", "Demo User", "demo@example.com", "2026-06-09T09:00:30Z"),
            event("Code executed", "ran", "Demo User", "demo@example.com", "2026-06-09T09:15:18Z", metadata: "swift")
        ]
    }

    private static func event(_ message: String, _ kind: String, _ userName: String,
                              _ userEmail: String?, _ createdAt: String,
                              metadata: String? = nil) -> [String: Any] {
        var dict: [String: Any] = [
            "message": message, "kind": kind,
            "user_name": userName, "user_email": userEmail as Any? ?? NSNull(),
            "created_at": createdAt
        ]
        if let metadata { dict["metadata"] = metadata }
        return dict
    }
}
