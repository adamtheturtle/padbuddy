//
//  LayoutMeasurement.swift
//  CoderPadDesignSystem
//
//  Domain-free SwiftUI layout-measurement utilities: preference keys (and the
//  view modifiers that report into them) that carry a subview's natural,
//  unclipped width up the view tree so an enclosing split-view column can refuse
//  to shrink below it. None of these reference app models, so they're shared with
//  the HackerRank app (#377). App-semantic preferences (e.g. a section's
//  result-count subtitle) stay in the app.
//

import SwiftUI

// MARK: - Filter bar width measurement

/// Carries the natural (unclipped) width of a filter bar up the view tree so the
/// enclosing split-view column can refuse to shrink below it. Reduces to the
/// widest reporter, and never below a sensible floor.
public struct FilterBarWidthKey: PreferenceKey {
    public static let defaultValue: CGFloat = 380
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public extension View {
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

// MARK: - Sidebar row width measurement

/// Carries the widest sidebar row's natural (unclipped) label width up the view
/// tree so the sidebar column can size its minimum to fit the longest label,
/// rather than relying on a hand-tuned constant that breaks when labels or the
/// row font change. Reduces to the widest reporter.
public struct SidebarRowWidthKey: PreferenceKey {
    public static let maximumValue: CGFloat = 230
    public static let maximumLabelLength = 80
    public static let defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(maximumValue, max(value, nextValue()))
    }

    public static func boundedLabel(_ label: String) -> String {
        String(label.prefix(maximumLabelLength))
    }
}

public extension View {
    /// Reports the natural width of `label` rendered at the sidebar row font via
    /// `SidebarRowWidthKey`. Measures a hidden, `fixedSize` copy of the text so the
    /// reported width is the *untruncated* width even though the visible row is
    /// line-limited — attach to each row and the key's `max` yields the widest.
    func measuresSidebarRowWidth(_ label: String) -> some View {
        background(
            Text(SidebarRowWidthKey.boundedLabel(label))
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
