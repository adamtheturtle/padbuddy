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
    /// The deferred commit, retained so it can be cancelled.
    ///
    /// It used to be a fire-and-forget `Task`: nothing cancelled the one it replaced, and
    /// nothing cancelled it when the chip disappeared, so a commit could land after the
    /// view was gone and write a window the user had navigated away from. The generation
    /// guard suppressed the *value* but the task still ran (#4779).
    @State private var commitTask: Task<Void, Never>?

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
        if isCustom {
            return customRangeLabel
        }
        if let range = visibleWindow.range {
            return PadDateRange.displayLabel(for: range)
        }
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
                    if isActive {
                        Text("Any time")
                    } else {
                        Label("Any time", systemImage: "checkmark")
                    }
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
                    if isCustom {
                        Label("Custom…", systemImage: "checkmark")
                    } else {
                        Text("Custom…")
                    }
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
        .onDisappear { cancelPendingCommit() }
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

    #if os(iOS)
        @ToolbarContentBuilder
        private var compactCustomToolbar: some ToolbarContent {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showCustom = false }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") { applyCustom() }
            }
        }
    #endif

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
            commitTask?.cancel()
            commitTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(80))
                } catch {
                    return
                }
                guard !Task.isCancelled, generation == commitGeneration else { return }

                window = value
            }
        #else
            window = value
        #endif
    }

    /// Cancels a staged commit when the chip goes away, so it cannot write after the
    /// view it belonged to is gone (#4779).
    private func cancelPendingCommit() {
        commitTask?.cancel()
        commitTask = nil
    }
}
