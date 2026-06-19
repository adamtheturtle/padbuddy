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
