//
//  DesignSystem+Filters.swift
//  coderpad
//

import SwiftUI

#if canImport(Flow)
    import Flow
#endif

// MARK: - Filter bar width measurement

/// Carries the natural (unclipped) width of a filter bar up the view tree so the
/// enclosing split-view column can refuse to shrink below it. Reduces to the
/// widest reporter, and never below a sensible floor.
struct FilterBarWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 380
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Measures this view's laid-out width and reports it via `FilterBarWidthKey`.
    /// Attach either to a horizontally-scrolling filter bar's content (so the
    /// measured value is the chips' natural row width) or to each individual chip
    /// in a wrapping filter bar — because the key reduces by `max`, the per-chip
    /// case yields the widest single chip, the right floor for a bar that wraps.
    func measuresFilterBarWidth() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: FilterBarWidthKey.self, value: proxy.size.width)
            }
        )
    }
}

// MARK: - Section result count

/// Carries a list section's result-count summary (e.g. "12 pads") up the view tree
/// so `MainSplit` can show it as the window's navigation subtitle, directly beneath
/// the section title in the toolbar, instead of as an inline bar above the list.
/// Reduces to the last non-empty reporter so the visible section's count wins and
/// sections without a count (Organization, Quota) leave it empty.
struct SectionCountKey: PreferenceKey {
    static let defaultValue: String = ""
    static func reduce(value: inout String, nextValue: () -> String) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

extension View {
    /// Reports this section's result-count summary via `SectionCountKey` so the
    /// enclosing split view can render it as the toolbar subtitle. Pass an empty
    /// string when there's nothing to show (e.g. an empty or still-loading list).
    func reportsSectionCount(_ summary: String) -> some View {
        preference(key: SectionCountKey.self, value: summary)
    }
}

// MARK: - Sidebar row width measurement

/// Carries the widest sidebar row's natural (unclipped) label width up the view
/// tree so the sidebar column can size its minimum to fit the longest label,
/// rather than relying on a hand-tuned constant that breaks when labels or the
/// row font change. Reduces to the widest reporter.
struct SidebarRowWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Reports the natural width of `label` rendered at the sidebar row font via
    /// `SidebarRowWidthKey`. Measures a hidden, `fixedSize` copy of the text so the
    /// reported width is the *untruncated* width even though the visible row is
    /// line-limited — attach to each row and the key's `max` yields the widest.
    func measuresSidebarRowWidth(_ label: LocalizedStringKey) -> some View {
        background(
            Text(label)
                .font(.body)
                .fixedSize()
                .hidden()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: SidebarRowWidthKey.self, value: proxy.size.width)
                    }
                )
        )
    }
}

// MARK: - Flow layout

/// Arranges its subviews left-to-right, wrapping to a new line whenever the next
/// subview would overflow the available width. Lets a row of filter chips reflow
/// onto multiple lines as its container narrows, instead of being clipped or
/// forcing a horizontal scroll.
///
/// Backed by the Flow package's `HFlow` when that dependency is present (#391); the
/// built-in `FallbackFlowLayout` below keeps the app building without it — the same
/// `#if canImport` pattern Sparkle (#28) uses to sidestep the GUI-only package add.
/// Call sites are identical either way; only the engine swaps. `spacing` is the
/// gap between items in a row, `lineSpacing` the gap between rows.
struct FlowLayout<Content: View>: View {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if canImport(Flow)
            // Left-aligned rows with items vertically centred (matching the fallback),
            // mapping our item/line spacing onto HFlow's horizontal/vertical spacing.
            HFlow(horizontalAlignment: .leading,
                  verticalAlignment: .center,
                  horizontalSpacing: spacing,
                  verticalSpacing: lineSpacing) {
                content()
            }
        #else
            FallbackFlowLayout(spacing: spacing, lineSpacing: lineSpacing) {
                content()
            }
        #endif
    }
}

#if !canImport(Flow)
    /// The no-dependency fallback flow layout, used until the Flow package is added
    /// (#391). Arranges subviews left-to-right, wrapping when the next would overflow
    /// the available width, with each item vertically centred within its row.
    struct FallbackFlowLayout: Layout {
        var spacing: CGFloat = 8
        var lineSpacing: CGFloat = 8

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout Void) -> CGSize {
            let maxWidth = proposal.width ?? .infinity
            var xPos: CGFloat = 0
            var yPos: CGFloat = 0
            var rowHeight: CGFloat = 0
            var widestRow: CGFloat = 0
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if xPos > 0, xPos + size.width > maxWidth {
                    widestRow = max(widestRow, xPos - spacing)
                    xPos = 0
                    yPos += rowHeight + lineSpacing
                    rowHeight = 0
                }
                xPos += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
            widestRow = max(widestRow, xPos - spacing)
            let width = maxWidth.isFinite ? maxWidth : widestRow
            return CGSize(width: max(0, width), height: yPos + rowHeight)
        }

        func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout Void) {
            // Group subviews into rows first, then place each item vertically centred
            // within its row. A single forward pass can't centre because a row's full
            // height isn't known until it's complete — so a short control (e.g. a
            // borderless Save button) would top-align against the taller capsule chips
            // and appear to float high.
            var rows: [[(index: Int, size: CGSize)]] = []
            var current: [(index: Int, size: CGSize)] = []
            var xPos = bounds.minX
            for (index, subview) in subviews.enumerated() {
                let size = subview.sizeThatFits(.unspecified)
                if xPos > bounds.minX, xPos + size.width > bounds.maxX {
                    rows.append(current)
                    current = []
                    xPos = bounds.minX
                }
                current.append((index, size))
                xPos += size.width + spacing
            }
            if !current.isEmpty { rows.append(current) }

            var yPos = bounds.minY
            for row in rows {
                let rowHeight = row.map(\.size.height).max() ?? 0
                var rowX = bounds.minX
                for item in row {
                    let yOffset = (rowHeight - item.size.height) / 2
                    subviews[item.index].place(
                        at: CGPoint(x: rowX, y: yPos + yOffset),
                        anchor: .topLeading,
                        proposal: ProposedViewSize(item.size)
                    )
                    rowX += item.size.width + spacing
                }
                yPos += rowHeight + lineSpacing
            }
        }
    }
#endif

// The filter-chip view components (SearchableFilterChip, ChipLabel, the
// chipClearOverlay helper, and the searchable popover) now live alongside the
// other chips in FilterChips.swift. This file keeps the filter-bar layout and
// measurement infrastructure they sit inside (FlowLayout and the width/count
// preference keys above).
