//
//  PadRow.swift
//  coderpad
//

import SwiftUI

/// The pad row's static title/metadata/date block — the bulk of the row's render
/// cost — memoized via `.equatable()` by ``PadRowHostableContent`` (#439). It holds no interaction
/// and no closures, so wrapping it in an `EquatableView` can't affect the row's
/// hit-testing or selection. `==` compares only the fields it renders.
private struct PadRowInfo: View, Equatable {
    let pad: Pad
    let account: RowAccount?
    /// The owner's display name as already resolved by ``PadRowHostableContent`` against the org
    /// directory; compared in `==` so a directory update re-renders the block.
    let ownerDisplay: String
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
            && lhs.account == rhs.account
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
            VStack(alignment: .leading, spacing: 5) {
                Text(pad.displayListTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.fastListRowPrimaryLabel)
                    .lineLimit(expandsForDynamicType ? 2 : 1)
                metadata
                Text(ownerDisplay)
                    .font(.caption)
                    .foregroundStyle(Color.fastListRowSecondaryLabel.opacity(0.88))
                    .lineLimit(expandsForDynamicType ? 2 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        // Read the title + metadata block as one VoiceOver element with a coherent
        // label, rather than stopping on each badge/label separately. The favorite
        // star stays its own action.
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

    private var accessibilityLabel: String {
        var parts = [pad.displayListTitle, pad.status.label]
        if let account { parts.append(account.name) }
        if let language = pad.language, !language.isEmpty {
            parts.append(language.coderPadLanguageDisplayName)
        }
        if pad.interviewType == .takeHome { parts.append("Take-home") }
        parts.append(ownerDisplay)
        if let updated = pad.informativeUpdatedAt {
            parts.append("updated \(RelativeDateLabel.labels(for: updated).relative)")
        }
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
                    .foregroundStyle(Color.fastListRowSecondaryLabel.opacity(0.88))
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
        buttonWithFeedback
            // The star is small visually, but its layout slot is the 44pt touch minimum on
            // touch devices so the tappable area matches where the control appears.
            .touchTarget()
            // Highlight the star under the iPad trackpad/Magic Keyboard pointer (#586).
            .pointerHoverEffect()
        #if os(macOS)
            // While invisible, the star must be neither clickable nor a VoiceOver
            // stop: an invisible-but-live control toggled favorites on stray
            // clicks and gave VoiceOver an undiscoverable element (#1711). The
            // row's context menu still offers the favorite toggle throughout.
            .opacity(isFavorite || isRowHovered ? 1 : 0)
            .allowsHitTesting(isFavorite || isRowHovered)
            .accessibilityHidden(!(isFavorite || isRowHovered))
        #else
            .opacity(1)
        #endif
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityLabel(isFavorite ? "Remove \(title) from Favorites"
                : "Add \(title) to Favorites")
    }

    @ViewBuilder
    private var buttonWithFeedback: some View {
        let button = Button {
            feedbackTrigger += 1
            onToggle()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(starFont)
                .foregroundStyle(starStyle)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
                .frame(width: minimumTouchTarget, height: minimumTouchTarget)
                .background(starBackground, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)

        // Light tactile confirmation on touch devices; unavailable before visionOS 26 (#611).
        #if os(visionOS)
            if #available(visionOS 26.0, *) {
                button.sensoryFeedback(.impact(flexibility: .soft), trigger: feedbackTrigger)
            } else {
                button
            }
        #else
            button.sensoryFeedback(.impact(flexibility: .soft), trigger: feedbackTrigger)
        #endif
    }

    private var starFont: Font {
        #if os(iOS)
            .body
        #else
            .caption
        #endif
    }

    private var starStyle: AnyShapeStyle {
        if isFavorite { return AnyShapeStyle(.yellow) }
        if isRowHovered { return AnyShapeStyle(Color.fastListRowPrimaryLabel) }
        return AnyShapeStyle(.secondary)
    }

    private var starBackground: Color {
        if isFavorite { return .yellow.opacity(0.16) }
        if isRowHovered { return .secondary.opacity(0.10) }
        return .clear
    }

    private var minimumTouchTarget: CGFloat {
        #if os(iOS)
            44
        #else
            18
        #endif
    }
}

extension Pad {
    /// The row's primary label: the trimmed title, or the slug when the title is
    /// empty *or whitespace-only* — an all-whitespace API title used to render a
    /// blank primary label and blank favorite/accessibility text (#1713).
    var displayListTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id : trimmed
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
    /// The account this row belongs to, named on the row only in the merged list
    /// (`nil` in the per-account list). (#604)
    var rowAccount: RowAccount?
    var ownerDisplay: String
    /// Resolved by the list owner so the hosted row doesn't read the `@Observable`
    /// favorites store while `NSTableView` recycles cells during scroll (#633).
    var isFavorite: Bool
    var onToggleFavorite: () -> Void
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
                account: rowAccount,
                ownerDisplay: ownerDisplay
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
            title: pad.displayListTitle,
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
