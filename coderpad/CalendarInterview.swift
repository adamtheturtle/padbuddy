//
//  CalendarInterview.swift
//  coderpad
//
//  A calendar-event value type and the pure pad-matching heuristic behind the
//  EventKit integration (#592). Kept free of any EventKit dependency so the
//  matching logic is deterministic and unit-testable; `InterviewCalendar` maps
//  `EKEvent`s into these values.
//

import Foundation

/// A scheduled calendar event that may correspond to an interview pad.
struct CalendarInterview: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    /// Attendee display names (or email local-parts when no name is set).
    let attendees: [String]
    /// The owning calendar's title, for display/disambiguation.
    let calendarTitle: String?
}

/// A pure heuristic that associates a calendar event with the interview pad it most
/// likely belongs to, by candidate/interviewer name, role-title overlap, and how
/// close the pad's creation sits to the event's start. Deliberately conservative:
/// a single weak signal does not clear the bar, so an unrelated pad is left
/// unmatched rather than mislinked.
enum InterviewPadMatcher {
    /// Words that carry no identifying signal in interview titles, so they never
    /// count toward a match.
    private static let stopWords: Set<String> = [
        "interview", "interviews", "with", "and", "the", "for", "of",
        "onsite", "phone", "screen", "screening", "technical", "tech",
        "coding", "code", "pad", "coderpad", "call", "meeting", "sync",
        "round", "candidate", "final", "loop", "panel", "chat", "intro",
        "session", "live", "remote", "video", "zoom", "google", "meet"
    ]

    /// Significant lowercased word tokens in a string: letters/numbers only, at
    /// least two characters, stop-words removed.
    static func tokens(_ string: String) -> Set<String> {
        Set(
            string.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 2 && !stopWords.contains($0) }
        )
    }

    /// Reduces an attendee entry to name tokens, taking the local-part of an email
    /// address (split on `.`/`_`) when the entry looks like one.
    private static func attendeeTokens(_ attendee: String) -> Set<String> {
        if let atIndex = attendee.firstIndex(of: "@") {
            return tokens(String(attendee[..<atIndex]))
        }
        return tokens(attendee)
    }

    /// A heuristic confidence score for linking `event` to `pad`. Higher is better;
    /// `0` means no shared signal.
    static func score(event: CalendarInterview, pad: Pad) -> Int {
        let eventTitleTokens = tokens(event.title)
        let eventPeopleTokens = event.attendees.reduce(into: Set<String>()) {
            $0.formUnion(attendeeTokens($1))
        }
        let eventTokens = eventTitleTokens.union(eventPeopleTokens)

        // Strong signal: a pad participant's name appears in the event title or
        // among its attendees (the candidate, typically).
        let padPeopleTokens = pad.participants.reduce(into: Set<String>()) {
            $0.formUnion(tokens($1))
        }
        let nameHits = padPeopleTokens.intersection(eventTokens)

        // Weak signal: the pad's role title overlaps the event title.
        let titleHits = tokens(pad.title).intersection(eventTitleTokens)

        var score = nameHits.count * 3 + titleHits.count

        // Proximity of the pad's creation to the event start: a pad opened right
        // around interview time is likely this interview's pad.
        if let created = pad.createdAt {
            let delta = abs(created.timeIntervalSince(event.start))
            if delta <= 2 * 3600 {
                score += 2
            } else if delta <= 24 * 3600 {
                score += 1
            }
        }

        return score
    }

    /// The pad most likely linked to `event`, or `nil` when nothing clears
    /// `minimumScore`. The default bar (3) is met by a single name hit, or by a
    /// role-title overlap combined with a same-time pad creation.
    static func bestMatch(for event: CalendarInterview, among pads: [Pad], minimumScore: Int = 3) -> Pad? {
        pads
            .map { (pad: $0, score: score(event: event, pad: $0)) }
            .filter { $0.score >= minimumScore }
            .max { $0.score < $1.score }?
            .pad
    }
}
