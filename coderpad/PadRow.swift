//
//  PadRow.swift
//  coderpad
//

import SwiftUI

#if DEBUG
    /// Per-selection render profiler (#439). Counts how many memoized row-content bodies
    /// (`PadRowInfo` / `QuestionRowInfo`) evaluate per selection change, plus the rough
    /// main-thread stall. With the `NSTableView`-backed `FastList` the table doesn't
    /// re-host rows on a selection change, so this should stay near zero — what's left of
    /// the stall is the detail-pane/selection cascade, not the list. Wired up from a
    /// list's selection `onChange`; DEBUG-only so it never ships in release.
    @MainActor
    enum SelectionProfiler {
        static var memoizedEvals = 0

        static func memoizedTick() {
            memoizedEvals += 1
        }

        /// Call from the list's selection `onChange`. Resets the counter, then reads it
        /// back after the current update cycle drains to approximate the stall.
        static func selectionChanged() {
            let start = CFAbsoluteTimeGetCurrent()
            memoizedEvals = 0
            DispatchQueue.main.async {
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
                print(String(format: "⏱️ #439 selection stall ≈ %.1fms — memoized row bodies = %d",
                             elapsedMs, memoizedEvals))
            }
        }
    }
#endif

/// The pad row's static title/metadata/date block — the bulk of the row's render
/// cost — memoized via `.equatable()` by ``PadRowHostableContent`` (#439). It holds no interaction
/// and no closures, so wrapping it in an `EquatableView` can't affect the row's
/// hit-testing or selection. `==` compares only the fields it renders, so a selection
/// change on an unchanged row skips rebuilding it.
private struct PadRowInfo: View, Equatable {
    let pad: Pad
    let isChanged: Bool
    let accountName: String?
    /// The owner's display name as already resolved by ``PadRowHostableContent`` against the org
    /// directory; compared in `==` so a directory update re-renders the block.
    let ownerDisplay: String

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
            && lhs.ownerDisplay == rhs.ownerDisplay
    }

    var body: some View {
        #if DEBUG
            // `let _` is required inside a ViewBuilder (a bare `_ =` isn't a valid
            // builder expression), so silence redundant_discardable_let here.
            // swiftlint:disable:next redundant_discardable_let
            let _ = SelectionProfiler.memoizedTick()
        #endif
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
/// hover — so rows don't shift as the pointer moves.
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
        // The caption-size star is a ~15pt target tuned for a pointer; on iPad it's
        // always shown (no hover) so it must also be comfortably tappable - give it a
        // 44pt hit area on touch (no-op on macOS, #597).
        .touchTarget()
        // macOS reveals the star on row hover to keep rows clean; iPad has no hover on
        // touch, so a non-favorite star would be invisible and un-tappable - always show it.
        #if os(macOS)
            .opacity(isFavorite || hovered ? 1 : 0)
        #else
            .opacity(1)
        #endif
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityLabel(isFavorite ? "Remove \(title) from Favorites"
            : "Add \(title) to Favorites")
    }
}

/// The pad row as hosted inside the `NSTableView`-backed `FastList` (#439). The
/// title/metadata block is `.allowsHitTesting(false)` so left-clicks pass straight
/// through the `NSHostingView` to the table for native selection; only the favorite
/// star stays hittable so it can be toggled. Selection, double-click, swipe, drag, and
/// the context menu are the table's job — so there's no `.contentShape`, `.draggable`,
/// or `.contextMenu` here (those would re-swallow the click).
struct PadRowHostableContent: View {
    let pad: Pad
    var isChanged: Bool = false
    var accountName: String?
    var ownerDisplay: String
    /// The owning account, used to read/toggle the favorite state.
    var account: UUID?
    /// Read live in `body` (it's `@Observable`) so toggling the star re-renders this
    /// hosted row immediately — the cell isn't otherwise re-created on a favorite
    /// change. Passing a static `Bool` left the star stuck (#439).
    var favoritePads: FavoritePadsStore
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            PadRowInfo(
                pad: pad,
                isChanged: isChanged,
                accountName: accountName,
                ownerDisplay: ownerDisplay
            )
            .equatable()
            .allowsHitTesting(false)
            FavoriteStarButton(
                isFavorite: favoritePads.isFavorite(pad.id, account: account),
                hovered: hovered,
                title: pad.title.isEmpty ? pad.id : pad.title,
                onToggle: {
                    guard let account else { return }

                    favoritePads.toggle(pad.id, account: account)
                }
            )
        }
        .padding(.vertical, 4)
        .onHover { hovered = $0 }
    }
}
