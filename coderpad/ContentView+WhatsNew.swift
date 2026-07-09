//
//  ContentView+WhatsNew.swift
//  coderpad
//

import SwiftUI
import WhatsNewKit

/// The What's New content for the current release, built on WhatsNewKit.
///
/// To ship a new release's What's New sheet:
///   1. Bump MARKETING_VERSION (CFBundleShortVersionString) in the build settings.
///      WhatsNewKit gates on the bundle version via `WhatsNew.Version.current()`, so a
///      bump alone re-shows the sheet - there is no second version constant to remember.
///   2. Replace `features` with the new release's bullets.
///
/// The strings go through `String(localized:)` so they stay in the String Catalog even
/// though WhatsNewKit's `Text` takes a plain `String` rather than a `LocalizedStringKey`.
enum WhatsNewContent {
    static var current: WhatsNew {
        WhatsNew(
            version: .current(),
            title: WhatsNew.Title(
                text: WhatsNew.Text(String(localized: "What's New in PadBuddy"))
            ),
            features: [
                WhatsNew.Feature(
                    image: .init(systemName: "magnifyingglass"),
                    title: .init(String(localized: "Search across the sidebar")),
                    subtitle: .init(String(localized:
                        "Type in the new sidebar search to jump straight into Pads or Questions."))
                ),
                WhatsNew.Feature(
                    image: .init(systemName: "person.crop.circle.badge.plus"),
                    title: .init(String(localized: "Accounts like Mail")),
                    subtitle: .init(String(localized:
                        "The Add Account flow auto-fills the name from your org and uses the +/− button set."))
                ),
                WhatsNew.Feature(
                    image: .init(systemName: "bolt.horizontal"),
                    title: .init(String(localized: "Faster section switching")),
                    subtitle: .init(String(localized:
                        // swiftlint:disable:next line_length
                        "Pads and Questions are cached per account, so switching sections shows your last data instantly while a background reload runs."))
                ),
                WhatsNew.Feature(
                    image: .init(systemName: "keyboard"),
                    title: .init(String(localized: "More shortcuts")),
                    subtitle: .init(String(localized:
                        "⌘⇧N New Question, ⌘⌥C Copy Pad URL, ⌘↩ Open Pad in Browser."))
                )
            ],
            primaryAction: WhatsNew.PrimaryAction(
                title: .init(String(localized: "Continue"))
            )
        )
    }
}

struct OpenPadURLSheet: View {
    @Binding var urlString: String
    let onSubmit: (URL) -> Void
    let onCancel: () -> Void

    private var trimmed: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedURL: URL? {
        URL(string: trimmed).flatMap { $0.scheme != nil ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Open Pad by URL").font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Paste a CoderPad pad URL. It opens in your browser.")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField("https://app.coderpad.io/…", text: $urlString)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if let url = parsedURL { onSubmit(url) } }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Open") {
                    if let url = parsedURL { onSubmit(url) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsedURL == nil)
            }
        }
        .padding()
        .frame(minWidth: 480)
    }
}
