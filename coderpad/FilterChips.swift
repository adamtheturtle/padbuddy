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
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The view isn't attached to the control's hierarchy yet at make time.
        DispatchQueue.main.async { suppress(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
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
    var resetLabel: String = String(localized: "All")

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
                                        search: NamedSearch(name: String(localized: "My Pads"), ownerFilter: currentUserEmail)))
        }
        result.append(DefaultSearch(id: "active", icon: "bolt.fill",
                                    search: NamedSearch(name: String(localized: "Active"), stateFilter: .active)))
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
                                        search: NamedSearch(name: String(localized: "My Questions"), ownerFilter: currentUserEmail)))
        }
        result.append(DefaultSearch(id: "drafts", icon: "doc.badge.ellipsis",
                                    search: NamedSearch(name: String(localized: "Drafts"), draftFilter: "draft")))
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
        .chipClearOverlay(isActive: isActive, label: String(localized: "Clear \(title) filter")) { selected = nil }
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
                            label: String(localized: "Me"),
                            subtitle: formatter(meEmail) == meEmail ? meEmail : formatter(meEmail),
                            isSelected: selected == meEmail
                        ) {
                            selected = meEmail
                            presented = false
                        }
                        Divider()
                    }
                    PopoverRow(label: String(localized: "All"), subtitle: nil, isSelected: selected == nil) {
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
