//
//  DesignSystem+Glass.swift
//  coderpad
//
//  The generic Liquid Glass primitives (floatingGlass / chipCapsule / glass button
//  styles / chipLabelColor / GlassCluster) now live in the CoderPadDesignSystem
//  package (#377). This keeps the app-coupled "Get an API key" link, which depends
//  on the CoderPad-specific `CoderPadLinks`.
//

import SwiftUI

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
            button.prominentGlassButtonStyle()
        } else {
            // Borderless keeps the chromeless, accent-tinted hyperlink look the old
            // `Link` had on both macOS and iPadOS, rather than a bordered push button.
            button.buttonStyle(.borderless)
        }
    }
}
