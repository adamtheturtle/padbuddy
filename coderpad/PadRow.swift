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
    /// The owning account's id, so a drag onto the sidebar can pin the pad to the
    /// right account (the originating one in the merged view, not the active one).
    var account: UUID?
    /// Select this row. Driven explicitly because the double-click gesture below
    /// suppresses the list's own click-to-select once it covers the whole row
    /// (#324); the owning list updates its selection set here.
    var onSelect: () -> Void = {}
    @Environment(\.orgDirectory) private var directory
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Drag a pad out as its web URL, so it can be dropped into Slack, Mail,
        // Notes, etc. as a link that reopens the pad — and, when we know the owning
        // account, also carry an internal favorite payload so it can be dropped onto
        // the sidebar Favorites to pin it (#297). Only when the URL parses; otherwise
        // the row is simply not draggable.
        if let url = pad.webURL {
            if let account {
                rowContent.draggable(PadDragPayload(
                    account: account,
                    id: pad.id,
                    title: pad.title.isEmpty ? pad.id : pad.title,
                    url: url
                ))
            } else {
                rowContent.draggable(url)
            }
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
            }
            Spacer(minLength: 8)
            // Mirror the question row: the relative date sits on the trailing edge in
            // the same .caption/.secondary styling, rather than as a faint extra line
            // tucked under the metadata.
            if let updated = pad.informativeUpdatedAt {
                Text(updated.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .help("Updated \(updated.formatted(date: .long, time: .shortened))")
            }
        }
        .padding(.vertical, 4)
        // Make the entire row frame hittable — including the trailing Spacer and
        // any empty space — so a double-click anywhere on the row opens the pad,
        // not just on the opaque title/badges (#322). Mirrors QuestionRow.
        .contentShape(Rectangle())
        // Read the whole row as one VoiceOver element with a coherent label,
        // rather than stopping on each badge/label separately. The "changed"
        // indicator is a color-only dot, so fold it into the label as well.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        // Single click selects/previews the pad in the detail pane, double click
        // opens it — the macOS convention, matching the explicit "open" buttons
        // elsewhere (#291). A tap gesture covering the whole row swallows the list's
        // own click-to-select on macOS (#324), so selection is driven explicitly
        // here; both gestures are simultaneous so a double click selects, then opens.
        .simultaneousGesture(TapGesture(count: 1).onEnded { onSelect() })
        .simultaneousGesture(TapGesture(count: 2).onEnded { openInWindow() })
    }

    /// Open the live pad on double-click, reusing the shared open path so it honors
    /// the user's "Open links" preference: the in-app `pad-browser` window, or the
    /// external browser (#291). Rows whose URL doesn't parse simply don't respond.
    @MainActor
    private func openInWindow() {
        guard let url = pad.webURL else { return }
        if BrowserSettings.openLinksIn == .external {
            BrowserSettings.openExternally(url)
        } else {
            openWindow(id: "pad-browser", value: url)
        }
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
