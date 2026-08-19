//
//  FilterChipMenu.swift
//  CoderPadDesignSystem
//
//  The generic, domain-free filter-chip primitives shared by both apps: the
//  focus-ring suppressor, the menu-backed chip shell, and the categorical
//  `FilterChipMenu`. Lifted out of the app (#515) so the chip vocabulary lives
//  beside the other design-system components. Domain-specific chips (date-range,
//  saved-search) stay app-side and build on the public `ChipMenuShell`.
//

import AppKit
import SwiftUI

/// Strips the AppKit keyboard focus ring from the control backing a button-styled
/// `Menu`. SwiftUI's `.focusEffectDisabled()` governs its own focus *effect*, but a
/// `Menu` rendered with `.menuStyle(.button)` is hosted by an `NSControl` that draws
/// its own `focusRingType` ring — which the SwiftUI modifier doesn't reach, so a
/// stray blue box still appears around the chip when it takes keyboard focus (#341).
/// Attached via `.background`, the helper sits inside the control's view tree and
/// walks up to set `focusRingType = .none` on the hosting views (the same
/// walk-up-the-view-tree trick an `NSViewRepresentable` uses to reach its host).
struct FocusRingSuppressor: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        // The view isn't attached to the control's hierarchy yet at make time.
        DispatchQueue.main.async { Self.suppress(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        // Re-assert in case SwiftUI rebuilt the backing control and reset its ring.
        DispatchQueue.main.async { Self.suppress(from: nsView) }
    }

    static func suppress(from view: NSView) {
        var candidate = view.superview
        while let current = candidate {
            if let control = current as? NSControl {
                control.focusRingType = .none
                control.cell?.focusRingType = .none
                return
            }
            candidate = current.superview
        }
    }
}

extension View {
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
public struct ChipMenuShell<MenuContent: View>: View {
    private enum FocusedElement: Hashable {
        case menu
        case clear
    }

    let icon: String
    let text: String
    let isActive: Bool
    let fillColor: Color
    let strokeColor: Color
    let labelColor: Color
    var menuDisabled: Bool
    let clearLabel: String
    let onClear: () -> Void
    @ViewBuilder var menu: () -> MenuContent
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var focusedElement: FocusedElement?

    public init(
        icon: String,
        text: String,
        isActive: Bool,
        fillColor: Color,
        strokeColor: Color,
        labelColor: Color,
        menuDisabled: Bool,
        clearLabel: String,
        onClear: @escaping () -> Void,
        @ViewBuilder menu: @escaping () -> MenuContent
    ) {
        self.icon = icon
        self.text = text
        self.isActive = isActive
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.labelColor = labelColor
        self.menuDisabled = menuDisabled
        self.clearLabel = clearLabel
        self.onClear = onClear
        self.menu = menu
    }

    public var body: some View {
        HStack(spacing: 4) {
            Menu {
                menu()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: icon).font(.caption).accessibilityHidden(true)
                    Text(text).font(.callout).lineLimit(1)
                    // Drop the disclosure chevron when active — the × takes the
                    // trailing slot — so the chip doesn't grow a second glyph.
                    if !isActive {
                        Image(systemName: "chevron.down").font(.caption2).accessibilityHidden(true)
                    }
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
            .focused($focusedElement, equals: .menu)
            .disabled(menuDisabled)

            if isActive {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
                .focused($focusedElement, equals: .clear)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .foregroundStyle(labelColor)
        .chipCapsule(
            glassTint: isActive ? .accentColor : nil,
            fallbackFill: fillColor,
            fallbackStroke: strokeColor,
            fallbackStrokeWidth: ChipContrast.lineWidth(contrast)
        )
        .overlay {
            if focusedElement != nil {
                Capsule()
                    .stroke(Color.accentColor, lineWidth: ChipContrast.focusLineWidth(contrast))
                    .padding(-2)
            }
        }
        .fixedSize()
    }
}

/// A categorical filter chip: a labelled menu of mutually exclusive options bound to
/// an optional selection, with a checkmark on the current choice and a reset row.
public struct FilterChipMenu<Option: Hashable>: View {
    let title: String
    let icon: String
    @Binding var selected: Option?
    let options: [Option]
    let formatter: (Option) -> String
    /// The label of the row that clears the filter. "All" reads naturally for the
    /// categorical chips (State, Language, …); callers can override it.
    var resetLabel: String
    @State private var stagedSelection: Option?
    @State private var isShowingStagedSelection = false
    @State private var commitGeneration = 0

    private var visibleSelection: Option? {
        isShowingStagedSelection ? stagedSelection : selected
    }

    public init(
        title: String,
        icon: String,
        selected: Binding<Option?>,
        options: [Option],
        formatter: @escaping (Option) -> String,
        resetLabel: String = String(localized: "All")
    ) {
        self.title = title
        self.icon = icon
        _selected = selected
        self.options = Self.uniqueOptions(options)
        self.formatter = formatter
        self.resetLabel = resetLabel
    }

    static func uniqueOptions(_ options: [Option]) -> [Option] {
        var seen = Set<Option>()
        return options.filter { seen.insert($0).inserted }
    }

    /// Match SearchableFilterChip's selected/idle styling so a set filter always
    /// shows the accent capsule. Idle wears the neutral chip pill so it reads as a
    /// control (#352); a selection paints the same accent fill, stroke, and text
    /// colour the Owner chip uses.
    private var isActive: Bool {
        visibleSelection != nil
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

    public var body: some View {
        ChipMenuShell(
            icon: icon,
            text: visibleSelection.map(formatter) ?? title,
            isActive: isActive,
            fillColor: fillColor,
            strokeColor: strokeColor,
            labelColor: labelColor,
            menuDisabled: options.isEmpty,
            clearLabel: String(localized: "Clear \(title) filter"),
            onClear: { commitSelection(nil) },
            menu: {
                // The reset row carries the checkmark while nothing is selected, so
                // exactly one row in the menu is always marked as the current choice.
                Button {
                    commitSelection(nil)
                } label: {
                    if isActive {
                        Text(resetLabel)
                    } else {
                        Label(resetLabel, systemImage: "checkmark")
                    }
                }
                if !options.isEmpty {
                    Divider()
                }
                ForEach(options, id: \.self) { option in
                    Button {
                        commitSelection(option)
                    } label: {
                        if option == visibleSelection {
                            Label(formatter(option), systemImage: "checkmark")
                        } else {
                            Text(formatter(option))
                        }
                    }
                }
            }
        )
        .accessibilityHint(isActive
            ? String(localized: "\(title) filter selected: \(visibleSelection.map(formatter) ?? "")")
            : String(localized: "No \(title.lowercased()) filter selected"))
        .onChange(of: selected) { _, newValue in
            commitGeneration &+= 1
            stagedSelection = newValue
            isShowingStagedSelection = false
        }
    }

    private func commitSelection(_ value: Option?) {
        commitGeneration &+= 1
        let generation = commitGeneration
        stagedSelection = value
        isShowingStagedSelection = true
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
