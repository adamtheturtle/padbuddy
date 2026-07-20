//
//  DesignSystem+Glass.swift
//  coderpad
//
//  Most Liquid Glass styling now uses SwiftUI 26 APIs directly. This keeps the
//  app-coupled "Get an API key" link, which depends on the CoderPad-specific
//  `CoderPadLinks`.
//

import SwiftUI

extension View {
    @ViewBuilder
    func glassActionButtonStyle() -> some View {
        #if os(visionOS)
            buttonStyle(.bordered)
        #else
            buttonStyle(.glass)
        #endif
    }

    @ViewBuilder
    func prominentActionButtonStyle() -> some View {
        #if os(visionOS)
            buttonStyle(.borderedProminent)
        #else
            buttonStyle(.glassProminent)
        #endif
    }

    @ViewBuilder
    func glassCapsule(tint: Color? = nil) -> some View {
        #if os(visionOS)
            background(.regularMaterial, in: Capsule())
        #else
            glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: Capsule())
        #endif
    }

    @ViewBuilder
    func selectableGlassRoundedRectangle(isSelected: Bool) -> some View {
        #if os(visionOS)
            background(isSelected ? Color.accentColor.opacity(0.24) : Color.clear,
                       in: .rect(cornerRadius: 12))
        #else
            glassEffect(isSelected ? .regular.tint(.accentColor.opacity(0.24)) : .regular.interactive(),
                        in: .rect(cornerRadius: 12))
        #endif
    }
}

struct GetAPIKeyLink: View {
    var prominent: Bool = false

    /// Drive the open explicitly through the environment action rather than a bare
    /// `Link`. On iPad a `Link` to an external URL can silently no-op (#552); calling
    /// `openURL` from a `Button` opens the browser reliably on both macOS and iPadOS.
    @Environment(\.openURL) private var openURL

    var body: some View {
        let button = Button {
            openURL(CoderPadLinks.apiSettings)
        } label: {
            Label("Get an API key from CoderPad", systemImage: "key.viewfinder")
        }

        if prominent {
            button.prominentActionButtonStyle()
        } else {
            // Borderless keeps the chromeless, accent-tinted hyperlink look the old
            // `Link` had on both macOS and iPadOS, rather than a bordered push button.
            button.buttonStyle(.borderless)
        }
    }
}
