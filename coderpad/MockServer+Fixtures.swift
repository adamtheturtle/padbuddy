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
    // The mutable stores below are unsynchronized storage, made safe by the single
    // `MockResponses.lock` that serializes every request: they are only ever read or
    // written from within `respondLocked`, which always runs under that lock. The
    // `unsafe` is the vouch for that external synchronization, not an unchecked race.
    nonisolated(unsafe) static var createdPads: [[String: Any]] = []
    nonisolated(unsafe) static var updatedPads: [String: [String: Any]] = [:]
    nonisolated(unsafe) static var deletedPadIDs: Set<String> = []
    nonisolated(unsafe) static var createdQuestions: [[String: Any]] = []
    nonisolated(unsafe) static var updatedQuestions: [Int: [String: Any]] = [:]
    nonisolated(unsafe) static var deletedQuestionIDs: Set<Int> = []

    static func allQuestions() -> [[String: Any]] {
        let merged = questions().map { question -> [String: Any] in
            guard let id = question["id"] as? Int, let updates = updatedQuestions[id] else { return question }
            var combined = question
            for (key, value) in updates where key != "id" {
                combined[key] = value
            }
            return combined
        }
        return (merged + createdQuestions).filter { question in
            guard let id = question["id"] as? Int else { return true }
            return !deletedQuestionIDs.contains(id)
        }
    }

    static func allPads() -> [[String: Any]] {
        func applyUpdates(_ pad: [String: Any]) -> [String: Any] {
            guard let id = pad["id"] as? String, let updates = updatedPads[id] else { return pad }
            var merged = pad
            for (key, value) in updates where key != "id" {
                merged[key] = value
            }
            return merged
        }
        // Both seed pads and pads created during the session need their `updatedPads`
        // overrides applied, otherwise ending/editing a freshly-created pad silently
        // no-ops while still returning HTTP 200.
        let base = seedPads().map(applyUpdates)
        let created = createdPads.map(applyUpdates)
        return (base + created).filter { pad in
            guard let id = pad["id"] as? String else { return true }
            return !deletedPadIDs.contains(id)
        }
    }

    private static func seedPads() -> [[String: Any]] {
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

    static func events(forPad _: String) -> [[String: Any]] {
        [
            ["message": "Pad started", "kind": "started",
             "user_name": "Alex Park", "user_email": "alex@demo.co",
             "created_at": "2026-06-09T18:00:00Z"],
            ["message": "Jane Doe joined the pad", "kind": "joined",
             "user_name": "Jane Doe", "user_email": NSNull(),
             "created_at": "2026-06-09T18:01:42Z"],
            ["message": "Code executed", "kind": "ran", "metadata": "python3",
             "user_name": "Jane Doe", "user_email": NSNull(),
             "created_at": "2026-06-09T18:14:08Z"],
            ["message": "Jane Doe left the pad", "kind": "left",
             "user_name": "Jane Doe", "user_email": NSNull(),
             "created_at": "2026-06-09T18:46:20Z"]
        ]
    }
}
