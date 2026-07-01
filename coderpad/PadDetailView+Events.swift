//
//  PadDetailView+Events.swift
//  coderpad
//

import SwiftUI

extension PadDetailView {
    var eventsCard: some View {
        DetailSection(title: "Events", systemImage: "list.bullet.rectangle") {
            if isLoading {
                ProgressView().controlSize(.small)
            }
        } content: {
            if let loadError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(loadError.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    // Inline recovery so a failed fetch doesn't force a navigate-away-and-back
                    // or a global reload (#621). Disabled while a retry is already in flight.
                    Button("Retry") { Task { await load() } }
                        .controlSize(.small)
                        .disabled(isLoading)
                }
            } else if events.isEmpty, !isLoading {
                Text("No events yet.").foregroundStyle(.secondary).font(.callout)
            } else {
                eventList
            }
        }
    }

    private var eventList: some View {
        // Lazy so only the visible timeline rows are built: an active session can
        // emit hundreds of grouped events, each a non-trivial row (icon, chips,
        // actor, timestamp), and this sits inside the detail pane's ScrollView.
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(groupedEvents) { group in
                // Baseline-align the icon to the title line rather than top-aligning
                // it: with `.top` the glyph floated above the text, and a "×9" count
                // chip — which makes the first line taller — exaggerated the gap (#331).
                // Matching the title's `.callout` font keeps the glyph sized to the text.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: icon(for: group.representative.kind))
                        .font(.callout)
                        .foregroundStyle(color(for: group.representative.kind))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(displayKind(group.representative.kind))
                                .font(.callout.weight(.semibold))
                            // Event-specific context from `metadata` — e.g. the language
                            // for a run, the question id, or a spectator join — kept as
                            // restrained secondary text to match the timeline.
                            if let context = eventContext(group.representative) {
                                Text(context)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            if group.count > 1 {
                                Chip(text: "×\(group.count)", tint: .accentColor)
                            }
                            if let actor = eventActor(group.representative) {
                                // Emphasize the most recently-active participant so the
                                // eye is drawn to whoever acted last in the session.
                                let isActive = group.representative.userName == activeParticipant
                                eventActorView(actor: actor, isActive: isActive,
                                               email: group.representative.userEmail)
                            }
                        }
                        eventTimestamp(for: group)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(for: group))
            }
        }
    }

    /// The actor name shown beside an event. Org members resolve to an email, so
    /// their name becomes a link to their pads, mirroring the Participants card.
    /// Everyone else stays plain text using weight (not link-blue) for the active
    /// emphasis, so the color never implies a tap target that isn't there.
    @ViewBuilder
    private func eventActorView(actor: String, isActive: Bool, email: String?) -> some View {
        let weight: Font.Weight = isActive ? .semibold : .regular
        if let memberEmail = memberEmail(forName: actor) {
            Button {
                AppNavigation.shared.showPads(PadsRequest(ownerEmail: memberEmail))
            } label: {
                Text("· \(actor)")
                    .font(.callout.weight(weight))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Show pads from \(actor)")
        } else {
            Text("· \(actor)")
                .font(.callout.weight(weight))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .help(email ?? actor)
        }
    }

    @ViewBuilder
    private func eventTimestamp(for group: PadEventGroup) -> some View {
        if let first = group.representative.createdAt {
            if group.count > 1, let last = group.lastEvent.createdAt {
                let firstText = first.formatted(date: .long, time: .shortened)
                let lastText = last.formatted(date: .omitted, time: .shortened)
                Text("\(firstText) - \(lastText)")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                Text(first.formatted(date: .long, time: .shortened))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private var groupedEvents: [PadEventGroup] {
        PadEventGrouping.group(events)
    }

    /// The participant who acted most recently in the session. Events are grouped
    /// oldest-first, so the most recent named actor is found by scanning from the
    /// end. Nil when no event carries a user name.
    private var activeParticipant: String? {
        for group in groupedEvents.reversed() {
            if let name = group.lastEvent.userName ?? group.representative.userName, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    /// Turns a raw event kind (e.g. `added_question`) into human-readable copy
    /// (`Added Question`). The API uses snake_case, so underscores become spaces
    /// before capitalizing rather than surviving into the UI.
    private func displayKind(_ kind: String) -> String {
        kind.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// The actor to show for an event: the participant's name, falling back to their
    /// email when the API gives no name (so an email-only actor still appears rather
    /// than vanishing). `nil` when neither is present.
    private func eventActor(_ event: PadEvent) -> String? {
        if let name = event.userName, !name.isEmpty { return name }
        if let email = event.userEmail, !email.isEmpty { return email }
        return nil
    }

    /// A short, human-readable detail drawn from an event's `metadata`, interpreted
    /// by kind: the language for a run ("Ran Python"), the question id for an added
    /// question ("Added Question #123"), or a spectator join ("Joined as spectator").
    /// `nil` when there's no metadata or it isn't one of these recognized shapes.
    private func eventContext(_ event: PadEvent) -> String? {
        guard let meta = event.metadata?.trimmingCharacters(in: .whitespacesAndNewlines),
              !meta.isEmpty else { return nil }

        switch event.kind.lowercased() {
        case "ran", "executed": return meta.coderPadLanguageDisplayName
        case "added_question": return "#\(meta)"
        case "joined" where meta.lowercased() == "spectator": return String(localized: "as spectator")
        default: return nil
        }
    }

    private func icon(for kind: String) -> String {
        switch kind.lowercased() {
        case "joined": "person.fill.badge.plus"
        case "left": "person.fill.badge.minus"
        case "ended": "flag.checkered"
        case "started": "play.fill"
        case "edited", "typed": "pencil"
        case "ran", "executed": "play.circle"
        default: "circle.fill"
        }
    }

    private func color(for kind: String) -> Color {
        switch kind.lowercased() {
        case "joined": .green
        case "left": .secondary
        case "ended": .gray
        case "started": .blue
        case "ran", "executed": .orange
        default: .accentColor
        }
    }

    private func accessibilityLabel(for group: PadEventGroup) -> String {
        var parts = [displayKind(group.representative.kind)]
        if let context = eventContext(group.representative) { parts.append(context) }
        if group.count > 1 { parts.append("\(group.count) times") }
        if let user = eventActor(group.representative) { parts.append("by \(user)") }
        if let when = group.representative.createdAt {
            parts.append("at \(when.formatted(date: .long, time: .shortened))")
        }
        return parts.joined(separator: " ")
    }
}
