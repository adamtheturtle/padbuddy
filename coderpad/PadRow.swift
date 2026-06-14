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
            rowContent
                .draggable(url)
                // Double-click opens the live pad in its own window via the existing
                // pad-browser scene, matching the macOS convention (single click
                // selects/previews in the detail pane, double click opens). The
                // enclosing List still drives single-click selection; a simultaneous
                // gesture runs alongside it rather than consuming the click.
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    AppRouter.requestOpenPadInBrowser(url)
                })
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
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
