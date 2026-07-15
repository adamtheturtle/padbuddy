//
//  PadDetailView+Participants.swift
//  coderpad
//

import SwiftUI

extension PadDetailView {
    /// The API returns participants as a flat list of names with no role, so we
    /// infer who's who from the org directory: a participant whose name matches an
    /// org member is an interviewer, and anyone else is the candidate. When the
    /// directory hasn't loaded we can't tell them apart, so we fall back to an
    /// unlabeled list rather than guess.
    private var participantRoles: (interviewers: [String], candidates: [String])? {
        let memberNames = Set(directory.nameByEmail.values.map { $0.lowercased() })
        guard !memberNames.isEmpty else { return nil }

        var interviewers: [String] = []
        var candidates: [String] = []
        for name in pad.participants {
            if memberNames.contains(name.lowercased()) {
                interviewers.append(name)
            } else {
                candidates.append(name)
            }
        }
        return (interviewers, candidates)
    }

    var participantsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let roles = participantRoles {
                if !roles.candidates.isEmpty {
                    participantGroup(
                        title: roles.candidates.count == 1 ? "Candidate" : "Candidates",
                        names: roles.candidates, tint: .blue
                    )
                }
                if !roles.interviewers.isEmpty {
                    participantGroup(
                        title: roles.interviewers.count == 1 ? "Interviewer" : "Interviewers",
                        names: roles.interviewers, tint: .purple
                    )
                }
            } else {
                participantList(names: pad.participants, tint: .purple)
            }
        }
    }

    var participantsCard: some View {
        DetailSection(title: "Participants", systemImage: "person.2") {
            participantsContent
        }
    }

    private func participantGroup(
        title: LocalizedStringKey,
        names: [String],
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            participantList(names: names, tint: tint)
        }
    }

    /// A single column of compact participant rows. Rows hug their content instead of
    /// filling the detail pane, avoiding oversized backgrounds when a role has only
    /// one participant while still keeping names stacked predictably.
    private func participantList(names: [String], tint: Color) -> some View {
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
