//
//  FilterChips+SavedSearch.swift
//  coderpad
//
//  The saved-search chips and their built-in defaults. Split out of
//  FilterChips.swift so each chip family keeps its own file.
//

import SwiftUI

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
            result.append(DefaultSearch(
                id: "my-pads", icon: "person.fill",
                search: NamedSearch(name: String(localized: "My Pads"), ownerFilter: currentUserEmail)
            ))
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
            result.append(DefaultSearch(
                id: "my-questions", icon: "person.fill",
                search: NamedSearch(name: String(localized: "My Questions"), ownerFilter: currentUserEmail)
            ))
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

    /// The token shape for saved-search chips: a rounded rectangle, deliberately
    /// distinct from the filter chips' `Capsule`, so the recall tokens and the
    /// filter pills are told apart at a glance regardless of accent state (#405).
    static let tokenShape = RoundedRectangle(cornerRadius: 6, style: .continuous)

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

    /// White on the accent glass capsule (macOS 26), accent on the light fallback
    /// fill (macOS 15) while applied, primary when idle — so an applied chip's text
    /// and icon stay readable instead of accent-on-accent (#397).
    private var contentColor: AnyShapeStyle {
        isActive ? AnyShapeStyle(chipLabelColor(isActive: true)) : AnyShapeStyle(.primary)
    }

    /// The leading icon and the delete glyph: white on the accent glass capsule
    /// (macOS 26) / accent on the light fallback fill (macOS 15) while applied, and
    /// secondary when idle, so neither washes out against the applied chip (#397).
    private var iconColor: AnyShapeStyle {
        isActive ? AnyShapeStyle(chipLabelColor(isActive: true)) : AnyShapeStyle(.secondary)
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
        // `.isButton` is added below via a ternary that this rule's matcher doesn't
        // detect; the chip is correctly exposed as a button to VoiceOver.
        // swiftlint:disable:next accessibility_trait_for_button
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
                .accessibilityHidden(true)
                .foregroundStyle(iconColor)
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
                        .foregroundStyle(iconColor)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete saved search \(name)")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        // Glass on macOS 26 (accent-tinted while applied; the interactive variant
        // supplies the hover/press response the manual fill gives on 15), opaque
        // shape on 15 (#352). A rounded *rectangle* rather than the filter chips'
        // capsule, so saved-search recall tokens read as a distinct family from the
        // filter pills even when both glow accent while applied (#405).
        .chipCapsule(
            glassTint: isActive ? .accentColor : nil,
            fallbackFill: fillStyle,
            fallbackStroke: strokeColor,
            fallbackStrokeWidth: 0.5,
            in: Self.tokenShape
        )
        .contentShape(Self.tokenShape)
        .onTapGesture { onApply() }
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("Apply saved search \(name)")
    }
}
