//
//  DetailChipBar.swift
//  coderpad
//

import SwiftUI

/// An item shown as a chip in a `DetailChipBar`: the detail panes' section and
/// pane enums conform so both bars render from the same source of truth.
/// Nonisolated (like the conforming enums) so the `Identifiable`/`Equatable`
/// requirements don't cross out of the app's default MainActor isolation.
nonisolated protocol DetailChipItem: Identifiable, Equatable {
    var label: LocalizedStringKey { get }
    var systemImage: String { get }
}

/// The shared chip bar pinned above a detail pane's scroll content (via
/// `.safeAreaInset(edge: .top)`), so pad and question detail present one visual
/// exclusive panes (keeping the Solution off screen until asked for).
/// pass no `selection` for momentary scroll-to-section buttons, or bind
/// `selection` when chips switch mutually exclusive panes.
struct DetailChipBar<Item: DetailChipItem>: View {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    let items: [Item]
    /// The exclusively-selected item when the bar switches panes; `nil` when
    /// the chips are navigation buttons with no persistent state.
    var selection: Item?
    /// Matches the hosting scroll content's leading padding so the chips line
    /// up with the cards below them.
    let horizontalPadding: CGFloat
    let accessibilityLabel: LocalizedStringKey
    let action: (Item) -> Void

    var body: some View {
        if selection == nil {
            visualBar
        } else {
            visualBar
                // Keep the custom glass chips visually, while assistive
                // technologies receive a native single-selection control whose
                // exclusivity and selected value are explicit (#2015).
                .accessibilityRepresentation {
                    Picker(accessibilityLabel, selection: accessibilitySelection) {
                        ForEach(uniqueItems) { item in
                            Text(item.label).tag(Optional(item.id))
                        }
                    }
                    .pickerStyle(.segmented)
                }
        }
    }

    private var visualBar: some View {
        // Horizontal scroll rather than wrapping: the bar is pinned, so it must
        // keep a fixed height however narrow the detail column gets.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(uniqueItems) { item in
                    chip(for: item)
                }
            }
            .padding(.leading, chipBarHorizontalPadding)
            .padding(.trailing, chipBarHorizontalPadding)
            .padding(.vertical, chipBarVerticalPadding)
        }
        .mask(alignment: .trailing) {
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.88),
                .init(color: .clear, location: 1)
            ], startPoint: .leading, endPoint: .trailing)
        }
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var chipBarHorizontalPadding: CGFloat {
        #if os(iOS)
            horizontalSizeClass == .compact ? 12 : horizontalPadding
        #else
            horizontalPadding
        #endif
    }

    private var chipBarVerticalPadding: CGFloat {
        #if os(iOS)
            horizontalSizeClass == .compact ? 6 : 8
        #else
            8
        #endif
    }

    private var chipHorizontalPadding: CGFloat {
        #if os(iOS)
            horizontalSizeClass == .compact ? 9 : 12
        #else
            12
        #endif
    }

    private var chipVerticalPadding: CGFloat {
        #if os(iOS)
            horizontalSizeClass == .compact ? 5 : 6
        #else
            6
        #endif
    }

    private var chipFont: Font {
        #if os(iOS)
            horizontalSizeClass == .compact ? .caption : .callout
        #else
            .callout
        #endif
    }

    private var accessibilitySelection: Binding<Item.ID?> {
        Binding(
            get: { selection?.id },
            set: { id in
                guard let id, let item = uniqueItems.first(where: { $0.id == id }) else { return }

                action(item)
            }
        )
    }

    /// The chips to render, de-duplicated by `id`. `ForEach` keys these by
    /// identity, so a caller that repeats a section or pane value handed SwiftUI
    /// duplicate identities, which renders duplicate controls and makes selection
    /// updates unstable (#2014). First occurrence wins so the caller's ordering
    /// is preserved.
    var uniqueItems: [Item] {
        var seen = Set<Item.ID>()
        var unique: [Item] = []
        unique.reserveCapacity(items.count)
        for item in items where seen.insert(item.id).inserted {
            unique.append(item)
        }

        return unique
    }

    private func chip(for item: Item) -> some View {
        let isSelected = selection == item

        return Button {
            action(item)
        } label: {
            Label {
                Text(item.label)
                    .lineLimit(1)
            } icon: {
                // Decorative: the Label's own text names the chip, and the button
                // carries an explicit accessibilityLabel below, so announcing the
                // symbol as well would just repeat it.
                Image(systemName: item.systemImage)
                    .accessibilityHidden(true)
            }
            .font(chipFont.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.78))
            .padding(.horizontal, chipHorizontalPadding)
            .padding(.vertical, chipVerticalPadding)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .selectableGlassRoundedRectangle(isSelected: isSelected)
        .accessibilityLabel(Text(item.label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
