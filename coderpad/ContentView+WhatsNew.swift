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

    @State private var parsedURL: URL?

    private static func parseURL(_ urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmed).flatMap { $0.scheme != nil ? $0 : nil }
    }

    var body: some View {
        #if os(iOS)
            NavigationStack {
                sheetFields
                    .padding()
                    .navigationTitle("Open Pad by URL")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { sheetToolbar }
            }
        #else
            VStack(alignment: .leading, spacing: 14) {
                Text("Open Pad by URL").font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                sheetFields
                actionButtons
            }
            .padding()
            .frame(minWidth: 480)
        #endif
    }

    private var sheetFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste a CoderPad pad URL. It opens in your browser.")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField("https://app.coderpad.io/…", text: $urlString)
                .textFieldStyle(.roundedBorder)
                .onChange(of: urlString, initial: true) { _, newValue in
                    parsedURL = Self.parseURL(newValue)
                }
                .onSubmit { if let url = parsedURL { onSubmit(url) } }
        }
    }

    private var actionButtons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
            openButton
        }
    }

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel, action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
            openButton
        }
    }

    private var openButton: some View {
        Button("Open") {
            if let url = parsedURL { onSubmit(url) }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(parsedURL == nil)
    }
}
