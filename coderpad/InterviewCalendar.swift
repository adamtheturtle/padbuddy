//
//  InterviewCalendar.swift
//  coderpad
//
//  Read-only EventKit integration (#592): surfaces the user's upcoming calendar
//  events so the menu bar can link a scheduled interview to its pad and jump
//  straight into it. Access is requested lazily (only when the user opts in via
//  "Connect Calendar…"), never on launch.
//

import EventKit
import Foundation
import Observation

@MainActor
@Observable
final class InterviewCalendar {
    static let shared = InterviewCalendar()

    /// EventKit's own store. Constructing it does not prompt; only an explicit
    /// access request does.
    private let store = EKEventStore()

    /// Upcoming, timed (non-all-day) events within the look-ahead window, soonest
    /// first. Empty until access is granted and `reload()` runs.
    private(set) var upcoming: [CalendarInterview] = []

    /// How far ahead to look for interviews.
    private let horizon: TimeInterval = 7 * 24 * 3600

    private init() {}

    /// The current calendar authorization. Reading this never prompts.
    var authorization: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// Whether the app may read events (the access level EventKit grants for a
    /// read request on current OSes).
    var isAuthorized: Bool {
        authorization == .fullAccess
    }

    /// Prompts for read access (full access is what EventKit grants reads under)
    /// and, if granted, loads the upcoming events. A no-op refresh when already
    /// authorized.
    func requestAccessAndReload() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            if granted {
                reload()
            }
        } catch {
            // Denied or errored: leave `upcoming` empty; the UI falls back to the
            // connect affordance or hides the section.
        }
    }

    /// Reloads only when access is already granted, so it is cheap and prompt-free
    /// to call from a menu's `.task` on every open.
    func reloadIfAuthorized() {
        guard isAuthorized else { return }
        reload()
    }

    /// Queries the event store for timed events between now and the horizon.
    func reload() {
        guard isAuthorized else { return }
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now,
            end: now.addingTimeInterval(horizon),
            calendars: nil
        )
        upcoming = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map(CalendarInterview.init(event:))
    }
}

extension CalendarInterview {
    /// Maps an EventKit event into the dependency-free value the matcher and UI use.
    init(event: EKEvent) {
        self.init(
            id: event.eventIdentifier ?? event.calendarItemIdentifier,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            attendees: (event.attendees ?? []).compactMap { participant in
                participant.name
                    ?? participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
            },
            calendarTitle: event.calendar?.title
        )
    }
}
