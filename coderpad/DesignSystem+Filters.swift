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
    func measuresSidebarRowWidth(_ label: String) -> some View {
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
struct FlowLayout: Layout {
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

// MARK: - Searchable filter chip

struct SearchableFilterChip: View {
    let title: String
    let icon: String
    @Binding var selected: String?
    let options: [String]
    let formatter: (String) -> String
    /// When set, a "Me" shortcut is pinned to the top of the popover and the
    /// chip reads "Me" while this value is selected. Nil hides the shortcut
    /// (e.g. when the account has no known user email).
    var meEmail: String?

    @State private var presented = false
    @State private var search = ""
    @Environment(\.colorSchemeContrast) private var contrast

    private var chipText: String {
        guard let selected else { return title }
        if let meEmail, selected == meEmail { return "Me" }
        return formatter(selected)
    }

    private var accessibilityHint: String {
        if let selected { return "Filter applied: \(formatter(selected)). Activate to change." }
        return "No \(title.lowercased()) filter. Activate to choose one."
    }

    private var filtered: [String] {
        let query = search.lowercased()
        guard !query.isEmpty else { return options }
        return options.filter {
            formatter($0).lowercased().contains(query) || $0.lowercased().contains(query)
        }
    }

    /// Explicitly-typed style helpers keep the `body` type-checker from
    /// exploring these ternaries combinatorially (was ~6s to type-check).
    private var isActive: Bool {
        selected != nil
    }

    /// Idle state is transparent so this chip matches the borderless `Menu`-based
    /// FilterChipMenu chips, which don't paint a capsule fill until a filter is set.
    private var fillColor: Color {
        isActive ? Color.accentColor.opacity(ChipContrast.fill(0.18, contrast)) : Color.clear
    }

    private var strokeColor: Color {
        isActive ? Color.accentColor.opacity(ChipContrast.stroke(0.4, contrast)) : Color.clear
    }

    private var labelColor: Color {
        isActive ? Color.accentColor : Color.primary
    }

    var body: some View {
        // A plain tappable label rather than a `Button`: a macOS `Button` keeps
        // AppKit's default push-button control height and centers its label within
        // it (even with `.fixedSize()`), rendering taller than the FilterChipMenu
        // chips. Those menu chips now render the same `ChipLabel` under a
        // `.button` menu style, so they report the same true padded height as this
        // label and line up without any height compensation. We re-add button a11y
        // semantics by hand.
        ChipLabel(
            title: title,
            icon: icon,
            text: chipText,
            fillColor: fillColor,
            strokeColor: strokeColor,
            labelColor: labelColor,
            showsClear: isActive
        )
        .contentShape(Capsule())
        .onTapGesture { presented.toggle() }
        .chipClearOverlay(isActive: isActive, label: "Clear \(title) filter") { selected = nil }
        .disabled(options.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(title) filter")
        .accessibilityValue(selected.map(formatter) ?? "All")
        .accessibilityHint(accessibilityHint)
        .popover(isPresented: $presented, arrowEdge: .top) {
            SearchableFilterPopover(
                title: title,
                options: filtered,
                selected: $selected,
                presented: $presented,
                formatter: formatter,
                search: $search,
                meEmail: meEmail
            )
        }
    }
}

/// Extracted so the label's styling chain type-checks independently of the
/// chip's outer modifier/popover chain — keeps SearchableFilterChip.body fast
/// to compile (was ~671ms as one expression). Shared with FilterChipMenu so
/// the menu-backed chips render the same selected capsule as the Owner chip.
struct ChipLabel: View {
    let title: String
    let icon: String
    let text: String
    let fillColor: Color
    let strokeColor: Color
    let labelColor: Color
    /// When true, the trailing chevron becomes a clear (×) glyph to signal the chip
    /// can be cleared in place. The actual tap target is supplied by the parent via
    /// `chipClearOverlay` so clearing is independent of the chip's menu/popover.
    var showsClear: Bool = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption)
            Text(text)
                .font(.callout).lineLimit(1)
            Image(systemName: showsClear ? "xmark.circle.fill" : "chevron.down").font(.caption2)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(fillColor, in: Capsule())
        .foregroundStyle(labelColor)
        // Thicken the hairline border under Increase Contrast so the chip outline
        // stays defined for low-vision users.
        .overlay(Capsule().stroke(strokeColor, lineWidth: ChipContrast.lineWidth(contrast)))
    }
}

extension View {
    /// Overlays a tappable clear target over a chip's trailing × glyph (paired with
    /// `ChipLabel(showsClear:)`). Present only when `isActive`, so an idle chip is
    /// untouched; the target sits *inside* the chip's bounds so the wrapping filter
    /// bar never clips it, and floats above the chip's own menu/popover gesture so a
    /// click here clears rather than opening the chip.
    func chipClearOverlay(isActive: Bool, label: String, onClear: @escaping () -> Void) -> some View {
        overlay(alignment: .trailing) {
            if isActive {
                Button(action: onClear) {
                    Color.clear
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
            }
        }
    }
}

/// Extracted so its ScrollView/ForEach/ternary contents type-check independently
/// of the chip's modifier chain, keeping each `body` fast to compile.
private struct SearchableFilterPopover: View {
    let title: String
    let options: [String]
    @Binding var selected: String?
    @Binding var presented: Bool
    let formatter: (String) -> String
    @Binding var search: String
    var meEmail: String?

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search \(title.lowercased())", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let meEmail {
                        PopoverRow(
                            label: "Me",
                            subtitle: formatter(meEmail) == meEmail ? meEmail : formatter(meEmail),
                            isSelected: selected == meEmail
                        ) {
                            selected = meEmail
                            presented = false
                        }
                        Divider()
                    }
                    PopoverRow(label: "All", subtitle: nil, isSelected: selected == nil) {
                        selected = nil
                        presented = false
                    }
                    Divider()
                    ForEach(options, id: \.self) { option in
                        PopoverRow(
                            label: formatter(option),
                            subtitle: formatter(option) == option ? nil : option,
                            isSelected: option == selected
                        ) {
                            selected = option
                            presented = false
                        }
                    }
                    if options.isEmpty {
                        Text("No matches")
                            .font(.callout).foregroundStyle(.secondary)
                            .padding(10)
                    }
                }
            }
            .frame(width: 320, height: 320)
        }
    }
}

private struct PopoverRow: View {
    let label: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark" : "circle")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
                Text(label).lineLimit(1)
                Spacer(minLength: 4)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(hovered ? Color.accentColor.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
