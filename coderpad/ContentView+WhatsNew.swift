//
//  ContentView+WhatsNew.swift
//  coderpad
//

import SwiftUI

struct WhatsNewHighlight {
    let symbol: String
    let title: String
    let body: String
}

struct WhatsNewRelease {
    let version: String
    let highlights: [WhatsNewHighlight]
}

enum WhatsNew {
    /// To ship a new release's What's New sheet:
    ///   1. Bump MARKETING_VERSION (CFBundleShortVersionString) in the build settings.
    ///      That alone re-shows the sheet — the gate reads the bundle version below,
    ///      so there is no second version constant to remember.
    ///   2. Replace `highlights` with the new release's bullets.
    /// The version shown to the user and used for gating both come from the bundle,
    /// so they can never drift out of sync with the shipped build.
    static let highlights: [WhatsNewHighlight] = [
        WhatsNewHighlight(
            symbol: "magnifyingglass",
            title: "Search across the sidebar",
            body: "Type in the new sidebar search to jump straight into Pads or Questions."
        ),
        WhatsNewHighlight(
            symbol: "person.crop.circle.badge.plus",
            title: "Accounts like Mail",
            body: "The Add Account flow auto-fills the name from your org and uses the +/− button set."
        ),
        WhatsNewHighlight(
            symbol: "bolt.horizontal",
            title: "Faster section switching",
            body: "Pads and Questions are cached per account, so switching sections shows your last data "
                + "instantly while a background reload runs."
        ),
        WhatsNewHighlight(
            symbol: "keyboard",
            title: "More shortcuts",
            body: "⌘⇧N New Question, ⌘⌥C Copy Pad URL, ⌘↩ Open Pad in Browser."
        )
    ]

    /// The app's marketing version (CFBundleShortVersionString). Drives both the
    /// sheet's title and the gate, so a version bump alone re-shows the sheet.
    /// Falls back to "0" when unreadable (e.g. the unit-test host bundle).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var current: WhatsNewRelease {
        WhatsNewRelease(version: version, highlights: highlights)
    }

    private static let key = "lastSeenWhatsNewVersion"

    static func shouldShow() -> Bool {
        let last = UserDefaults.standard.string(forKey: key)
        return last != version
    }

    static func markSeen() {
        UserDefaults.standard.set(version, forKey: key)
    }
}

struct WhatsNewSheet: View {
    let release: WhatsNewRelease
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What's New in CoderPad").font(.title2.bold())
                Text("Version \(release.version)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(0 ..< release.highlights.count, id: \.self) { index in
                    let item = release.highlights[index]
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.symbol)
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.callout.weight(.semibold))
                            Text(item.body).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                // Just dismiss; the sheet's `onDismiss` records that it was seen,
                // so every dismissal path goes through the same single place.
                Button("Continue") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(minWidth: 460)
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
            Text("Paste a CoderPad pad URL. It opens in the in-app browser window.")
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
