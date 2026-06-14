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
        // Drag a pad out as its web URL, so it can be dropped into Slack, Mail,
        // Notes, etc. as a link that reopens the pad. Only when the URL parses;
        // otherwise the row is simply not draggable. Drop-in is tracked separately.
        if let url = pad.webURL {
            rowContent.draggable(url)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // A small leading dot marking activity since the row was last opened,
            // in a fixed-width gutter so titles stay aligned whether or not a row
            // has it. Replaces the owner-initials avatar this row used to show; the
            // owner is still named in the subtitle below.
            changedIndicator
                .frame(width: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(pad.title.isEmpty ? pad.id : pad.title)
                    .font(.callout.weight(.medium))
                    // Full contrast: the row's VStack tints everything .tertiary for
                    // the secondary metadata, but the title is the primary content and
                    // was getting dragged down to the same faint grey, which read as
                    // hard-to-see in both light and dark mode.
                    .foregroundStyle(.primary)
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

    /// The "updated since last refresh" dot, shown only when the pad changed since
    /// the user last opened it. Color-only, so its meaning is folded into the row's
    /// accessibility label (see `accessibilityLabel`) rather than announced on its own.
    @ViewBuilder
    private var changedIndicator: some View {
        if isChanged {
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
                .help("Updated since last refresh")
        }
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
