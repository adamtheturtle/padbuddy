//
//  PadRow.swift
//  coderpad
//

import SwiftUI

#if DEBUG
/// Per-selection render profiler (#439). Counts, per selection change, how many row
/// parent bodies vs memoized content bodies evaluate, plus the rough main-thread
/// stall. A macOS `List` rebuilds *every* row on each selection, so the memoized
/// count staying near zero is what proves `.equatable()` is doing its job. Wired up
/// from the list's `selectedIDs` `onChange`; DEBUG-only so it never ships in release.
@MainActor
enum SelectionProfiler {
    static var rowEvals = 0
    static var memoizedEvals = 0

    static func rowTick() { rowEvals += 1 }
    static func memoizedTick() { memoizedEvals += 1 }

    /// Call from the list's `selectedIDs` `onChange`. Resets the counters, then reads
    /// them back after the current update cycle drains to approximate the stall.
    static func selectionChanged() {
        let start = CFAbsoluteTimeGetCurrent()
        rowEvals = 0
        memoizedEvals = 0
        DispatchQueue.main.async {
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print(String(format: "⏱️ #439 selection stall ≈ %.1fms — row parent bodies = %d, memoized content bodies = %d",
                         ms, rowEvals, memoizedEvals))
        }
    }
}
#endif

/// A single pad row. A deliberately tiny non-equatable shell: it owns the hover
/// state, applies the row's hit-test shape, and embeds all the actual content in one
/// `.equatable()` child (``PadRowContent``).
///
/// Why this shape (#439): a macOS `List` isn't lazy — it rebuilds *every* row's body
/// on each selection change, so on a large list (thousands of pads) a single click
/// re-ran every row's full view tree and stalled the main thread for ~0.5s+. The win
/// is to skip that rebuild for unchanged rows via `.equatable()`. But wrapping the
/// *whole* row (tag/selection/hit-test included) in an `EquatableView` breaks
/// clicking: when the row update is skipped, the `.contentShape` hit area and the
/// double-click installer go stale, so rows stop registering clicks (commit e9746df
/// and later regressions). The fix is to keep everything click-related OUT of the
/// equatable boundary — `.contentShape` and `.onHover` here, and `.tag()` /
/// `.installsTableDoubleClick` / `.contextMenu` / `.swipeActions` applied by the list
/// outside the row — while ``PadRowContent`` (all the expensive text/badges/date/drag)
/// gets memoized. This shell body stays cheap enough to run for every row each pass.
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
    /// Whether this pad is pinned as a favorite, driving the trailing star.
    var isFavorite: Bool = false
    /// Toggles the pad's favorite state from the trailing star, mirroring QuestionRow.
    var onToggleFavorite: () -> Void = {}
    @Environment(\.orgDirectory) private var directory
    @State private var hovered = false

    var body: some View {
        #if DEBUG
        let _ = SelectionProfiler.rowTick()
        #endif
        // Resolve the owner name here (it depends on the observable directory) and
        // pass the resolved string in, so the content's equality covers both the
        // owner email and a directory update without holding the directory itself.
        PadRowContent(
            pad: pad,
            isChanged: isChanged,
            accountName: accountName,
            account: account,
            isFavorite: isFavorite,
            hovered: hovered,
            ownerDisplay: directory.display(pad.ownerEmail),
            onToggleFavorite: onToggleFavorite
        )
        .equatable()
        // Hit-test shape and hover stay OUTSIDE the equatable boundary so they're
        // re-applied every pass and never go stale on a skipped row. Make the entire
        // row frame hittable — including the trailing Spacer and empty space — so a
        // double-click anywhere on the row opens the pad, not just the title/badges
        // (#322).
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        // Single click selects/previews the pad in the detail pane; double click
        // opens it. Both are handled natively by the list (selection) and the
        // table's `doubleAction` (open), installed by the owning list — see
        // `TableDoubleClickProxy`. A SwiftUI tap gesture here would break the list's
        // own click-to-select (#324/#326).
    }
}

/// All of a pad row's content — the title/metadata/date block, the favorite star,
/// and the drag payload — memoized via `.equatable()` by ``PadRow`` (#439). `==`
/// compares only the fields the row actually renders, so a selection change on an
/// unchanged row skips rebuilding the whole subtree. The favorite-toggle closure is
/// excluded (closures aren't comparable and it's stable per row); `hovered` is
/// included so the trailing star still reveals itself on hover.
private struct PadRowContent: View, Equatable {
    let pad: Pad
    let isChanged: Bool
    let accountName: String?
    let account: UUID?
    let isFavorite: Bool
    let hovered: Bool
    /// The owner's display name as already resolved by ``PadRow`` against the org
    /// directory; compared in `==` so a directory update re-renders the row.
    let ownerDisplay: String
    let onToggleFavorite: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        let lpad = lhs.pad, rpad = rhs.pad
        return lpad.id == rpad.id
            && lpad.title == rpad.title
            && lpad.status == rpad.status
            && lpad.language == rpad.language
            && lpad.interviewType == rpad.interviewType
            // `informativeUpdatedAt` (not raw `updatedAt`) is what the row renders,
            // and it folds in `endedAt`, so compare it directly.
            && lpad.informativeUpdatedAt == rpad.informativeUpdatedAt
            && lhs.isChanged == rhs.isChanged
            && lhs.accountName == rhs.accountName
            && lhs.account == rhs.account
            && lhs.isFavorite == rhs.isFavorite
            && lhs.hovered == rhs.hovered
            && lhs.ownerDisplay == rhs.ownerDisplay
    }

    var body: some View {
        #if DEBUG
        let _ = SelectionProfiler.memoizedTick()
        #endif
        // Drag a pad out as its web URL, so it can be dropped into Slack, Mail,
        // Notes, etc. as a link that reopens the pad — and, when we know the owning
        // account, also carry an internal favorite payload so it can be dropped onto
        // the sidebar Favorites to pin it (#297). Only when the URL parses; otherwise
        // the row is simply not draggable.
        if let url = pad.webURL {
            if let account {
                row.draggable(PadDragPayload(
                    account: account,
                    id: pad.id,
                    title: pad.title.isEmpty ? pad.id : pad.title,
                    url: url
                ))
            } else {
                row.draggable(url)
            }
        } else {
            row
        }
    }

    private var row: some View {
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
                    Text(ownerDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                // Mirror the question row: the relative date sits on the trailing edge
                // in the same .caption/.secondary styling, rather than as a faint extra
                // line tucked under the metadata.
                if let updated = pad.informativeUpdatedAt {
                    // Cached labels rather than `.formatted` per render: on a large list
                    // this block is re-evaluated for every visible row on each selection
                    // pass, and `.formatted(.relative:)` is costly (#439).
                    let labels = RelativeDateLabel.labels(for: updated)
                    Text(labels.relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .help("Updated \(labels.tooltip)")
                }
            }
            // Read the title + metadata block as one VoiceOver element with a coherent
            // label, rather than stopping on each badge/label separately. The "changed"
            // indicator is a color-only dot, so fold it into the label as well; the
            // favorite star stays its own action.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            FavoriteStarButton(
                isFavorite: isFavorite,
                hovered: hovered,
                title: pad.title.isEmpty ? pad.id : pad.title,
                onToggle: onToggleFavorite
            )
        }
        .padding(.vertical, 4)
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
        parts.append(ownerDisplay)
        if let updated = pad.informativeUpdatedAt {
            parts.append("updated \(RelativeDateLabel.labels(for: updated).relative)")
        }
        if isChanged { parts.append("recently updated") }
        return parts.joined(separator: ", ")
    }
}

/// Inline favorite toggle on a pad/question row, à la Mail's flag: always shown
/// (filled) once pinned, and revealed faintly on hover otherwise so the resting list
/// stays uncluttered. The button always occupies its slot — only opacity changes on
/// hover — so rows don't shift as the pointer moves. Lives inside the memoized
/// content of each row (``PadRowContent`` / `QuestionRow`), so it's only rebuilt when
/// its own inputs change.
struct FavoriteStarButton: View {
    let isFavorite: Bool
    let hovered: Bool
    /// The row's display title, used only to phrase the accessibility label.
    let title: String
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.caption)
                .foregroundStyle(isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .opacity(isFavorite || hovered ? 1 : 0)
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityLabel(isFavorite ? "Remove \(title) from Favorites"
            : "Add \(title) to Favorites")
    }
}
