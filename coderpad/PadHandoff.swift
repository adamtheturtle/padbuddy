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

import SwiftUI

enum PadActivity {
    /// Must match the entry declared in `Info.plist`'s `NSUserActivityTypes`, or the
    /// system silently refuses to advertise or hand off the activity.
    static let type = "com.adamdangoor.padbuddy.viewing-pad"
    /// `userInfo` key carrying the pad's URL string, used to restore the activity even
    /// when `webpageURL` isn't consulted.
    static let urlKey = "url"

    /// The normalized origins (scheme + host + resolved port) pad activities may
    /// point at: the hosted service plus every configured account's server.
    /// Whole origins rather than bare hostnames: an account configured for HTTPS
    /// must not have its Handoff trust extended to plain HTTP or a different
    /// port on the same host (#1152).
    @MainActor
    static var trustedPadOrigins: Set<String> {
        var origins: Set<String> = []
        if let origin = origin(of: CoderPadClient.defaultBaseURL) {
            origins.insert(origin)
        }
        for account in AccountsStore.shared.accounts {
            if let origin = origin(of: account.resolvedBaseURL) {
                origins.insert(origin)
            }
        }
        return origins
    }

    /// A URL's normalized `scheme://host:port` origin, defaulting the port from
    /// the scheme so `https://example.com` and `https://example.com:443` compare
    /// equal. Nil for non-HTTP(S) or hostless URLs.
    nonisolated static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host()?.lowercased(), !host.isEmpty else { return nil }

        let port = url.port ?? (scheme == "http" ? 80 : 443)
        return "\(scheme)://\(host):\(port)"
    }

    /// Web-app routes served on the same origins as pads; a first path component
    /// naming one of these is app navigation, never a pad. Mirrors the Open Pad
    /// service's list (#1044).
    private static let nonPadRoutes: Set<String> = [
        "account", "accounts", "admin", "api", "billing", "candidates", "dashboard",
        "docs", "help", "interviews", "login", "logout", "pads", "profile",
        "questions", "register", "sandbox", "screen", "screens", "settings",
        "signup", "team", "teams", "users"
    ]

    /// Path components that may trail a pad id in a shareable pad URL.
    private static let padPathSuffixes: Set<String> = ["playback"]

    @MainActor
    static func isTrustedPadURL(_ url: URL) -> Bool {
        guard let origin = origin(of: url), trustedPadOrigins.contains(origin) else {
            return false
        }

        // The activity type claims to restore a pad, so the path must actually be
        // a pad route — a single id-shaped component (optionally + a known pad
        // page like /playback) — not /dashboard, /admin, or any other same-origin
        // page an incoming activity happens to name (#1153).
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let first = parts.first,
              let id = PadIDValidation.normalize(first),
              !nonPadRoutes.contains(id.lowercased()),
              parts.dropFirst().allSatisfy({ padPathSuffixes.contains($0.lowercased()) })
        else { return false }

        return true
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
        .flatMap { $0.count <= 2048 ? URL(string: $0) : nil }
    let candidate = activity.webpageURL ?? userInfoURL
    guard let candidate, PadActivity.isTrustedPadURL(candidate) else { return nil }

    return candidate
}

extension View {
    /// Marks this view as advertising the pad at `url` for Handoff, Spotlight, and Siri
    /// prediction while it's on screen. `title` (the live page title when known) labels
    /// the Handoff banner and search result.
    @ViewBuilder
    func advertisesPadActivity(url: URL?, title: String?) -> some View {
        if let url {
            userActivity(PadActivity.type) { activity in
                activity.title = (title?.isEmpty == false ? title : nil) ?? url.host ?? "Pad"
                activity.targetContentIdentifier = url.absoluteString
                // Sets webpageURL plus the Handoff/Spotlight (and iOS-only prediction)
                // eligibility flags shared across the interview apps (BuddyAppKit).
                activity.applyBuddyHandoffFlags(webpageURL: url)
                activity.addUserInfoEntries(from: [PadActivity.urlKey: url.absoluteString])
            }
        } else {
            self
        }
    }
}
