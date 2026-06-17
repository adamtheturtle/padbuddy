//
//  DesignSystem+Glass.swift
//  coderpad
//

import SwiftUI

struct GetAPIKeyLink: View {
    var prominent: Bool = false
    var body: some View {
        Link(destination: CoderPadLinks.apiSettings) {
            Label("Get an API key from CoderPad", systemImage: "key.viewfinder")
        }
        .if(prominent) { $0.prominentGlassButtonStyle() }
    }
}

private extension View {
    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition { transform(self) } else { self }
    }
}

extension View {
    /// Backs the view with Liquid Glass in `shape` on macOS 26, falling back to
    /// `fallback` painted in the same shape on macOS 15. Reserved for the
    /// control/overlay layer that floats *above* content — inline search fields,
    /// embedded-browser toolbars, floating panels. Per Apple's guidance, dense
    /// content surfaces (cards, list rows, badges, chips) keep an opaque material
    /// instead, so glass never stacks on glass or sits behind body text.
    ///
    /// Pass `interactive: true` for glass that backs a control the user presses,
    /// so it gains the same responsive ripple the system gives `.buttonStyle(.glass)`.
    @ViewBuilder
    func floatingGlass(
        in shape: some Shape,
        fallback: some ShapeStyle,
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(fallback, in: shape)
        }
    }

    /// Backs a filter chip with a capsule that reads as a distinct control. On
    /// macOS 26 the idle chip gets interactive Liquid Glass (and an accent-tinted
    /// glass when its filter is set), so a row of chips floats above the list as a
    /// clear functional layer rather than bare text + chevron (#352 — the owner
    /// wants these to plainly read as controls, and prioritises the Tahoe look).
    /// On macOS 15 it falls back to the opaque capsule fill + hairline stroke the
    /// chips have always used. The filter bar sits in the control layer above the
    /// list content, so glass here matches Apple's guidance even though dense
    /// *content*-layer surfaces (cards, list rows, badges) still keep flat material.
    ///
    /// `shape` defaults to a `Capsule` (the filter chips' pill); the saved-search
    /// chips pass a rounded rectangle so the two chip families read as visibly
    /// different controls — recall "tokens" versus filter "pills" (#405).
    @ViewBuilder
    func chipCapsule(
        glassTint: Color?,
        fallbackFill: some ShapeStyle,
        fallbackStroke: Color,
        fallbackStrokeWidth: CGFloat,
        in shape: some Shape = Capsule()
    ) -> some View {
        if #available(macOS 26, *) {
            let glass: Glass = (glassTint.map { Glass.regular.tint($0) } ?? .regular).interactive()
            glassEffect(glass, in: shape)
        } else {
            background(fallbackFill, in: shape)
                .overlay(shape.stroke(fallbackStroke, lineWidth: fallbackStrokeWidth))
        }
    }

    /// Applies the Liquid Glass button style to every button in this subtree on
    /// macOS 26, leaving the macOS 15 appearance untouched (`.automatic`). Intended
    /// for a row of icon controls grouped in a ``GlassCluster`` so they read as one
    /// floating set, rather than buttons already resting on a glass surface.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.automatic)
        }
    }

    /// Prominent call-to-action style: prominent Liquid Glass on macOS 26,
    /// `.borderedProminent` on macOS 15 — so existing prominent buttons keep their
    /// look on Sequoia while gaining glass on Tahoe.
    @ViewBuilder
    func prominentGlassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

/// The readable label colour for a filter chip given whether its filter is set.
/// An idle chip uses `.primary`. A *set* chip on macOS 26 wears accent-tinted
/// (saturated) glass via ``chipCapsule``, so its label must be white — the same
/// pairing the system uses for `.glassProminent` — because accent text on the
/// accent capsule is unreadable (#397). On macOS 15 the set chip instead wears a
/// light-accent fill, where the accent label reads fine, so it keeps the accent.
@MainActor
func chipLabelColor(isActive: Bool) -> Color {
    guard isActive else { return .primary }

    if #available(macOS 26, *) {
        return .white
    }
    return .accentColor
}

/// Groups several `glassEffect`/glass-styled controls so the system can blend and
/// morph them as a single Liquid Glass shape on macOS 26. On macOS 15 it's a plain
/// passthrough, so the same call site compiles and lays out identically there.
struct GlassCluster<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
