//
//  MockScreen+Fixtures.swift
//  coderpad
//
//  Immutable seed data for the fake Screen API: campaigns, test sessions (in every
//  status, completed ones carrying a scored report with a per-technology/skill
//  breakdown), and a generated one-page PDF for the report download. Keys are the
//  snake_case the `ScreenAPI` models decode; timestamps are epoch milliseconds,
//  computed relative to now so the demo always looks recent.
//

import CoreGraphics
import CoreText
import Foundation

nonisolated enum MockScreenFixtures {
    // MARK: - Time helpers

    /// Now as epoch milliseconds — Screen's timestamp unit.
    static func nowMillis() -> Int {
        Int(Date.now.timeIntervalSince1970 * 1000)
    }

    /// `days` ago as epoch milliseconds.
    private static func daysAgo(_ days: Double) -> Int {
        Int((Date.now.timeIntervalSince1970 - days * 86400) * 1000)
    }

    // MARK: - Campaigns

    static func campaigns() -> [[String: Any]] {
        [
            ["id": 101, "name": "Backend Engineer",
             "languages": ["python3", "go", "java"], "pinned": true, "archived": false],
            ["id": 102, "name": "Frontend Engineer",
             "languages": ["javascript", "typescript"], "pinned": false, "archived": false],
            ["id": 103, "name": "Full-Stack Challenge",
             "languages": ["python3", "javascript", "sql"], "pinned": false, "archived": false],
            ["id": 104, "name": "Data Science Screen",
             "languages": ["python3", "r", "sql"], "pinned": false, "archived": false],
            ["id": 105, "name": "Legacy C++ Role (2023)",
             "languages": ["cpp"], "pinned": false, "archived": true]
        ]
    }

    // MARK: - Test sessions

    static func tests() -> [[String: Any]] {
        backendTests() + frontendTests() + fullStackTests() + dataScienceTests()
    }

    private static func backendTests() -> [[String: Any]] {
        [
            session(id: 5001, campaign: 101, status: "completed",
                    name: "Ada Lovelace", email: "ada@example.com",
                    sent: 9, started: 8, ended: 8, tags: ["referral", "senior"],
                    report: report(score: 88, duration: 3240,
                                   comparative: 71, warnings: ["Left full screen once"],
                                   technologies: backendTech(java: 90, algorithms: 86))),
            session(id: 5002, campaign: 101, status: "completed",
                    name: "Alan Turing", email: "alan@example.com",
                    sent: 6, started: 5, ended: 5, tags: ["inbound"],
                    report: report(score: 64, duration: 3600,
                                   comparative: 48, warnings: [],
                                   technologies: backendTech(java: 60, algorithms: 68))),
            session(id: 5003, campaign: 101, status: "in_progress",
                    name: "Grace Hopper", email: "grace@example.com",
                    sent: 1, started: 0.2, ended: nil, tags: []),
            session(id: 5004, campaign: 101, status: "waiting",
                    name: "Katherine Johnson", email: "katherine@example.com",
                    sent: 0.5, started: nil, ended: nil, tags: ["referral"]),
            session(id: 5005, campaign: 101, status: "aborted",
                    name: "Edsger Dijkstra", email: "edsger@example.com",
                    sent: 12, started: 11, ended: 11, tags: [])
        ]
    }

    private static func frontendTests() -> [[String: Any]] {
        [
            session(id: 5101, campaign: 102, status: "completed",
                    name: "Margaret Hamilton", email: "margaret@example.com",
                    sent: 4, started: 3, ended: 3, tags: ["senior"],
                    report: report(score: 92, duration: 2700,
                                   comparative: 83, warnings: [],
                                   technologies: frontendTech())),
            session(id: 5102, campaign: 102, status: "waiting",
                    name: "Barbara Liskov", email: "barbara@example.com",
                    sent: 0.8, started: nil, ended: nil, tags: []),
            session(id: 5103, campaign: 102, status: "cancelled",
                    name: "Donald Knuth", email: "donald@example.com",
                    sent: 7, started: nil, ended: nil, tags: ["withdrew"])
        ]
    }

    private static func fullStackTests() -> [[String: Any]] {
        [
            session(id: 5201, campaign: 103, status: "completed",
                    name: "Tim Berners-Lee", email: "tim@example.com",
                    sent: 2, started: 2, ended: 1, tags: ["inbound"],
                    report: report(score: 76, duration: 3000,
                                   comparative: 58, warnings: ["Pasted from clipboard"],
                                   technologies: frontendTech())),
            session(id: 5202, campaign: 103, status: "in_progress",
                    name: "Linus Torvalds", email: "linus@example.com",
                    sent: 1, started: 0.1, ended: nil, tags: [])
        ]
    }

    private static func dataScienceTests() -> [[String: Any]] {
        [
            session(id: 5301, campaign: 104, status: "completed",
                    name: "John McCarthy", email: "john@example.com",
                    sent: 5, started: 4, ended: 4, tags: [],
                    report: report(score: 81, duration: 3300,
                                   comparative: 66, warnings: [],
                                   technologies: dataScienceTech())),
            session(id: 5302, campaign: 104, status: "waiting",
                    name: "Radia Perlman", email: "radia@example.com",
                    sent: 0.3, started: nil, ended: nil, tags: ["referral"])
        ]
    }

    // MARK: - Session builder

    /// Builds a session dict. `sent`/`started`/`ended` are days-ago offsets; the latest
    /// of them seeds `last_activity_time` so the list's most-recent-first sort is stable.
    private static func session(
        id: Int, campaign: Int, status: String,
        name: String? = nil, email: String? = nil,
        sent: Double? = nil, started: Double? = nil, ended: Double? = nil,
        tags: [String] = [], report: [String: Any]? = nil
    ) -> [String: Any] {
        var session: [String: Any] = [
            "id": id, "id_test": id, "status": status, "campaign_id": campaign,
            "organization_id": "demo-org", "candidate_language": "en", "tags": tags,
            "url": "https://app.coderpad.io/screen/demo/dashboard/tests/\(id)",
            "test_url": "https://app.coderpad.io/screen/demo/tests/\(id)",
            "questions": [["id": id * 10, "last_activity_time": daysAgo(ended ?? started ?? sent ?? 1)]]
        ]
        session["candidate_name"] = name ?? NSNull()
        session["candidate_email"] = email ?? NSNull()
        if let sent { session["send_time"] = daysAgo(sent) }
        if let started { session["start_time"] = daysAgo(started) }
        if let ended { session["end_time"] = daysAgo(ended) }
        session["last_activity_time"] = daysAgo(ended ?? started ?? sent ?? 1)
        if let report { session["report"] = report }
        return session
    }

    // MARK: - Report builders

    /// Builds a report dict. Fixture points always equal the score and the total is
    /// always 100, so both are derived here rather than passed.
    private static func report(
        score: Double, duration: Int, comparative: Double,
        warnings: [String], technologies: [String: Any]
    ) -> [String: Any] {
        [
            "score": score, "points": Int(score.rounded()), "total_points": 100,
            "duration": duration, "total_duration": duration,
            "comparative_score": comparative, "warnings": warnings,
            "technologies": technologies,
            "community_stats": [2, 5, 9, 14, 20, 18, 12, 8, 4, 2]
        ]
    }

    private static func backendTech(java: Double, algorithms: Double) -> [String: Any] {
        [
            "Java": technology(score: java, skills: [
                "Language knowledge": skill(score: java + 2),
                "Problem solving": skill(score: java - 4)
            ]),
            "Algorithms": technology(score: algorithms, skills: [
                "Data structures": skill(score: algorithms),
                "Complexity": skill(score: algorithms - 6)
            ])
        ]
    }

    private static func frontendTech() -> [String: Any] {
        [
            "JavaScript": technology(score: 90, skills: [
                "DOM & events": skill(score: 92),
                "Async": skill(score: 84)
            ]),
            "CSS": technology(score: 78, skills: [
                "Layout": skill(score: 80),
                "Responsive design": skill(score: 74)
            ])
        ]
    }

    private static func dataScienceTech() -> [String: Any] {
        [
            "Python": technology(score: 84, skills: [
                "Pandas": skill(score: 88),
                "NumPy": skill(score: 80)
            ]),
            "SQL": technology(score: 76, skills: [
                "Joins": skill(score: 79),
                "Aggregation": skill(score: 72)
            ])
        ]
    }

    private static func technology(score: Double, skills: [String: Any]) -> [String: Any] {
        ["score": score, "points": Int(score.rounded()), "total_points": 100,
         "comparative_score": max(0, score - 12), "skills": skills]
    }

    private static func skill(score: Double) -> [String: Any] {
        ["score": score, "points": Int(score.rounded()), "total_points": 100]
    }

    // MARK: - Report PDF

    /// A one-page PDF for the report download, drawn with Core Graphics so it's always a
    /// valid document that opens in Preview. Generated off the main thread (it runs on
    /// the URL loading system's threads), which Core Graphics PDF contexts support.
    static func reportPDF(candidate: String, score: Double?) -> Data {
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 420, height: 300)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1))
        draw("CoderPad Screen — Demo Report", in: context, originX: 30, originY: 240, size: 20)
        draw("Candidate: \(candidate)", in: context, originX: 30, originY: 198, size: 14)
        if let score {
            draw("Overall score: \(Int(score.rounded()))/100", in: context, originX: 30, originY: 170, size: 14)
        }
        context.setFillColor(CGColor(red: 0.4, green: 0.4, blue: 0.42, alpha: 1))
        draw("Sample report data generated by the in-app demo.", in: context, originX: 30, originY: 120, size: 11)
        context.endPDFPage()
        context.closePDF()
        return pdfData as Data
    }

    /// Draws a single line of text at a baseline point, using the context's current fill
    /// color (Core Text falls back to it when no foreground-color attribute is set).
    private static func draw(_ string: String, in context: CGContext,
                             originX: CGFloat, originY: CGFloat, size: CGFloat) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ]
        let attributed = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: originX, y: originY)
        CTLineDraw(line, context)
    }
}
