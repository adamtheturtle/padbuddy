//
//  ScreenSectionView.swift
//  coderpad
//
//  The CoderPad Screen section (campaigns and test sessions). Phase 1 scaffolding
//  (#432): placeholder list + detail columns, gated on the account having a Screen
//  key. The campaigns list, test-session list, and report detail land in #433+.
//

import SwiftUI

/// The Screen section's list (content) column. A placeholder for now — the campaigns
/// list replaces it in #433.
struct ScreenSectionPlaceholder: View {
    var body: some View {
        ContentUnavailableView {
            Label("Screen", systemImage: "person.crop.rectangle.stack")
        } description: {
            Text("Campaigns and test sessions will appear here.")
        }
    }
}

/// The Screen section's detail column placeholder, shown until a campaign/test session
/// is selectable (#434+).
struct ScreenDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView("Select a campaign", systemImage: "person.crop.rectangle.stack")
    }
}

#Preview("Screen placeholder") {
    ScreenSectionPlaceholder()
        .frame(width: 480, height: 360)
}
