//
//  PadRow+Layout.swift
//  coderpad
//
//  Row-layout view helpers shared by the pad and question `FastList` rows
//  (metadata clipping, per-platform insets, fixed height, manual selection).
//  Split out of `PadRow.swift` to keep each file under the length limit.
//

import FastList
import SwiftUI

extension View {
    /// Bounds a row's metadata line to the width the row actually allots, so it can never
    /// force the whole row wider than its list column, while letting a compressible chip
    /// (the account name) truncate cleanly instead of being clipped mid-glyph.
    ///
    /// The short chips (``StateBadge``/``MetaLabel``/``Chip``) are each `.fixedSize` so they
    /// stay whole rather than truncating to "Pyth…". The side effect is that a row carrying
    /// more metadata than fits (an extra language plus a "Used N×" chip, say) has a *minimum*
    /// width larger than the iPad list column. A frame - including the `containerRelativeFrame`
    /// that seats each row in its column - can't shrink below its content's minimum, so such a
    /// row would otherwise lay out at its intrinsic width: its trailing star/date get shoved
    /// out of view, and in a `NavigationSplitView` content column the whole row drifts off the
    /// shared leading edge (the "middle row too far left" report).
    ///
    /// `minWidth: 0` makes this line *report* zero minimum width - leaving its natural height,
    /// so row height and Dynamic Type are untouched - so the row can never be forced wider than
    /// its column. Unlike a fixed `frame(width: 0)`, the flexible frame proposes the row's
    /// *actual* allotted width down to the chips, so the one compressible chip (the free-form
    /// ``AccountMetaLabel`` name) truncates with a tail ellipsis to fit; `clipped()` then trims
    /// any residual overflow from the whole-width fixed chips. A no-op when the metadata fits.
    func clipsMetadataOverflow() -> some View {
        frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
    }

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
            modifier(FastListRowInsetsModifier())
        #else
            self
        #endif
    }

    @ViewBuilder
    func fixedFastListRowHeight() -> some View {
        #if os(macOS)
            frame(minHeight: FastListRowMetrics.macHeight)
        #else
            self
        #endif
    }

    @ViewBuilder
    func accountTintRailOverlay(_ account: RowAccount?, enabled: Bool) -> some View {
        if enabled, let account {
            modifier(AccountTintRailOverlayModifier(account: account))
        } else {
            self
        }
    }

    @ViewBuilder
    func padRowTrailingActionInset(enabled: Bool) -> some View {
        #if os(iOS)
            if enabled {
                padding(.trailing, 24)
            } else {
                self
            }
        #else
            padding(.trailing, 24)
        #endif
    }

    @ViewBuilder
    func fastListRowManualSelection<ID: Hashable>(id: ID, selection: Binding<Set<ID>>) -> some View {
        #if os(iOS)
            contentShape(Rectangle())
                .selectionDisabled()
                .focusEffectDisabled()
                // A regular tap gesture yields to embedded buttons/accessories.
                // The previous simultaneous gesture selected and navigated the row
                // in addition to performing the control's own action (#2747).
                .onTapGesture {
                    selection.wrappedValue = [id]
                }
        #else
            self
        #endif
    }
}

nonisolated enum FastListRowInsetPolicy {
    static func horizontal(compact: Bool, accessibilitySize: Bool) -> (leading: CGFloat, trailing: CGFloat) {
        if accessibilitySize { return (16, 12) }
        if compact { return (20, 16) }
        return (32, 24)
    }

    static func tintRailReservation(compact: Bool, accessibilitySize: Bool) -> CGFloat {
        if accessibilitySize { return 8 }
        if compact { return 8 }
        return 12
    }
}

private struct AccountTintRailOverlayModifier: ViewModifier {
    let account: RowAccount
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let reservation = FastListRowInsetPolicy.tintRailReservation(
            compact: horizontalSizeClass == .compact,
            accessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
        content
            .padding(.leading, reservation)
            .overlay(alignment: .leading) {
                AccountTintRail(account: account)
            }
    }
}

#if os(iOS)
    private struct FastListRowInsetsModifier: ViewModifier {
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        func body(content: Content) -> some View {
            let insets = FastListRowInsetPolicy.horizontal(
                compact: horizontalSizeClass == .compact,
                accessibilitySize: dynamicTypeSize.isAccessibilitySize
            )
            content
                .padding(.leading, insets.leading)
                .padding(.trailing, insets.trailing)
                .containerRelativeFrame(.horizontal, alignment: .leading)
        }
    }
#endif
