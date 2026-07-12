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

    var participantsCard: some View {
        DetailSection(title: "Participants", systemImage: "person.2") {
            VStack(alignment: .leading, spacing: 12) {
                if let roles = participantRoles {
                    if !roles.candidates.isEmpty {
                        participantGroup(
                            title: roles.candidates.count == 1 ? "Candidate" : "Candidates",
                            systemImage: "person.crop.circle.badge.questionmark",
                            names: roles.candidates, tint: .blue
                        )
                    }
                    if !roles.interviewers.isEmpty {
                        participantGroup(
                            title: roles.interviewers.count == 1 ? "Interviewer" : "Interviewers",
                            systemImage: "person.crop.circle.badge.checkmark",
                            names: roles.interviewers, tint: .purple, clickable: true
                        )
                    }
                } else {
                    participantList(names: pad.participants, tint: .purple)
                }
            }
        }
    }

    private func participantGroup(
        title: LocalizedStringKey,
        systemImage: String,
        names: [String],
        tint: Color,
        clickable: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            participantList(names: names, tint: tint, clickable: clickable)
        }
    }

    /// A single column of compact participant rows. Rows hug their content instead of
    /// filling the detail pane, avoiding oversized backgrounds when a role has only
    /// one participant while still keeping names stacked predictably.
    private func participantList(names: [String], tint: Color, clickable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Key by position rather than the name itself: two participants can
            // share a display name (or the same name can appear twice), and
            // `id: \.self` would then hand the list duplicate IDs.
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                // Interviewers are org members, so we can resolve their email and
                // make the row a button that jumps to their pads, mirroring the
                // Organization users list. Candidates aren't members, so they
                // stay as plain rows.
                if clickable, let email = memberEmail(forName: name) {
                    Button {
                        AppNavigation.shared.showPads(PadsRequest(ownerEmail: email))
                    } label: {
                        participantRow(name: name, tint: tint, clickable: true)
                            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                        .pointerStyle(.link)
                    #endif
                        .help("Show pads from \(name)")
                } else {
                    participantRow(name: name, tint: tint)
                }
            }
        }
    }

    private func participantRow(name: String, tint: Color, clickable: Bool = false) -> some View {
        HStack(spacing: 8) {
            AvatarCircle(label: name, diameter: 26, tint: tint)
            Text(name)
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: 260, alignment: .leading)
            // A trailing chevron marks the row as a link to the member's pads, so
            // a clickable interviewer reads differently from a plain candidate row
            // that only carries the same name and avatar.
            if clickable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    // Purely a visual affordance: the row is already a button with a
                    // "Show pads from …" help/hint, so VoiceOver shouldn't read the
                    // bare symbol name on top of the participant's name.
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.subtleStroke.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    /// The org email for a participant matched by display name, used to turn an
    /// interviewer row into a link to their pads. Names can collide in theory, so
    /// this returns the first match; `nil` when no member carries that name.
    func memberEmail(forName name: String) -> String? {
        let lowered = name.lowercased()
        return directory.nameByEmail.first { $0.value.lowercased() == lowered }?.key
    }
}
