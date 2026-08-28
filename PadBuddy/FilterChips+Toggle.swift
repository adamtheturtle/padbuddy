//
//  FilterChips+Toggle.swift
//  coderpad
//
//  The on/off and reset chips, and the chip-row preview.
//

import SwiftUI

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
        // 44pt hit area without changing the capsule's look. The chip was roughly 30pt
        // tall, below Apple's minimum, in the densest row of controls in the app and the
        // one most often used one-handed (#4775). `PadRow` and the code card's copy button
        // already use this helper; the filter bar did not.
        .touchTarget()
        // Announce the on/off state to VoiceOver; the visual accent fill alone
        // doesn't reach assistive tech.
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A compact action chip for clearing the current filter set. The iPhone compact-width
/// form keeps the reset action from wrapping as a mismatched full text button in the
/// chip row while preserving a named VoiceOver target.
struct FilterResetChip: View {
    let action: () -> Void

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
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption)
                    .accessibilityHidden(true)
                if !isCompactWidth {
                    Text("Reset")
                        .font(.callout)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: isCompactWidth ? 32 : 0, minHeight: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, isCompactWidth ? 8 : 10)
        .padding(.vertical, 5)
        .foregroundStyle(.secondary)
        .glassCapsule()
        .fixedSize()
        // As for `ToggleFilterChip` (#4775). Compact width dropped the "Reset" text for a
        // bare 32x20 icon, which is the smallest target in the bar.
        .touchTarget()
        .accessibilityLabel("Reset filters")
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
