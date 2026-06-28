//
//  InterviewPadMatcherTests.swift
//  coderpadTests
//
//  Tests for the EventKit pad-matching heuristic (#592).
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Interview pad matching")
struct InterviewPadMatcherTests {
    /// A fixed reference instant so time-proximity scoring is deterministic.
    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    /// Builds a `Pad` through the real decoder (the type exposes only a decoder
    /// init), with just the fields the matcher reads.
    private func makePad(
        title: String,
        participants: [String],
        id: String = "p1",
        createdAt: Date? = nil
    ) throws -> Pad {
        let participantsJSON = participants.map { "\"\($0)\"" }.joined(separator: ", ")
        var fields = [
            "\"id\": \"\(id)\"",
            "\"title\": \"\(title)\"",
            "\"participants\": [\(participantsJSON)]",
            "\"url\": \"https://coderpad.io/\(id)\"",
            "\"state\": \"active\""
        ]
        if let createdAt {
            fields.append("\"created_at\": \"\(ISO8601DateFormatter().string(from: createdAt))\"")
        }
        let json = "{ \(fields.joined(separator: ", ")) }"
        return try CoderPadClient.decoder.decode(Pad.self, from: Data(json.utf8))
    }

    private func event(
        title: String,
        attendees: [String] = [],
        start: Date? = nil
    ) -> CalendarInterview {
        let start = start ?? reference
        return CalendarInterview(
            id: "e1",
            title: title,
            start: start,
            end: start.addingTimeInterval(3600),
            attendees: attendees,
            calendarTitle: "Work"
        )
    }

    @Test
    func `matches a pad by candidate name in the event title`() throws {
        let pad = try makePad(
            title: "Onsite: Senior Backend Engineer",
            participants: ["Polly Sherman", "basil@fawltytowers.co.uk"]
        )
        let interview = event(title: "Interview with Polly Sherman")
        #expect(InterviewPadMatcher.bestMatch(for: interview, among: [pad])?.id == pad.id)
    }

    @Test
    func `does not match an unrelated pad`() throws {
        let pad = try makePad(title: "Phone Screen", participants: ["Manuel Fawlty"])
        let interview = event(title: "Interview with Polly Sherman")
        #expect(InterviewPadMatcher.bestMatch(for: interview, among: [pad]) == nil)
    }

    @Test
    func `prefers the pad sharing the candidate over another`() throws {
        let polly = try makePad(title: "Onsite", participants: ["Polly Sherman"], id: "polly")
        let basil = try makePad(title: "Onsite", participants: ["Basil Fawlty"], id: "basil")
        let interview = event(title: "Polly Sherman onsite loop")
        #expect(InterviewPadMatcher.bestMatch(for: interview, among: [basil, polly])?.id == "polly")
    }

    @Test
    func `matches on role-title overlap plus a same-time pad creation`() throws {
        let pad = try makePad(title: "Two Sum", participants: [], createdAt: reference)
        let interview = event(title: "Two Sum review", start: reference)
        #expect(InterviewPadMatcher.bestMatch(for: interview, among: [pad])?.id == pad.id)
    }

    @Test
    func `title overlap alone, without proximity, is not enough`() throws {
        // A pad far in the past with a one-word title overlap should not match.
        let pad = try makePad(
            title: "Two Sum",
            participants: [],
            createdAt: reference.addingTimeInterval(-30 * 24 * 3600)
        )
        let interview = event(title: "Two Sum review", start: reference)
        #expect(InterviewPadMatcher.bestMatch(for: interview, among: [pad]) == nil)
    }

    @Test
    func `matches a candidate via an attendee email local-part`() throws {
        let pad = try makePad(title: "Onsite", participants: ["polly.sherman"])
        let interview = event(
            title: "Technical interview",
            attendees: ["polly.sherman@fawltytowers.co.uk"]
        )
        #expect(InterviewPadMatcher.bestMatch(for: interview, among: [pad])?.id == pad.id)
    }

    @Test
    func `ignores generic stop-words so meetings do not over-match`() {
        // Two events sharing only filler words yield no token overlap.
        #expect(InterviewPadMatcher.tokens("Interview with the candidate")
            .isDisjoint(with: InterviewPadMatcher.tokens("Phone screen meeting")))
    }
}
