//
//  FilterChips.swift
//  coderpad
//
//  The domain-specific filter chips that stay app-side: the date-range chip bound to
//  a `DateWindow`. The generic chip primitives — the focus-ring suppressor, the
//  menu-backed `ChipMenuShell`, and the categorical `FilterChipMenu` — now live in
//  CoderPadDesignSystem (#515); this chip builds on the public `ChipMenuShell`. The
//  built-in Suggested-search chips live in FilterChips+Suggested / +Searchable.
//

import SwiftUI

/// A date-range filter chip bound to one `DateWindow`. `title` names the date
/// it constrains ("Updated" / "Created"); the pad bar shows one chip per window so
/// the two can be set independently. Offers the named windows and a custom
/// start/end picker, sharing the same chip styling as the other menu chips.
struct DateRangeFilterChip: View {
    let title: String
    @Binding var window: DateWindow
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
        chipLabelColor(isActive: isActive)
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
            menuDisabled: false,
            clearLabel: String(localized: "Clear \(title.lowercased()) date filter"),
            onClear: { window = DateWindow() },
            menu: {
                Button {
                    window = DateWindow()
                } label: {
                    if isActive { Text("Any time") } else { Label("Any time", systemImage: "checkmark") }
                }
                Divider()
                ForEach(options, id: \.self) { option in
                    Button {
                        window = DateWindow(range: option)
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
        // Never seed an inverted range: the "To" picker's lower bound is `draftStart`,
        // so an end before the start would silently clamp and misrepresent the window.
        draftEnd = max(draftStart, window.customEnd ?? today)
    }

    /// Commit the picker as an inclusive whole-day range: from the start of the
    /// "From" day to the last second of the "To" day.
    private func applyCustom() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: draftStart)
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: draftEnd) ?? draftEnd
        window = DateWindow(customStart: start, customEnd: end)
        showCustom = false
    }
}

#Preview("Filter chips — idle vs active") {
    VStack(alignment: .leading, spacing: 20) {
        Text("Filter chips (capsule pills)").font(.headline)
        HStack(spacing: 8) {
            // Idle filter chip: neutral pill that reads as a control (#352).
            FilterChipMenu(title: "State", icon: "circle",
                           selected: .constant(String?.none),
                           options: ["Active", "Ended"], formatter: { $0 })
            // Active filter chip: accent glass; label must stay readable, not
            // accent-on-accent (#397).
            FilterChipMenu(title: "Language", icon: "chevron.left.slash.chevron.right",
                           selected: .constant(Optional("Python")),
                           options: ["Python", "Swift"], formatter: { $0 })
        }

        Text("Saved-search tokens (rounded rectangles)").font(.headline)
        HStack(spacing: 8) {
            // Idle and active saved-search tokens — a distinct rounded-rect shape
            // from the filter pills above (#405), accent glass + readable text when
            // applied (#397).
            SavedSearchChip(name: "My Pads", systemImage: "person.fill", isActive: false,
                            maxNameLength: NamedSearch.maxNameLength, onApply: {})
            SavedSearchChip(name: "Active", systemImage: "bolt.fill", isActive: true,
                            maxNameLength: NamedSearch.maxNameLength, onApply: {})
            SavedSearchChip(name: "Frontend", isActive: false,
                            maxNameLength: NamedSearch.maxNameLength, onApply: {}, onDelete: {})
        }
    }
    .padding(40)
    .frame(width: 520, alignment: .leading)
    .background(.background)
}
