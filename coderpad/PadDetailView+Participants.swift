//
//  PadDetailView+Participants.swift
//  coderpad
//

import SwiftUI

extension PadDetailView {
    /// The pad API exposes participants as display-name strings only. Display names
    /// are not stable identities, so the detail view deliberately avoids guessing
    /// candidate/interviewer roles from org member names.
    /// How many participant rows the card draws before summarizing the rest.
    ///
    /// An imported or long-running pad can carry a very large participant list, and
    /// the card built one row per entry with no cap — expensive to lay out, and a
    /// wall of names nobody reads (#2377).
    private static let visibleParticipantLimit = 25

    var participantsContent: some View {
        // De-duplicated and trimmed first: the API repeats a participant who
        // rejoined, and a blank entry drew an empty row.
        var seen = Set<String>()
        let names = pad.participants
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        let shown = Array(names.prefix(Self.visibleParticipantLimit))
        let overflow = names.count - shown.count
        return VStack(alignment: .leading, spacing: 12) {
            participantList(names: shown)
            if overflow > 0 {
                Text("and ^[\(overflow) more participants](inflect: true)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var participantsCard: some View {
        DetailSection(title: "Participants", systemImage: "person.2") {
            participantsContent
        }
    }

    /// A single column of compact participant rows. Rows hug their content instead of
    /// filling the detail pane, avoiding oversized backgrounds when a role has only
    /// one participant while still keeping names stacked predictably.
    private func participantList(names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Key by position rather than the name itself: two participants can
            // share a display name (or the same name can appear twice), and keying on
            // the name would then hand the list duplicate IDs. Indices rather than
            // `Array(names.enumerated())`, which materialized a copy of the whole
            // participant list on every render of the detail view (#2471).
            ForEach(names.indices, id: \.self) { index in
                participantRow(name: names[index])
            }
        }
    }

    private func participantRow(name: String) -> some View {
        Label(name, systemImage: "person")
            .font(.callout)
            .lineLimit(1)
            .frame(maxWidth: 260, alignment: .leading)
            .accessibilityLabel("Participant: \(name)")
    }
}
