//
//  DesignSystem+Filters.swift
//  coderpad
//

import SwiftUI

// The generic filter-bar and sidebar-row width-measurement preference keys
// (FilterBarWidthKey/measuresFilterBarWidth, SidebarRowWidthKey/measuresSidebarRowWidth)
// now live in the buddy-kit package's BuddyDesignSystem (#377) and are re-exported via
// DesignSystem.swift, so the call sites here use them unchanged.

// MARK: - Section result count

/// Publishes a list section's result-count summary to its window's `WindowNavigation`
/// (via the environment), which `MainSplit` renders as the window's toolbar subtitle.
/// Per window rather than the former process-wide value, so two windows with different
/// searches or filters can't overwrite each other's counts (#908).
private struct SectionCountReporter: ViewModifier {
    @Environment(WindowNavigation.self) private var windowNav
    let summary: String

    func body(content: Content) -> some View {
        content.onChange(of: summary, initial: true) { _, new in
            windowNav.publishSectionCount(new)
        }
    }
}

extension View {
    /// Publishes this list section's result-count summary (e.g. "12 pads") to the
    /// window's `WindowNavigation`, which `MainSplit` renders as the window's toolbar
    /// subtitle beneath the section title. Pass an empty string when there's nothing
    /// to show (an empty or still-loading list).
    ///
    /// Fires once per settled value via `onChange` and routes through the guarded
    /// ``WindowNavigation/publishSectionCount(_:)``, so a count arrived at over the
    /// several `body` passes that settle one frame lands a single time. The former
    /// `SectionCountKey` preference wrote the live value straight into the view tree
    /// and so could update multiple times per frame — which SwiftUICore flagged as an
    /// invalid-configuration fault.
    func reportsSectionCount(_ summary: String) -> some View {
        modifier(SectionCountReporter(summary: summary))
    }
}

// `FlowLayout` (the wrapping filter-bar layout, backed by the Flow package's HFlow)
// now lives in the buddy-kit package's BuddyDesignSystem (#377) and is re-exported via
// DesignSystem.swift, so the filter-bar call sites here use it unchanged.

// The filter-chip view components (SearchableFilterChip, ChipLabel, the
// chipClearOverlay helper, and the searchable popover) now live alongside the
// other chips in FilterChips.swift. This file keeps the filter-bar layout and
// measurement infrastructure they sit inside (FlowLayout and the width/count
// preference keys above).
