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
    @State private var stagedWindow = DateWindow()
    @State private var isShowingStagedWindow = false
    @State private var commitGeneration = 0

    private var visibleWindow: DateWindow {
        isShowingStagedWindow ? stagedWindow : window
    }

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var isCustom: Bool {
        visibleWindow.customStart != nil || visibleWindow.customEnd != nil
    }

    private var isActive: Bool {
        visibleWindow.isActive
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

    private var isCompactWidth: Bool {
        #if os(iOS)
            horizontalSizeClass == .compact
        #else
            false
        #endif
    }

    /// No dashes in user-facing copy (house style): join the two dates with "to".
    private var customRangeLabel: String {
        Self.customRangeLabel(start: visibleWindow.customStart, end: visibleWindow.customEnd)
    }

    static func customRangeLabel(start: Date?, end: Date?) -> String {
        let style = SharedDateStyles.longDate
        let start = start.map { $0.formatted(style) } ?? "…"
        let end = end.map { $0.formatted(style) } ?? "…"
        return String(
            localized: "\(start) to \(end)",
            comment: "A custom date range, e.g. \"March 1, 2025 to March 8, 2026\""
        )
    }

    private var chipText: String {
        if isCustom { return customRangeLabel }
        if let range = visibleWindow.range { return PadDateRange.displayLabel(for: range) }
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
            onClear: { commitWindow(DateWindow()) },
            menu: {
                Button {
                    commitWindow(DateWindow())
                } label: {
                    if isActive { Text("Any time") } else { Label("Any time", systemImage: "checkmark") }
                }
                Divider()
                ForEach(options, id: \.self) { option in
                    Button {
                        commitWindow(DateWindow(range: option))
                    } label: {
                        if !isCustom, option == visibleWindow.range {
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
        .popover(isPresented: $showCustom, arrowEdge: .top) {
            #if os(iOS)
                customPopover
                    .presentationDetents(isCompactWidth ? [.medium, .large] : [.large])
                    .presentationDragIndicator(isCompactWidth ? .visible : .hidden)
            #else
                customPopover
            #endif
        }
        .onChange(of: window) { _, newValue in
            commitGeneration &+= 1
            stagedWindow = newValue
            isShowingStagedWindow = false
        }
    }

    @ViewBuilder
    private var customPopover: some View {
        if isCompactWidth {
            #if os(iOS)
                NavigationStack {
                    compactCustomPopover
                        .navigationTitle("Custom \(title) Range")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { compactCustomToolbar }
                }
            #else
                compactCustomPopover
            #endif
        } else {
            regularCustomPopover
        }
    }

    private var regularCustomPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom \(title) Range").font(.headline)
            dateFields
            HStack {
                Spacer()
                actionButtons
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private var compactCustomPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                dateFields
                    .padding(.vertical, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ToolbarContentBuilder
    private var compactCustomToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) { showCustom = false }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Apply") { applyCustom() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var dateFields: some View {
        VStack(spacing: 10) {
            DatePicker("From", selection: $draftStart, displayedComponents: .date)
            DatePicker("To", selection: $draftEnd, in: draftStart..., displayedComponents: .date)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Cancel") { showCustom = false }
            Button("Apply") { applyCustom() }
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Seed the picker from the active custom range, or default to the last seven
    /// days when opening it fresh.
    private func prepareCustomDraft() {
        let calendar = Calendar.current
        let today = Date()
        draftStart = visibleWindow.customStart
            ?? calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: today))
            ?? today
        // Never seed an inverted range: the "To" picker's lower bound is `draftStart`,
        // so an end before the start would silently clamp and misrepresent the window.
        //
        // The fresh default is the start of today rather than the current instant
        // (#2012): the draft is a whole-day selection, and seeding it with a
        // time-of-day left the committed range depending on when the popover
        // happened to be opened.
        draftEnd = max(draftStart, visibleWindow.customEnd ?? calendar.startOfDay(for: today))
    }

    /// Commit the picker as an inclusive whole-day range: from the start of the
    /// "From" day to the last representable instant of the "To" day. The end is
    /// the moment just before the next midnight, not 23:59:59 exactly, so records
    /// timestamped during the final fractional second still fall inside the
    /// intended end date (#1642); `DateWindow.contains` compares inclusively.
    private func applyCustom() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: draftStart)
        // The "To" picker is bounded by `draftStart`, but moving "From" past an
        // already-chosen "To" leaves the stale earlier end in state, and applying it
        // committed a range that ends before it begins — matching nothing (#2010).
        // Normalizing here keeps the commit consistent with what the pickers show.
        let endDay = max(draftStart, draftEnd)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDay))
            .map { Date(timeIntervalSinceReferenceDate: $0.timeIntervalSinceReferenceDate.nextDown) }
            ?? draftEnd
        commitWindow(DateWindow(customStart: start, customEnd: end))
        showCustom = false
    }

    private func commitWindow(_ value: DateWindow) {
        commitGeneration &+= 1
        let generation = commitGeneration
        stagedWindow = value
        isShowingStagedWindow = true
        #if os(iOS)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                guard generation == commitGeneration else { return }

                window = value
            }
        #else
            window = value
        #endif
    }
}

/// A boolean preset chip: one tap toggles the bound filter on or off, with no menu
/// behind it. Wears the same idle pill / active accent-glass capsule styling as the
/// menu-backed chips so it reads as part of the same filter bar (used by the
/// Questions "Favorites" filter, #1008).
struct ToggleFilterChip: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption).accessibilityHidden(true)
                Text(title).font(.callout).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .foregroundStyle(chipLabelColor(isActive: isOn))
        .chipCapsule(
            glassTint: isOn ? .accentColor : nil,
            fallbackFill: isOn ? Color.accentColor.opacity(0.18) : Color.chipIdleFill,
            fallbackStroke: isOn ? Color.accentColor.opacity(0.4) : Color.subtleStroke,
            fallbackStrokeWidth: ChipContrast.lineWidth(contrast)
        )
        .fixedSize()
        // Announce the on/off state to VoiceOver; the visual accent fill alone
        // doesn't reach assistive tech.
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
            // Boolean preset chip, idle and toggled on.
            ToggleFilterChip(title: "Favorites", icon: "star", isOn: .constant(false))
            ToggleFilterChip(title: "Favorites", icon: "star", isOn: .constant(true))
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
