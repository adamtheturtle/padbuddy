//
//  PadRow.swift
//  coderpad
//

import SwiftUI

struct PadRow: View, Equatable {
    /// Skip re-evaluating a row's body when its inputs are unchanged. A `List`
    /// builds a view for every row, and a selection change re-runs the list body, so
    /// without this SwiftUI re-rendered all N rows (each doing Date formatting) on
    /// every click — ~1.5s on a 2500-pad list. The favorite-toggle closure is excluded
    /// (closures aren't comparable and it's stable per row).
    static func == (lhs: Self, rhs: Self) -> Bool {
        // Compare only the fields this row actually renders, not the whole `Pad`
        // (which carries participant/environment arrays). On a 2500-row list this
        // `==` runs for every row on every selection pass, so a full struct compare —
        // including those arrays — was a large share of the per-pass cost.
        let lpad = lhs.pad, rpad = rhs.pad
        return lpad.id == rpad.id
            && lpad.title == rpad.title
            && lpad.status == rpad.status
            && lpad.language == rpad.language
            && lpad.ownerEmail == rpad.ownerEmail
            && lpad.interviewType == rpad.interviewType
            && lpad.updatedAt == rpad.updatedAt
            && lhs.isChanged == rhs.isChanged
            && lhs.accountName == rhs.accountName
            && lhs.account == rhs.account
            && lhs.isFavorite == rhs.isFavorite
    }

    let pad: Pad
    var isChanged: Bool = false
    /// The owning account's name, shown as a badge only in the combined "All
    /// Accounts" view so each row says which account it came from. `nil` in the
    /// normal single-account list, where the badge would be noise.
    var accountName: String?
    /// The owning account's id, so a drag onto the sidebar can pin the pad to the
    /// right account (the originating one in the merged view, not the active one).
    var account: UUID?
    /// Whether this pad is pinned as a favorite, driving the trailing star.
    var isFavorite: Bool = false
    /// Toggles the pad's favorite state from the trailing star, mirroring QuestionRow.
    var onToggleFavorite: () -> Void = {}
    @Environment(\.orgDirectory) private var directory
    @State private var hovered = false

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
        // Mirror QuestionRow's structure so the two lists read at the same height:
        // an outer center-aligned HStack holds the top-aligned title/metadata block
        // (with the trailing date) and, centered against the full row height, the
        // favorite star as a row-level action.
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                // A small leading dot marking activity since the row was last opened,
                // in a fixed-width gutter so titles stay aligned whether or not a row
                // has it. The owner is named in the subtitle below.
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
                // Mirror the question row: the relative date sits on the trailing edge
                // in the same .caption/.secondary styling, rather than as a faint extra
                // line tucked under the metadata.
                if let updated = pad.informativeUpdatedAt {
                    Text(updated.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .help("Updated \(updated.formatted(date: .long, time: .shortened))")
                }
            }
            // Read the title + metadata block as one VoiceOver element with a coherent
            // label, rather than stopping on each badge/label separately. The "changed"
            // indicator is a color-only dot, so fold it into the label as well; the
            // favorite star stays its own action.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            favoriteButton
        }
        .padding(.vertical, 4)
        // Make the entire row frame hittable — including the trailing Spacer and
        // any empty space — so a double-click anywhere on the row opens the pad,
        // not just on the opaque title/badges (#322). Mirrors QuestionRow.
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        // Single click selects/previews the pad in the detail pane; double click
        // opens it. Both are handled natively by the list (selection) and the
        // table's `doubleAction` (open), installed by the owning list — see
        // `TableDoubleClickProxy`. A SwiftUI tap gesture here would break the list's
        // own click-to-select (#324/#326).
    }

    /// Inline favorite toggle on the trailing edge, matching QuestionRow's star:
    /// always shown (filled) once the pad is pinned, and revealed faintly on hover
    /// otherwise so the resting list stays uncluttered. The button always occupies
    /// its slot — only opacity changes on hover — so rows don't shift on hover.
    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.caption)
                .foregroundStyle(isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .opacity(isFavorite || hovered ? 1 : 0)
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityLabel(isFavorite ? "Remove \(pad.title.isEmpty ? pad.id : pad.title) from Favorites"
            : "Add \(pad.title.isEmpty ? pad.id : pad.title) to Favorites")
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
