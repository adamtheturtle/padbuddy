//
//  DesignSystem+Filters.swift
//  coderpad
//

import SwiftUI

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

// `FlowLayout` (the wrapping filter-bar layout, backed by the Flow package's HFlow)
// now lives in the CoderPadDesignSystem package (#377) and is re-exported via
// DesignSystem.swift, so the filter-bar call sites here use it unchanged.

// The filter-chip view components (SearchableFilterChip, ChipLabel, the
// chipClearOverlay helper, and the searchable popover) now live alongside the
// other chips in FilterChips.swift. This file keeps the filter-bar layout and
// measurement infrastructure they sit inside (FlowLayout and the width/count
// preference keys above).
