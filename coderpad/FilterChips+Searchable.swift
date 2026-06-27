//
//  FilterChips+Searchable.swift
//  coderpad
//
//  The searchable filter chip and its supporting label, clear-overlay helper and
//  popover. Split out of FilterChips.swift so each chip family keeps its own file.
//

import BuddyDesignSystem
import SwiftUI

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

        if let meEmail, selected == meEmail { return String(localized: "Me") }
        return formatter(selected)
    }

    private var accessibilityHint: String {
        if let selected { return String(localized: "Filter applied: \(formatter(selected)). Activate to change.") }
        return String(localized: "No \(title.lowercased()) filter. Activate to choose one.")
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

    /// Idle wears the neutral chip pill so it reads as a control rather than bare
    /// text + chevron, matching the `Menu`-based FilterChipMenu chips (#352); a set
    /// filter swaps it for the accent capsule.
    private var fillColor: Color {
        isActive ? Color.accentColor.opacity(ChipContrast.fill(0.18, contrast)) : Color.chipIdleFill
    }

    private var strokeColor: Color {
        isActive ? Color.accentColor.opacity(ChipContrast.stroke(0.4, contrast)) : Color.subtleStroke
    }

    private var labelColor: Color {
        chipLabelColor(isActive: isActive)
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
        .chipClearOverlay(isActive: isActive, label: String(localized: "Clear \(title) filter")) { selected = nil }
        // Only disable when there's nothing to pick *and* no active filter to clear;
        // an active filter must stay clearable even if its option list reloaded empty.
        .disabled(options.isEmpty && !isActive)
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
            Image(systemName: icon).font(.caption).accessibilityHidden(true)
            Text(text)
                .font(.callout).lineLimit(1)
            Image(systemName: showsClear ? "xmark.circle.fill" : "chevron.down").font(.caption2)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .foregroundStyle(labelColor)
        // Glass on macOS 26, opaque capsule on 15. The fallback thickens its
        // hairline border under Increase Contrast so the outline stays defined for
        // low-vision users (#352).
        .chipCapsule(
            glassTint: showsClear ? .accentColor : nil,
            fallbackFill: fillColor,
            fallbackStroke: strokeColor,
            fallbackStrokeWidth: ChipContrast.lineWidth(contrast)
        )
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
                // The 22x22 clear target is exactly half the 44pt touch minimum in each
                // dimension; expand the hit area on touch (no-op on macOS, #597).
                .touchTarget()
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
                        PopoverSelectionRow(
                            label: String(localized: "Me"),
                            subtitle: formatter(meEmail) == meEmail ? meEmail : formatter(meEmail),
                            isSelected: selected == meEmail
                        ) {
                            selected = meEmail
                            presented = false
                        }
                        Divider()
                    }
                    PopoverSelectionRow(label: String(localized: "All"), subtitle: nil, isSelected: selected == nil) {
                        selected = nil
                        presented = false
                    }
                    Divider()
                    ForEach(options, id: \.self) { option in
                        PopoverSelectionRow(
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
