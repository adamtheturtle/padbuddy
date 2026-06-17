//
//  FilterChips.swift
//  coderpad
//
//  The reusable filter-chip components shared by the Pads and Questions filter
//  bars (and the combined-view bars): the menu-backed and searchable chips, the
//  date-range chip, the saved-search chips and their built-in defaults, plus the
//  shared chip label and clear-overlay primitives. Extracted here so the chip
//  vocabulary lives in one place rather than split between a view-specific file
//  and DesignSystem.
//

import AppKit
import SwiftUI

/// Strips the AppKit keyboard focus ring from the control backing a button-styled
/// `Menu`. SwiftUI's `.focusEffectDisabled()` governs its own focus *effect*, but a
/// `Menu` rendered with `.menuStyle(.button)` is hosted by an `NSControl` that draws
/// its own `focusRingType` ring — which the SwiftUI modifier doesn't reach, so a
/// stray blue box still appears around the chip when it takes keyboard focus (#341).
/// Attached via `.background`, the helper sits inside the control's view tree and
/// walks up to set `focusRingType = .none` on the hosting views (mirroring how
/// ``TableDoubleClickInstaller`` reaches its enclosing table).
private struct FocusRingSuppressor: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        // The view isn't attached to the control's hierarchy yet at make time.
        DispatchQueue.main.async { suppress(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        // Re-assert in case SwiftUI rebuilt the backing control and reset its ring.
        DispatchQueue.main.async { suppress(from: nsView) }
    }

    private func suppress(from view: NSView) {
        var candidate = view.superview
        while let current = candidate {
            current.focusRingType = .none
            if let control = current as? NSControl {
                control.cell?.focusRingType = .none
            }
            candidate = current.superview
        }
    }
}

private extension View {
    /// Suppresses the AppKit focus ring drawn by the control hosting this view.
    func suppressFocusRing() -> some View {
        background(FocusRingSuppressor())
    }
}

/// Shared shell for the menu-backed filter chips. Draws one capsule around a
/// `Menu` and — when a filter is set — a sibling clear (×) button. The × is a real
/// sibling laid out *beside* the menu rather than overlaid on top of it: a SwiftUI
/// `Button` placed over a `Menu` lets the click leak into the menu's synchronous
/// AppKit tracking loop, which beach-balls on clear. Keeping them side by side
/// means a click on the × never reaches the menu.
private struct ChipMenuShell<MenuContent: View>: View {
    let icon: String
    let text: String
    let isActive: Bool
    let fillColor: Color
    let strokeColor: Color
    let labelColor: Color
    var menuDisabled: Bool = false
    let clearLabel: String
    let onClear: () -> Void
    @ViewBuilder var menu: () -> MenuContent
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                menu()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: icon).font(.caption).accessibilityHidden(true)
                    Text(text).font(.callout).lineLimit(1)
                    // Drop the disclosure chevron when active — the × takes the
                    // trailing slot — so the chip doesn't grow a second glyph.
                    if !isActive { Image(systemName: "chevron.down").font(.caption2).accessibilityHidden(true) }
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            // Suppress AppKit's rectangular keyboard focus ring: it doesn't follow
            // the chip's capsule and reads as a stray blue box around the label.
            // `.focusEffectDisabled()` handles SwiftUI's own focus effect; the button
            // Menu's backing NSControl draws a separate AppKit ring that needs
            // `focusRingType = .none` to go away (#341).
            .focusEffectDisabled()
            .suppressFocusRing()
            .disabled(menuDisabled)

            if isActive {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(fillColor, in: Capsule())
        .foregroundStyle(labelColor)
        .overlay(Capsule().stroke(strokeColor, lineWidth: ChipContrast.lineWidth(contrast)))
        .fixedSize()
    }
}

struct FilterChipMenu<Option: Hashable>: View {
    let title: String
    let icon: String
    @Binding var selected: Option?
    let options: [Option]
    let formatter: (Option) -> String
    /// The label of the row that clears the filter. "All" reads naturally for the
    /// categorical chips (State, Language, …); callers can override it.
    var resetLabel: String = .init(localized: "All")

    /// Match SearchableFilterChip's selected/idle styling so a set filter always
    /// shows the accent capsule. Idle wears the neutral chip pill so it reads as a
    /// control (#352); a selection paints the same accent fill, stroke, and text
    /// colour the Owner chip uses.
    private var isActive: Bool {
        selected != nil
    }

    private var fillColor: Color {
        isActive ? Color.accentColor.opacity(0.18) : Color.chipIdleFill
    }

    private var strokeColor: Color {
        isActive ? Color.accentColor.opacity(0.4) : Color.subtleStroke
    }

    private var labelColor: Color {
        isActive ? Color.accentColor : Color.primary
    }

    var body: some View {
        ChipMenuShell(
            icon: icon,
            text: selected.map(formatter) ?? title,
            isActive: isActive,
            fillColor: fillColor,
            strokeColor: strokeColor,
            labelColor: labelColor,
            menuDisabled: options.isEmpty,
            clearLabel: String(localized: "Clear \(title) filter"),
            onClear: { selected = nil },
            menu: {
                // The reset row carries the checkmark while nothing is selected, so
                // exactly one row in the menu is always marked as the current choice.
                Button {
                    selected = nil
                } label: {
                    if isActive { Text(resetLabel) } else { Label(resetLabel, systemImage: "checkmark") }
                }
                if !options.isEmpty { Divider() }
                ForEach(options, id: \.self) { option in
                    Button {
                        selected = option
                    } label: {
                        if option == selected {
                            Label(formatter(option), systemImage: "checkmark")
                        } else {
                            Text(formatter(option))
                        }
                    }
                }
            }
        )
    }
}

/// A date-range filter chip bound to one `PadDateWindow`. `title` names the date
/// it constrains ("Updated" / "Created"); the pad bar shows one chip per window so
/// the two can be set independently. Offers the named windows and a custom
/// start/end picker, sharing the same chip styling as the other menu chips.
struct DateRangeFilterChip: View {
    let title: String
    @Binding var window: PadDateWindow
    let options: [String]

    @State private var showCustom = false
    @State private var draftStart = Date()
    @State private var draftEnd = Date()

    private var isCustom: Bool {
        window.customStart != nil || window.customEnd != nil
    }

    private var isActive: Bool {
        window.isActive
    }

    private var fillColor: Color {
        isActive ? Color.accentColor.opacity(0.18) : Color.chipIdleFill
    }

    private var strokeColor: Color {
        isActive ? Color.accentColor.opacity(0.4) : Color.subtleStroke
    }

    private var labelColor: Color {
        isActive ? Color.accentColor : Color.primary
    }

    /// No dashes in user-facing copy (house style): join the two dates with "to".
    private var customRangeLabel: String {
        let style = Date.FormatStyle.dateTime.month(.wide).day()
        let start = window.customStart.map { $0.formatted(style) } ?? "…"
        let end = window.customEnd.map { $0.formatted(style) } ?? "…"
        return String(localized: "\(start) to \(end)", comment: "A custom date range, e.g. \"March 1 to March 8\"")
    }

    private var chipText: String {
        if isCustom { return customRangeLabel }
        if let range = window.range { return PadDateRange.displayLabel(for: range) }
        return title
    }

    var body: some View {
        ChipMenuShell(
            icon: "calendar",
            text: chipText,
            isActive: isActive,
            fillColor: fillColor,
            strokeColor: strokeColor,
            labelColor: labelColor,
            clearLabel: String(localized: "Clear \(title.lowercased()) date filter"),
            onClear: { window = PadDateWindow() },
            menu: {
                Button {
                    window = PadDateWindow()
                } label: {
                    if isActive { Text("Any time") } else { Label("Any time", systemImage: "checkmark") }
                }
                Divider()
                ForEach(options, id: \.self) { option in
                    Button {
                        window = PadDateWindow(range: option)
                    } label: {
                        if !isCustom, option == window.range {
                            Label(PadDateRange.displayLabel(for: option), systemImage: "checkmark")
                        } else {
                            Text(PadDateRange.displayLabel(for: option))
                        }
                    }
                }
                Divider()
                Button {
                    prepareCustomDraft()
                    showCustom = true
                } label: {
                    if isCustom { Label("Custom…", systemImage: "checkmark") } else { Text("Custom…") }
                }
            }
        )
        .popover(isPresented: $showCustom, arrowEdge: .top) { customPopover }
    }

    private var customPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom \(title) Range").font(.headline)
            DatePicker("From", selection: $draftStart, displayedComponents: .date)
            DatePicker("To", selection: $draftEnd, in: draftStart..., displayedComponents: .date)
            HStack {
                Spacer()
                Button("Cancel") { showCustom = false }
                Button("Apply") { applyCustom() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    /// Seed the picker from the active custom range, or default to the last seven
    /// days when opening it fresh.
    private func prepareCustomDraft() {
        let calendar = Calendar.current
        let today = Date()
        draftStart = window.customStart
            ?? calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: today))
            ?? today
        draftEnd = window.customEnd ?? today
    }

    /// Commit the picker as an inclusive whole-day range: from the start of the
    /// "From" day to the last second of the "To" day.
    private func applyCustom() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: draftStart)
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: draftEnd) ?? draftEnd
        window = PadDateWindow(customStart: start, customEnd: end)
        showCustom = false
    }
}
