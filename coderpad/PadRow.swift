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

/// The account a merged-list row belongs to, reduced to just what the row renders:
/// the name plus the avatar's tint and symbol. `nil` in the per-account lists, where
/// every row shares one account and naming it on each row would be noise.
/// `Equatable`/`Hashable` (a plain value type) so the memoized row body re-renders
/// when the account's identity changes, and so it can sit inside the `Hashable`
/// merged-row models. (#604)
struct RowAccount: Equatable, Hashable {
    let name: String
    let tint: Color
    let symbol: String?

    init(_ account: Account) {
        name = account.name
        tint = account.avatarTint
        symbol = account.iconSymbol
    }
}

/// Names the account a merged-list row came from, using the account's own avatar
/// (its tint + chosen symbol, or its initials) rather than a generic person glyph —
/// so multi-account users can tell at a glance which account a pad/question belongs
/// to, matching the avatar shown in the org/quota headers and the sidebar footer.
/// Styled like ``MetaLabel`` so it sits cleanly among the row's other metadata. (#604)
struct AccountMetaLabel: View {
    let account: RowAccount

    var body: some View {
        HStack(spacing: 4) {
            AvatarCircle(label: account.name, diameter: 14, tint: account.tint, symbol: account.symbol)
            Text(account.name).font(.caption)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(.secondary)
    }
}

/// The pad row's static title/metadata/date block — the bulk of the row's render
/// cost — memoized via `.equatable()` by ``PadRowHostableContent`` (#439). It holds no interaction
/// and no closures, so wrapping it in an `EquatableView` can't affect the row's
/// hit-testing or selection. `==` compares only the fields it renders, so a selection
/// change on an unchanged row skips rebuilding it.
private struct PadRowInfo: View, Equatable {
    let pad: Pad
    let isChanged: Bool
    let account: RowAccount?
    /// The owner's display name as already resolved by ``PadRowHostableContent`` against the org
    /// directory; compared in `==` so a directory update re-renders the block.
    let ownerDisplay: String
    /// Whether Increase Contrast is on, resolved by the parent (the `.equatable()` here
    /// would otherwise hide an environment read from memoization); compared in `==` so
    /// toggling the setting re-renders the dot (#616).
    let highContrast: Bool

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
            && lhs.account == rhs.account
            && lhs.ownerDisplay == rhs.ownerDisplay
            && lhs.highContrast == rhs.highContrast
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
                    if let account {
                        AccountMetaLabel(account: account)
                    }
                    if let language = pad.language, !language.isEmpty {
                        MetaLabel(text: language.languageDisplayName)
                    }
                    if pad.interviewType == .takeHome {
                        InterviewType.takeHome.chip
                    }
                }
                .lineLimit(1)
                Text(ownerDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
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
                // Under Increase Contrast a flat blue dot can blend into the row; add a
                // contrasting outline so it stays distinct for low-vision users (#616).
                .overlay {
                    if highContrast {
                        Circle().strokeBorder(Color.primary, lineWidth: 1)
                    }
                }
                .help("Updated since last refresh")
        }
    }

    private var accessibilityLabel: String {
        var parts = [pad.title.isEmpty ? pad.id : pad.title, pad.status.label]
        if let account { parts.append(account.name) }
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

private struct PadRowDateLabel: View {
    private static let relativeDateColumnWidth: CGFloat = 78

    let updated: Date?

    var body: some View {
        Group {
            if let updated {
                let labels = RelativeDateLabel.labels(for: updated)
                Text(labels.relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .help("Updated \(labels.tooltip)")
                    .frame(minWidth: Self.relativeDateColumnWidth, alignment: .trailing)
            } else {
                // A `minWidth` frame is a floor, not a ceiling: an empty, infinitely
                // flexible `Color.clear` inside one would grab all the row's leftover
                // width (it has `layoutPriority(1)`), squishing the title and dragging
                // the star left. Reserve exactly the column width so undated rows keep
                // the star/date column aligned with dated rows without expanding (#635).
                Color.clear
                    .frame(width: Self.relativeDateColumnWidth)
            }
        }
        .layoutPriority(1)
        .allowsHitTesting(false)
    }
}

/// Inline favorite toggle on a pad/question row, à la Mail's flag: filled once
/// pinned, faint otherwise so it stays available without row-hover state. The
/// button always occupies its slot, so rows don't shift as the pointer moves.
struct FavoriteStarButton: View {
    let isFavorite: Bool
    /// The row's display title, used only to phrase the accessibility label.
    let title: String
    let onToggle: () -> Void
    /// Bumped on each tap to drive a light haptic on the toggle (#611). Tied to the tap,
    /// not `isFavorite`, so a favorite changed elsewhere doesn't buzz this row.
    @State private var feedbackTrigger = 0

    var body: some View {
        Button {
            feedbackTrigger += 1
            onToggle()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.caption)
                .foregroundStyle(isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        // Light tactile confirmation on touch devices; a no-op on macOS (#611).
        .sensoryFeedback(.impact(flexibility: .soft), trigger: feedbackTrigger)
        // The caption-size star is a ~15pt target tuned for a pointer; on iPad it's
        // always shown (no hover) so it must also be comfortably tappable - give it a
        // 44pt hit area on touch (no-op on macOS, #597).
        .touchTarget()
        // Highlight the star under the iPad trackpad/Magic Keyboard pointer (#586).
        .pointerHoverEffect()
        // Keep non-favorite stars faint but present on macOS; row-hover state in
        // recycled hosting cells adds scroll-time churn on large lists (#633).
        #if os(macOS)
            .opacity(isFavorite ? 1 : 0.35)
        #else
            .opacity(1)
        #endif
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityLabel(isFavorite ? "Remove \(title) from Favorites"
            : "Add \(title) to Favorites")
    }
}

enum FastListRowMetrics {
    /// Fixed hosted-row height for the AppKit `FastList` backend. Pad and question rows
    /// are fixed-format rows; giving AppKit one stable intrinsic height avoids per-row
    /// automatic height discovery as `NSTableView` recycles SwiftUI hosting cells during
    /// fast scrolls (#633).
    static let macHeight: CGFloat = 64
}

extension View {
    /// Insets a `FastList` row's hosted content horizontally on the iPad backend.
    ///
    /// On iPad `FastList` is a native `List`, and its rows host their SwiftUI content
    /// ~18pt to the *left* of the cell that draws the selection highlight — the content
    /// frame ignores the column's leading layout margin, so the title slides under the
    /// sidebar's trailing edge (clipping its leading characters) and overhangs the
    /// highlight, which tracks the cell and so reads as a too-small pill. `listRowInsets`
    /// can't fix this: the plain list honors its vertical component but overrides the
    /// horizontal with the system layout margin, leaving the content where it was.
    /// Padding *inside* the hosted content is immune, so it's the lever that actually
    /// seats the text within the cell — clear of the sidebar and inside the highlight.
    /// A no-op on macOS, where `FastList` is `NSTableView`-backed and insets its own rows.
    ///
    /// The trailing `.containerRelativeFrame(.horizontal)` forces every row to fill the
    /// column. `FastList` wraps each iPad row in `.contextMenu`/`.draggable`, which proposes
    /// the content's *intrinsic* width to the row (so the inner `Spacer` never expands) and
    /// centers it — leaving rows with wider metadata (e.g. "Used 4×") sitting noticeably
    /// wider than narrower ones (e.g. "C++"). A plain `.frame(maxWidth: .infinity)` can't
    /// fix that: under an intrinsic-width proposal it just resolves to the ideal width.
    /// `containerRelativeFrame` ignores the proposal and sizes to the list's container
    /// width, so every row spans the full column and the metadata no longer drives width.
    @ViewBuilder
    func fastListRowInsets() -> some View {
        #if os(iOS)
            padding(.leading, 32).padding(.trailing, 24)
                .containerRelativeFrame(.horizontal, alignment: .leading)
        #else
            self
        #endif
    }

    @ViewBuilder
    func fixedFastListRowHeight() -> some View {
        #if os(macOS)
            frame(height: FastListRowMetrics.macHeight)
        #else
            self
        #endif
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
    /// The account this row belongs to, named on the row only in the merged list
    /// (`nil` in the per-account list). (#604)
    var rowAccount: RowAccount?
    var ownerDisplay: String
    /// Resolved by the list owner so the hosted row doesn't read the `@Observable`
    /// favorites store while `NSTableView` recycles cells during scroll (#633).
    var isFavorite: Bool
    var onToggleFavorite: () -> Void
    /// Read out here (not inside the `.equatable()` `PadRowInfo`, where it would be
    /// invisible to memoization) and threaded in as a compared value, so the
    /// recently-updated dot gains a contrasting outline under Increase Contrast (#616).
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            PadRowInfo(
                pad: pad,
                isChanged: isChanged,
                account: rowAccount,
                ownerDisplay: ownerDisplay,
                highContrast: contrast == .increased
            )
            .equatable()
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .layoutPriority(0)
            FavoriteStarButton(
                isFavorite: isFavorite,
                title: pad.title.isEmpty ? pad.id : pad.title,
                onToggle: onToggleFavorite
            )
            PadRowDateLabel(updated: pad.informativeUpdatedAt)
        }
        .padding(.vertical, 4)
        .padding(.trailing, 24)
        .fixedFastListRowHeight()
        .fastListRowInsets()
    }
}
