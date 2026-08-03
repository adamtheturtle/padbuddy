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
    static let current = WhatsNew(
        version: .current(),
        title: WhatsNew.Title(
            text: WhatsNew.Text(String(localized: "What's New in PadBuddy"))
        ),
        features: [
            WhatsNew.Feature(
                image: .init(systemName: "folder.badge.plus"),
                title: .init(String(localized: "Multi-file question authoring")),
                subtitle: .init(String(localized: """
                Create multi-file starter projects or explicitly replace an existing question's project files.
                """))
            ),
            WhatsNew.Feature(
                image: .init(systemName: "magnifyingglass"),
                title: .init(String(localized: "Search across the sidebar")),
                subtitle: .init(String(localized:
                    "Type in the new sidebar search to jump straight into Pads or Questions."))
            ),
            WhatsNew.Feature(
                image: .init(systemName: "person.crop.circle.badge.plus"),
                title: .init(String(localized: "Easier account setup")),
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

struct OpenPadURLSheet: View {
    @Binding var urlString: String
    let onSubmit: (URL) -> Void
    let onCancel: () -> Void

    @State private var parsedURL: URL?
    /// Why the current text can't be opened, or nil while it is blank or valid.
    @State private var problem: String?

    /// The pad URL `urlString` names, or the reason it isn't one.
    ///
    /// This used to accept any URL carrying a scheme, so despite the sheet's
    /// CoderPad-specific copy it would happily hand `file:///…`, a custom scheme, or
    /// an unrelated site to the browser (#2163) — including one with an embedded
    /// username and password, which would then be written into browser history and
    /// sent to whatever host it named (#2164). Failures now say which part is wrong
    /// instead of silently disabling Open (#2165).
    static func parse(_ urlString: String) -> ParseOutcome {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure("")
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return .failure(String(localized: "That does not look like a web address."))
        }
        guard scheme == "https" || scheme == "http" else {
            return .failure(String(localized: "Only https web addresses can be opened."))
        }
        guard let host = url.host(), !host.isEmpty else {
            return .failure(String(localized: "That address is missing a server name."))
        }
        guard url.user() == nil, url.password() == nil else {
            return .failure(String(localized: """
            That address has a username or password in it. Remove them before opening it.
            """))
        }

        // The path has to name a pad, not the site's own pages — the same rule Handoff
        // and the Services item apply.
        guard PadActivity.canonicalPadURL(url) != nil else {
            return .failure(String(localized: "That address does not point to a pad."))
        }

        return .success(url)
    }

    /// A parsed pad URL, or the reason the text isn't one. Empty reason means the
    /// field is simply blank.
    enum ParseOutcome: Equatable {
        case success(URL)
        case failure(String)
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
                    switch Self.parse(newValue) {
                    case let .success(url):
                        parsedURL = url
                        problem = nil

                    case let .failure(reason):
                        parsedURL = nil
                        // hasn't typed yet.
                        // has not typed yet.
                        problem = reason.isEmpty ? nil : reason
                    }
                }
                .onSubmit { if let url = parsedURL { onSubmit(url) } }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
