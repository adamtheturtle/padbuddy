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
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Participants", systemImage: "person.2")
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
                    participantGrid(names: pad.participants, tint: .purple)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func participantGroup(
        title: String,
        systemImage: String,
        names: [String],
        tint: Color,
        clickable: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            participantGrid(names: names, tint: tint, clickable: clickable)
        }
    }

    private func participantGrid(names: [String], tint: Color, clickable: Bool = false) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(names, id: \.self) { name in
                // Interviewers are org members, so we can resolve their email and
                // make the row a button that jumps to their pads, mirroring the
                // Organization users list. Candidates aren't members, so they
                // stay as plain rows.
                if clickable, let email = memberEmail(forName: name) {
                    Button {
                        AppNavigation.shared.showPads(PadsRequest(ownerEmail: email))
                    } label: {
                        participantRow(name: name, tint: tint)
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Show pads from \(name)")
                } else {
                    participantRow(name: name, tint: tint)
                }
            }
        }
    }

    private func participantRow(name: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            AvatarCircle(label: name, diameter: 26, tint: tint)
            Text(name).font(.callout)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.subtleStroke.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// The org email for a participant matched by display name, used to turn an
    /// interviewer row into a link to their pads. Names can collide in theory, so
    /// this returns the first match; `nil` when no member carries that name.
    private func memberEmail(forName name: String) -> String? {
        let lowered = name.lowercased()
        return directory.nameByEmail.first { $0.value.lowercased() == lowered }?.key
    }
}
