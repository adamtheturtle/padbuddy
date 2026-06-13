//
//  PadsView+Chips.swift
//  coderpad
//

import SwiftUI

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
                    Image(systemName: icon).font(.caption)
                    Text(text).font(.callout).lineLimit(1)
                    // Drop the disclosure chevron when active — the × takes the
                    // trailing slot — so the chip doesn't grow a second glyph.
                    if !isActive { Image(systemName: "chevron.down").font(.caption2) }
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
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
    var resetLabel: String = "All"

    /// Match SearchableFilterChip's selected/idle styling so a set filter always
    /// shows the accent capsule. Idle is transparent; a selection paints the same
    /// accent fill, stroke, and text colour the Owner chip uses.
    private var isActive: Bool {
        selected != nil
    }

    private var fillColor: Color {
        isActive ? Color.accentColor.opacity(0.18) : Color.clear
    }

    private var strokeColor: Color {
        isActive ? Color.accentColor.opacity(0.4) : Color.clear
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
            clearLabel: "Clear \(title) filter",
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
        isActive ? Color.accentColor.opacity(0.18) : Color.clear
    }

    private var strokeColor: Color {
        isActive ? Color.accentColor.opacity(0.4) : Color.clear
    }

    private var labelColor: Color {
        isActive ? Color.accentColor : Color.primary
    }

    /// No dashes in user-facing copy (house style): join the two dates with "to".
    private var customRangeLabel: String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        let start = window.customStart.map { $0.formatted(style) } ?? "…"
        let end = window.customEnd.map { $0.formatted(style) } ?? "…"
        return "\(start) to \(end)"
    }

    private var chipText: String {
        if isCustom { return customRangeLabel }
        if let range = window.range { return range.capitalized }
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
            clearLabel: "Clear \(title.lowercased()) date filter",
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
                            Label(option.capitalized, systemImage: "checkmark")
                        } else {
                            Text(option.capitalized)
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

/// A built-in saved search shown as a chip ahead of the user's own. Defaults
/// aren't persisted or deletable — they're recomputed per account so "My Pads"
/// and "My Questions" track whoever is signed in.
struct DefaultSearch: Identifiable {
    let id: String
    let icon: String
    let search: NamedSearch
}

extension DefaultSearch {
    /// Built-in pad searches shown ahead of the user's saved searches, recomputed
    /// per account. "My Pads" appears only when the account knows its user's email;
    /// "Active" filters to in-progress sessions (the API's "started" state). Shared
    /// by the pad chip bar and the sidebar so the two never drift.
    static func padDefaults(me currentUserEmail: String?) -> [DefaultSearch] {
        var result: [DefaultSearch] = []
        if let currentUserEmail, !currentUserEmail.isEmpty {
            result.append(DefaultSearch(id: "my-pads", icon: "person.fill",
                                        search: NamedSearch(name: "My Pads", ownerFilter: currentUserEmail)))
        }
        result.append(DefaultSearch(id: "active", icon: "bolt.fill",
                                    search: NamedSearch(name: "Active", stateFilter: .active)))
        return result
    }

    /// Built-in question searches shown ahead of the user's saved searches,
    /// recomputed per account. "My Questions" appears only when the account knows
    /// its user's email; "Drafts" filters to unpublished questions. Shared by the
    /// question chip bar and the sidebar so the two never drift.
    static func questionDefaults(me currentUserEmail: String?) -> [DefaultSearch] {
        var result: [DefaultSearch] = []
        if let currentUserEmail, !currentUserEmail.isEmpty {
            result.append(DefaultSearch(id: "my-questions", icon: "person.fill",
                                        search: NamedSearch(name: "My Questions", ownerFilter: currentUserEmail)))
        }
        result.append(DefaultSearch(id: "drafts", icon: "doc.badge.ellipsis",
                                    search: NamedSearch(name: "Drafts", draftFilter: "draft")))
        return result
    }
}

struct SavedSearchChip: View {
    let name: String
    var systemImage: String = "bookmark.fill"
    /// True while the list's current filters exactly match this search — set the
    /// moment it's applied and cleared as soon as any filter is changed. Derived by
    /// the parent from filter state rather than stored, so it can never drift.
    var isActive: Bool = false
    let onApply: () -> Void
    /// Omitted for the built-in defaults, which can't be deleted.
    var onDelete: (() -> Void)?

    @State private var hovered = false

    /// Saved searches are *recall* buttons, not state: tapping one launches a set
    /// of filters rather than toggling a value. They stay neutral until applied, at
    /// which point the accent capsule marks "you are here" — the same accent the
    /// active filter chips use (see FilterChipMenu) — until a filter is modified.
    private var fillStyle: AnyShapeStyle {
        if isActive { return AnyShapeStyle(Color.accentColor.opacity(0.16)) }
        return hovered ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary)
    }

    private var strokeColor: Color {
        isActive ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08)
    }

    private var contentColor: AnyShapeStyle {
        isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary)
    }

    /// New names are capped on save, but names persisted before the cap (or any
    /// odd multi-line paste) could still be unbounded. Clamp to the same limit
    /// with a trailing ellipsis so no single chip overflows the bar; the full name
    /// stays in the accessibility label below.
    private var displayName: String {
        guard name.count > NamedSearch.maxNameLength else { return name }
        return String(name.prefix(NamedSearch.maxNameLength - 1)) + "…"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            Text(displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(contentColor)
                .lineLimit(1)
            if let onDelete {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete saved search \(name)")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(fillStyle, in: Capsule())
        .overlay(Capsule().strokeBorder(strokeColor, lineWidth: 0.5))
        .contentShape(Capsule())
        .onTapGesture { onApply() }
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("Apply saved search \(name)")
    }
}
