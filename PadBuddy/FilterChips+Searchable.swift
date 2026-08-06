//
//  FilterChips+Searchable.swift
//  coderpad
//
//  The searchable filter chip and its supporting label, clear-overlay helper and
//  popover. Split out of FilterChips.swift so each chip family keeps its own file.
//

// swiftlint:disable file_length

import BuddyDesignSystem
import SwiftUI

nonisolated enum SearchableFilterMatching {
    static func contains(_ candidate: String, query: String, locale: Locale = .current) -> Bool {
        candidate.range(of: query, options: [.caseInsensitive], locale: locale) != nil
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
    @State private var stagedSelected: String?
    @State private var isShowingStagedSelected = false
    @State private var commitGeneration = 0

    private var visibleSelected: String? {
        isShowingStagedSelected ? stagedSelected : selected
    }

    private var chipText: String {
        guard let visibleSelected else { return title }

        if let meEmail, visibleSelected == meEmail {
            return String(localized: "Me")
        }
        return formatter(visibleSelected)
    }

    private var accessibilityHint: String {
        if let visibleSelected {
            return String(localized: "Filter applied: \(formatter(visibleSelected)). Activate to change.")
        }
        return String(localized: "No \(title.lowercased()) filter. Activate to choose one.")
    }

    /// One option prepared for searching: the value to return alongside the
    /// formatted forms the query is matched against.
    private struct SearchIndexEntry {
        let value: String
        let label: String

        func matches(_ query: String) -> Bool {
            SearchableFilterMatching.contains(label, query: query)
                || SearchableFilterMatching.contains(value, query: query)
        }
    }

    /// The prepared options `filtered` searches. Built when the popover opens and
    /// rebuilt if the option list changes while it is open, so a keystroke scans
    /// ready-made strings instead of formatting and lowercasing every option again:
    /// an owner chip backed by a large org directory allocated two strings per
    /// member per keystroke (#2102). Dropped on close so an idle chip doesn't
    /// retain a copy of the whole directory.
    @State private var searchIndex: [SearchIndexEntry] = []

    private func indexEntry(for option: String) -> SearchIndexEntry {
        SearchIndexEntry(
            value: option,
            label: formatter(option)
        )
    }

    private var filtered: [String] {
        let query = search
        guard !query.isEmpty else { return options }

        // A render can beat the rebuild (or land while the chip is closed); index
        // on the fly then rather than filtering against a stale list.
        let entries = searchIndex.count == options.count ? searchIndex : options.map(indexEntry(for:))
        return entries.filter { $0.matches(query) }.map(\.value)
    }

    /// Explicitly-typed style helpers keep the `body` type-checker from
    /// exploring these ternaries combinatorially (was ~6s to type-check).
    private var isActive: Bool {
        visibleSelected != nil
    }

    private var labelColor: Color {
        chipLabelColor(isActive: isActive)
    }

    /// The tappable chip itself, split from `body` so its styling and
    /// accessibility chain type-checks independently of the popover and
    /// `onChange` chain below: folding the search-index refresh handlers into one
    /// expression pushed `body` past the Release build's 250ms type-check budget
    /// (#2102).
    private var chip: some View {
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
            labelColor: labelColor,
            showsClear: isActive
        )
        .contentShape(Capsule())
        .onTapGesture { presented.toggle() }
        .chipClearOverlay(isActive: isActive, label: String(localized: "Clear \(title) filter")) {
            commitSelection(nil)
        }
        // Only disable when there's nothing to pick *and* no active filter to clear;
        // an active filter must stay clearable even if its option list reloaded empty.
        .disabled(options.isEmpty && !isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(title) filter")
        .accessibilityValue(visibleSelected.map(formatter) ?? String(localized: "All"))
        .accessibilityHint(accessibilityHint)
        // The chip advertises button semantics but is a tap-gesture label, so
        // assistive technologies need an explicit activation to open it (#1649).
        .accessibilityAction { presented.toggle() }
    }

    var body: some View {
        chip
            // A stale query from the previous popover session would filter the next
            // open down to "No matches" out of nowhere (#1648).
            .onChange(of: presented) { _, isPresented in
                if isPresented {
                    searchIndex = options.map(indexEntry(for:))
                } else {
                    search = ""
                    searchIndex = []
                }
            }
            // Options can load in (or a directory can resolve display names) after the
            // popover is already open; keep the prepared strings in step with them.
            .onChange(of: options) { _, newOptions in
                if presented {
                    searchIndex = newOptions.map(indexEntry(for:))
                }
            }
            .popover(isPresented: $presented, arrowEdge: .top) {
                SearchableFilterPopover(
                    title: title,
                    options: filtered,
                    selected: visibleSelectionBinding,
                    presented: $presented,
                    formatter: formatter,
                    search: $search,
                    meEmail: meEmail
                )
            }
            .onChange(of: selected) { _, newValue in
                commitGeneration &+= 1
                stagedSelected = newValue
                isShowingStagedSelected = false
            }
    }

    private var visibleSelectionBinding: Binding<String?> {
        Binding(
            get: { visibleSelected },
            set: { commitSelection($0) }
        )
    }

    private func commitSelection(_ value: String?) {
        commitGeneration &+= 1
        let generation = commitGeneration
        stagedSelected = value
        isShowingStagedSelected = true
        #if os(iOS)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                guard generation == commitGeneration else { return }

                selected = value
            }
        #else
            selected = value
        #endif
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
    let labelColor: Color
    /// When true, the trailing chevron becomes a clear (×) glyph to signal the chip
    /// can be cleared in place. The actual tap target is supplied by the parent via
    /// `chipClearOverlay` so clearing is independent of the chip's menu/popover.
    var showsClear: Bool = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption).accessibilityHidden(true)
            Text(text)
                .font(.callout).lineLimit(1)
            Image(systemName: showsClear ? "xmark.circle.fill" : "chevron.down").font(.caption2)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.compactControlH).padding(.vertical, Spacing.compactControlV)
        .foregroundStyle(labelColor)
        .glassCapsule(tint: showsClear ? .accentColor : nil)
    }
}

extension View {
    /// Overlays a tappable clear target over a chip's trailing × glyph (paired with
    /// `ChipLabel(showsClear:)`). Present only when `isActive`, so an idle chip is
    /// untouched; the target sits *inside* the chip's bounds so the wrapping filter
    /// bar never clips it, and floats above the chip's own menu/popover gesture so a
    /// click here clears rather than opening the chip.
    func chipClearOverlay(isActive: Bool, label: String, onClear: @escaping () -> Void) -> some View {
        #if os(iOS)
            let clearTargetSize: CGFloat = 44
        #else
            let clearTargetSize: CGFloat = 22
        #endif

        return overlay(alignment: .trailing) {
            if isActive {
                Button(action: onClear) {
                    Color.clear
                        .frame(width: clearTargetSize, height: clearTargetSize)
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

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var isCompactWidth: Bool {
        #if os(iOS)
            horizontalSizeClass == .compact
        #else
            false
        #endif
    }

    var body: some View {
        #if os(iOS)
            popoverContent
                .presentationDetents(isCompactWidth ? [.medium, .large] : [.large])
                .presentationDragIndicator(isCompactWidth ? .visible : .hidden)
        #else
            popoverContent
        #endif
    }

    @ViewBuilder
    private var popoverContent: some View {
        if isCompactWidth {
            compactContent
        } else {
            regularContent
        }
    }

    private var regularContent: some View {
        VStack(spacing: 0) {
            searchField
                .padding(Spacing.popoverInset)
            Divider()
            ScrollView {
                rows
            }
            .frame(width: 320, height: 320)
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            searchField
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                rows
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var searchField: some View {
        TextField("Search \(title.lowercased())", text: $search)
            .textFieldStyle(.roundedBorder)
    }

    /// The rows to list, with the current user's email removed when the pinned
    /// "Me" row already covers it: listing it twice would show two choices for
    /// the same filter (#1647).
    ///
    /// De-duplicated first. `ForEach` keys these by value, so a repeated option —
    /// the same owner returned by two accounts, or the same language by two pages —
    /// produced duplicate SwiftUI identities, which makes selection and row
    /// updates unreliable (#2578). Matching is case-insensitive, like the "Me"
    /// comparison below: two spellings of one address are one choice, and the
    /// language and type values these chips also serve are already normalized.
    /// First occurrence wins so the caller's ordering is preserved.
    private var nonMeOptions: [String] {
        var seen = Set<String>()
        var rows: [String] = []
        rows.reserveCapacity(options.count)
        for option in options {
            if let meEmail, option.caseInsensitiveCompare(meEmail) == .orderedSame {
                continue
            }
            guard seen.insert(option.lowercased()).inserted else { continue }

            rows.append(option)
        }
        return rows
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let meEmail {
                PopoverSelectionRow(
                    label: String(localized: "Me"),
                    // The email when a display name resolves (nil when the email is
                    // all we have), matching the member rows below so "Me" says which
                    // address it maps to (#992).
                    subtitle: formatter(meEmail) == meEmail ? nil : meEmail,
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
            ForEach(nonMeOptions, id: \.self) { option in
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
                    .padding(Spacing.popoverInset)
            }
        }
    }
}
