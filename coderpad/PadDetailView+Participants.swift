//
//  PadDetailView+Participants.swift
//  coderpad
//

import SwiftUI

extension PadDetailView {
    /// The pad API exposes participants as display-name strings only. Display names
    /// are not stable identities, so the detail view deliberately avoids guessing
    /// candidate/interviewer roles from org member names.
    var participantsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            participantList(names: pad.participants)
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
            // share a display name (or the same name can appear twice), and
            // `id: \.self` would then hand the list duplicate IDs.
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                participantRow(name: name)
            }
        }
    }

    private func participantRow(name: String) -> some View {
        Text(name)
            .font(.callout)
            .lineLimit(1)
            .frame(maxWidth: 260, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.subtleStroke.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}
