//
//  WelcomePreviews.swift
//  coderpad
//

import SwiftUI

private struct WelcomePreviewHost: View {
    let size: CGSize

    var body: some View {
        PadBuddyWelcomeView(onAddAccount: {})
            .frame(width: size.width, height: size.height)
    }
}

#Preview("Welcome — Regular") {
    WelcomePreviewHost(size: CGSize(width: 900, height: 600))
}

#Preview("Welcome — Compact") {
    WelcomePreviewHost(size: CGSize(width: 480, height: 600))
}

#Preview("Welcome — Dark") {
    WelcomePreviewHost(size: CGSize(width: 900, height: 600))
        .preferredColorScheme(.dark)
}
