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
