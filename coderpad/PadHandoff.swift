//
//  PadHandoff.swift
//  coderpad
//
//  Advertises the pad you're currently viewing as an `NSUserActivity` (#596), so the
//  system can Hand Off the live pad to another device, surface it in Spotlight, and
//  predict it with Siri Suggestions. A pad is web content, so the activity carries the
//  page URL as `webpageURL`: another device hands off straight into PadBuddy's in-app
//  browser when it's installed, and falls back to opening the URL in Safari when it
//  isn't. Restoration routes through the same `pad-browser` window the rest of the app
//  opens pads into (see the scene `onContinueUserActivity` handlers).
//

import SwiftUI

enum PadActivity {
    /// Must match the entry declared in `Info.plist`'s `NSUserActivityTypes`, or the
    /// system silently refuses to advertise or hand off the activity.
    static let type = "com.adamdangoor.padbuddy.viewing-pad"
    /// `userInfo` key carrying the pad's URL string, used to restore the activity even
    /// when `webpageURL` isn't consulted.
    static let urlKey = "url"
}

/// The pad URL carried by an incoming pad activity: the `webpageURL` (set on every
/// pad activity) with the `userInfo` string as a fallback. Returns `nil` for an
/// activity that carries neither, so the scene handlers can ignore it.
@MainActor
func padActivityURL(_ activity: NSUserActivity) -> URL? {
    if let url = activity.webpageURL { return url }
    if let string = activity.userInfo?[PadActivity.urlKey] as? String { return URL(string: string) }
    return nil
}

extension View {
    /// Marks this view as advertising the pad at `url` for Handoff, Spotlight, and Siri
    /// prediction while it's on screen. `title` (the live page title when known) labels
    /// the Handoff banner and search result.
    func advertisesPadActivity(url: URL, title: String?) -> some View {
        userActivity(PadActivity.type) { activity in
            activity.title = (title?.isEmpty == false ? title : nil) ?? url.host ?? "Pad"
            activity.webpageURL = url
            activity.targetContentIdentifier = url.absoluteString
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
            // Siri prediction / Suggestions is an iOS-only eligibility flag.
            #if !os(macOS)
                activity.isEligibleForPrediction = true
            #endif
            activity.addUserInfoEntries(from: [PadActivity.urlKey: url.absoluteString])
        }
    }
}
