//
//  PadHandoff.swift
//  coderpad
//
//  Advertises the pad you're currently viewing as an `NSUserActivity` (#596), so the
//  system can Hand Off the live pad to another device, surface it in Spotlight, and
//  predict it with Siri Suggestions. A pad is web content, so the activity carries the
//  page URL as `webpageURL`: another device can hand the pad back to PadBuddy when
//  it's installed, and the app opens the URL in the user's browser.
//

import os
import SafeURLKit
import SwiftUI

enum PadActivity {
    private nonisolated static let logger = Logger(subsystem: "com.coderpad.app", category: "handoff")
    /// Must match the entry declared in `Info.plist`'s `NSUserActivityTypes`, or the
    /// system silently refuses to advertise or hand off the activity.
    static let type = "com.adamdangoor.padbuddy.viewing-pad"
    /// `userInfo` key carrying the pad's URL string, used to restore the activity even
    /// when `webpageURL` isn't consulted.
    static let urlKey = "url"

    nonisolated static func activityTitle(_ raw: String?, fallback: String) -> String {
        let bounded = String((raw ?? "").unicodeScalars.prefix(128).map { scalar -> Character in
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .surrogate, .unassigned: " "
            default: Character(scalar)
            }
        })
        let title = bounded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return title.isEmpty ? fallback : title
    }

    /// The normalized origins (scheme + host + resolved port) pad activities may
    /// point at: the hosted service plus every configured account's server.
    /// Whole origins rather than bare hostnames: an account configured for HTTPS
    /// must not have its Handoff trust extended to plain HTTP or a different
    /// port on the same host (#1152).
    @MainActor
    static var trustedPadOrigins: Set<String> {
        var origins: Set<String> = []
        for account in AccountsStore.shared.accounts {
            if let origin = origin(of: account.resolvedBaseURL) {
                origins.insert(origin)
            }
        }
        // The hosted service is always trusted, independent of the configured accounts
        // (#2688 proposed scoping this to accounts that use it). It stays: the trust
        // this grants is "open a pad-shaped path on CoderPad's own service in the
        // user's browser", which is not a meaningful attack surface — and scoping it
        // would silently drop a Handoff of a hosted pad for a user whose own accounts
        // are all self-hosted, with nothing to explain why.
        if let origin = origin(of: CoderPadClient.defaultBaseURL) {
            origins.insert(origin)
        }
        return origins
    }

    /// A URL's normalized `scheme://host:port` origin, defaulting the port from
    /// the scheme so `https://example.com` and `https://example.com:443` compare
    /// equal. Nil for non-HTTP(S) or hostless URLs.
    ///
    /// Now normalized by SafeURLKit (#1866), so the origin string is built from a
    /// parsed host rather than a textual one: `http://2130706433:80` and
    /// `http://127.0.0.1:80` produce the same origin instead of two different
    /// strings that a set comparison would treat as unrelated.
    nonisolated static func origin(of url: URL) -> String? {
        do {
            return try validatedOrigin(of: url)
        } catch {
            logger.debug("Rejected Handoff origin \(url.absoluteString, privacy: .private): \(error)")
            return nil
        }
    }

    nonisolated static func validatedOrigin(of url: URL) throws -> String {
        try originPolicy.validate(url).origin
    }

    /// The policy behind ``origin(of:)``: HTTP or HTTPS on any port, with the host
    /// merely required to be well formed.
    ///
    /// Deliberately permissive about *what kind* of host it is, unlike the app's other
    /// URL policies. A self-hosted CoderPad is routinely on a LAN address or an
    /// internal name, and Handoff's actual control is the exact-origin comparison in
    /// ``isTrustedPadURL(_:)`` against origins the user configured themselves — so
    /// refusing private addresses here would break self-hosting whilst adding nothing.
    /// Credentials are still refused: no configured account origin has them, and a URL
    /// carrying them arrived from somewhere else (#1747).
    nonisolated static let originPolicy = URLPolicy(
        allowedSchemes: ["http", "https"],
        portRule: .any,
        allowsFragment: true,
        allowsIPLiteralHosts: true,
        allowsSpecialUseHostNames: true,
        allowsSpecialPurposeAddresses: true
    )

    /// The pad a trusted Handoff URL names, together with the account whose server
    /// serves it — nil when the URL isn't a pad route on a configured origin.
    ///
    /// Handoff used to hand the URL straight to the browser, which loses the account
    /// entirely: on a multi-account or custom-server setup the receiving Mac had no
    /// way to know which account the pad came from, so it could not open the pad in
    /// its own context (#2325). The account is nil when the origin is CoderPad's
    /// default and no configured account uses it — the browser is still right then.
    @MainActor
    static func padRoute(for url: URL) -> (id: String, account: UUID?)? {
        guard isTrustedPadURL(url), let padOrigin = origin(of: url) else { return nil }
        guard let id = PadWebRoute.padID(from: url.pathComponents) else { return nil }

        // Exactly one account, or none: two accounts on one origin can't be told apart
        // from the URL, and guessing would open the pad under the wrong credentials.
        let owners = AccountsStore.shared.accounts.filter { origin(of: $0.resolvedBaseURL) == padOrigin }
        return (id, owners.count == 1 ? owners.first?.id : nil)
    }

    /// `url` reduced to scheme, host, port, and the pad path — no query, no fragment.
    /// Nil when it is not a pad route, so the caller must not advertise it.
    nonisolated static func canonicalPadURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let id = PadWebRoute.padID(from: parts) else { return nil }

        // Keep a known trailing page (e.g. /playback) so a handed-off playback view
        // resumes where it was. Unknown pages are rejected above.
        let suffixes = parts.dropFirst()
        components.path = "/" + ([id] + suffixes).joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url
    }

    @MainActor
    static func isTrustedPadURL(_ url: URL) -> Bool {
        guard let origin = origin(of: url), trustedPadOrigins.contains(origin) else {
            return false
        }

        return PadWebRoute.padID(from: url.pathComponents) != nil
    }
}

/// The pad URL carried by an incoming pad activity: the `webpageURL` (set on every
/// pad activity) with the `userInfo` string as a fallback. Returns `nil` for missing
/// or untrusted URLs, so Handoff cannot become an arbitrary external-open command.
@MainActor
func padActivityURL(_ activity: NSUserActivity) -> URL? {
    // Cap the incoming userInfo string before parsing: a real pad URL is short,
    // and a crafted multi-megabyte activity payload must not reach URL parsing
    // and the external-open path at all (#1747).
    let userInfoURL = (activity.userInfo?[PadActivity.urlKey] as? String)
        .flatMap { $0.utf8.count <= 2048 ? URL(string: $0) : nil }
    let candidate = activity.webpageURL ?? userInfoURL
    guard let candidate, candidate.absoluteString.utf8.count <= 2048,
          PadActivity.isTrustedPadURL(candidate) else { return nil }

    return candidate
}

extension View {
    /// Marks this view as advertising the pad at `url` for Handoff, Spotlight, and Siri
    /// prediction while it's on screen. `title` (the live page title when known) labels
    /// the Handoff banner and search result.
    @ViewBuilder
    func advertisesPadActivity(url: URL?, title: String?) -> some View {
        // Advertised in its canonical form: origin plus pad id, with any query and
        // fragment dropped. Only the pad's identity is needed to resume it, and the
        // full URL was being handed to Spotlight, Siri prediction, and Handoff metadata
        // — where a token or tracking parameter in the query would have been persisted
        // and synced with it (#2690).
        if let url, let advertised = PadActivity.canonicalPadURL(url) {
            userActivity(PadActivity.type) { activity in
                activity.title = PadActivity.activityTitle(title, fallback: advertised.host ?? "Pad")
                activity.targetContentIdentifier = advertised.absoluteString
                // Sets webpageURL plus the Handoff/Spotlight (and iOS-only prediction)
                // eligibility flags shared across the interview apps (BuddyAppKit).
                activity.applyBuddyHandoffFlags(webpageURL: advertised)
                activity.addUserInfoEntries(from: [PadActivity.urlKey: advertised.absoluteString])
            }
        } else {
            self
        }
    }
}
