//
//  DesignSystem+Filters.swift
//  coderpad
//

import SwiftUI

// The generic filter-bar and sidebar-row width-measurement preference keys
// (FilterBarWidthKey/measuresFilterBarWidth, SidebarRowWidthKey/measuresSidebarRowWidth)
// now live in the CoderPadDesignSystem package (#377) and are re-exported via
// DesignSystem.swift, so the call sites here use them unchanged. Only the
// app-semantic SectionCountKey (a list section's result-count subtitle) stays here.

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

// `FlowLayout` (the wrapping filter-bar layout, backed by the Flow package's HFlow)
// now lives in the CoderPadDesignSystem package (#377) and is re-exported via
// DesignSystem.swift, so the filter-bar call sites here use it unchanged.

// The filter-chip view components (SearchableFilterChip, ChipLabel, the
// chipClearOverlay helper, and the searchable popover) now live alongside the
// other chips in FilterChips.swift. This file keeps the filter-bar layout and
// measurement infrastructure they sit inside (FlowLayout and the width/count
// preference keys above).
