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

    @MainActor
    static var trustedPadHosts: Set<String> {
        var hosts: Set<String> = []
        if let host = CoderPadClient.defaultBaseURL.host() {
            hosts.insert(host.lowercased())
        }
        for account in AccountsStore.shared.accounts {
            if let host = account.resolvedBaseURL.host() {
                hosts.insert(host.lowercased())
            }
        }
        return hosts
    }

    @MainActor
    static func isTrustedPadURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host()?.lowercased(),
              trustedPadHosts.contains(host) else {
            return false
        }

        return url.pathComponents.contains { $0 != "/" && !$0.isEmpty }
    }
}

/// The pad URL carried by an incoming pad activity: the `webpageURL` (set on every
/// pad activity) with the `userInfo` string as a fallback. Returns `nil` for missing
/// or untrusted URLs, so Handoff cannot become an arbitrary external-open command.
@MainActor
func padActivityURL(_ activity: NSUserActivity) -> URL? {
    let candidate = activity.webpageURL
        ?? (activity.userInfo?[PadActivity.urlKey] as? String).flatMap(URL.init(string:))
    guard let candidate, PadActivity.isTrustedPadURL(candidate) else { return nil }

    return candidate
}

extension View {
    /// Marks this view as advertising the pad at `url` for Handoff, Spotlight, and Siri
    /// prediction while it's on screen. `title` (the live page title when known) labels
    /// the Handoff banner and search result.
    func advertisesPadActivity(url: URL, title: String?) -> some View {
        userActivity(PadActivity.type) { activity in
            activity.title = (title?.isEmpty == false ? title : nil) ?? url.host ?? "Pad"
            activity.targetContentIdentifier = url.absoluteString
            // Sets webpageURL plus the Handoff/Spotlight (and iOS-only prediction)
            // eligibility flags shared across the interview apps (BuddyAppKit).
            activity.applyBuddyHandoffFlags(webpageURL: url)
            activity.addUserInfoEntries(from: [PadActivity.urlKey: url.absoluteString])
        }
    }
}
