//
//  PadRow.swift
//  coderpad
//

import SwiftUI

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var expandsForDynamicType: Bool {
        #if os(iOS)
            dynamicTypeSize.isAccessibilitySize
        #else
            false
        #endif
    }

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
                    .foregroundStyle(Color.fastListRowPrimaryLabel)
                    .lineLimit(expandsForDynamicType ? 2 : 1)
                metadata
                Text(ownerDisplay)
                    .font(.caption)
                    .foregroundStyle(Color.fastListRowSecondaryLabel)
                    .lineLimit(expandsForDynamicType ? 2 : 1)
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

    @ViewBuilder
    private var metadata: some View {
        if expandsForDynamicType {
            VStack(alignment: .leading, spacing: 4) {
                metadataItems
            }
        } else {
            HStack(spacing: 8) {
                metadataItems
            }
            .lineLimit(1)
            .clipsMetadataOverflow()
        }
    }

    @ViewBuilder
    private var metadataItems: some View {
        StateBadge(state: pad.status)
        if let account {
            AccountMetaLabel(account: account)
        }
        if let language = pad.language, !language.isEmpty {
            MetaLabel(text: language.coderPadLanguageDisplayName)
        }
        if pad.interviewType == .takeHome {
            InterviewType.takeHome.chip
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
            parts.append(language.coderPadLanguageDisplayName)
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
    let updated: Date?

    var body: some View {
        Group {
            if let updated {
                let labels = RelativeDateLabel.labels(for: updated)
                Text(labels.relative)
                    .font(.caption)
                    .foregroundStyle(Color.fastListRowSecondaryLabel)
                    .lineLimit(1)
                    .fixedSize()
                    .help("Updated \(labels.tooltip)")
                    .frame(minWidth: FastListRowMetrics.dateColumnWidth, alignment: .trailing)
            } else {
                // A `minWidth` frame is a floor, not a ceiling: an empty, infinitely
                // flexible `Color.clear` inside one would grab all the row's leftover
                // width (it has `layoutPriority(1)`), squishing the title and dragging
                // the star left. Reserve exactly the column width so undated rows keep
                // the star/date column aligned with dated rows without expanding (#635).
                Color.clear
                    .frame(width: FastListRowMetrics.dateColumnWidth)
            }
        }
        .layoutPriority(1)
        .allowsHitTesting(false)
    }
}

/// Inline favorite toggle on a pad/question row, à la Mail's flag: visible when pinned
/// or when the pointer is over the row. The button always occupies its slot, so rows
/// don't shift as the pointer moves.
struct FavoriteStarButton: View {
    let isFavorite: Bool
    /// The row's display title, used only to phrase the accessibility label.
    let title: String
    let onToggle: () -> Void
    var isRowHovered = false
    /// Bumped on each tap to drive a light haptic on the toggle (#611). Tied to the tap,
    /// not `isFavorite`, so a favorite changed elsewhere doesn't buzz this row.
    @State private var feedbackTrigger = 0
    var body: some View {
        Button {
            feedbackTrigger += 1
            onToggle()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(starFont)
                .foregroundStyle(isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: minimumTouchTarget, height: minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Light tactile confirmation on touch devices; a no-op on macOS (#611).
        .sensoryFeedback(.impact(flexibility: .soft), trigger: feedbackTrigger)
        // The star is small visually, but its layout slot is the 44pt touch minimum on
        // touch devices so the tappable area matches where the control appears.
        .touchTarget()
        // Highlight the star under the iPad trackpad/Magic Keyboard pointer (#586).
        .pointerHoverEffect()
        #if os(macOS)
            .opacity(isFavorite || isRowHovered ? 1 : 0)
        #else
            .opacity(1)
        #endif
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityLabel(isFavorite ? "Remove \(title) from Favorites"
                : "Add \(title) to Favorites")
    }

    private var starFont: Font {
        #if os(iOS)
            .body
        #else
            .caption
        #endif
    }

    private var minimumTouchTarget: CGFloat {
        #if os(iOS)
            44
        #else
            18
        #endif
    }
}

enum FastListRowMetrics {
    /// Fixed width of the right-aligned trailing date column shared by pad and question
    /// rows. Reserving one common width keeps the favorite star seated in the same
    /// horizontal slot across both lists (star, then date), so the star doesn't jump
    /// when switching between Pads and Questions (#635, #650).
    static let dateColumnWidth: CGFloat = 78

    /// Fixed hosted-row height for the AppKit `FastList` backend. Pad and question rows
    /// are fixed-format rows; giving AppKit one stable intrinsic height avoids per-row
    /// automatic height discovery as `NSTableView` recycles SwiftUI hosting cells during
    /// fast scrolls (#633).
    static let macHeight: CGFloat = 64
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
    @State private var isHovering = false
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if usesInlineAccountTintRail, let rowAccount {
                AccountTintRail(account: rowAccount)
            }
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
            if usesTrailingFavoriteAction {
                PadRowDateLabel(updated: pad.informativeUpdatedAt)
                favoriteButton
            } else {
                favoriteButton
                PadRowDateLabel(updated: pad.informativeUpdatedAt)
            }
        }
        .padding(.vertical, 4)
        .padRowTrailingActionInset(enabled: !usesTrailingFavoriteAction)
        .fixedFastListRowHeight()
        .accountTintRailOverlay(rowAccount, enabled: !usesInlineAccountTintRail)
        .fastListRowInsets()
        #if os(macOS)
            .onHover { isHovering = $0 }
            .onChange(of: hoverIdentity) { _, _ in isHovering = false }
        #endif
    }

    private var favoriteButton: some View {
        FavoriteStarButton(
            isFavorite: isFavorite,
            title: pad.title.isEmpty ? pad.id : pad.title,
            onToggle: onToggleFavorite,
            isRowHovered: isHovering
        )
    }

    private var hoverIdentity: FavoriteRowHoverIdentity {
        FavoriteRowHoverIdentity(itemID: pad.id, account: rowAccount)
    }

    private var usesTrailingFavoriteAction: Bool {
        #if os(iOS)
            horizontalSizeClass == .compact
        #else
            false
        #endif
    }

    private var usesInlineAccountTintRail: Bool {
        #if os(iOS)
            horizontalSizeClass == .compact
        #else
            false
        #endif
    }
}
