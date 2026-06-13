//
//  PadRow.swift
//  coderpad
//

import SwiftUI

struct PadRow: View {
    let pad: Pad
    var isChanged: Bool = false
    /// The owning account's name, shown as a badge only in the combined "All
    /// Accounts" view so each row says which account it came from. `nil` in the
    /// normal single-account list, where the badge would be noise.
    var accountName: String?
    @Environment(\.orgDirectory) private var directory

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                AvatarCircle(label: directory.display(pad.ownerEmail), diameter: 30)
                if isChanged {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Color.cardBackground, lineWidth: 2))
                        .offset(x: 2, y: -2)
                        .help("Updated since last refresh")
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(pad.title.isEmpty ? pad.id : pad.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    StateBadge(state: pad.status)
                    if let accountName {
                        MetaLabel(text: accountName, systemImage: "person.crop.circle")
                    }
                    if let language = pad.language, !language.isEmpty {
                        MetaLabel(text: language.languageDisplayName)
                    }
                    if pad.interviewType == .takeHome {
                        InterviewType.takeHome.chip
                    }
                }
                Text(directory.display(pad.ownerEmail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let updated = pad.informativeUpdatedAt {
                    Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        // Read the whole row as one VoiceOver element with a coherent label,
        // rather than stopping on each badge/label separately. The "changed"
        // indicator is a color-only dot, so fold it into the label as well.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [pad.title.isEmpty ? pad.id : pad.title, pad.status.label]
        if let accountName { parts.append(accountName) }
        if let language = pad.language, !language.isEmpty {
            parts.append(language.languageDisplayName)
        }
        if pad.interviewType == .takeHome { parts.append("Take-home") }
        parts.append(directory.display(pad.ownerEmail))
        if let updated = pad.informativeUpdatedAt {
            parts.append("updated \(updated.formatted(.relative(presentation: .named)))")
        }
        if isChanged { parts.append("recently updated") }
        return parts.joined(separator: ", ")
    }
}
