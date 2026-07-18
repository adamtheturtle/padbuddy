#if os(macOS)
//
    //  ServicesProvider.swift
    //  coderpad
//
    //  Backs the "Open Pad in CoderPad" macOS Service. From any app — Safari, Notes,
    //  Mail — a user can select a CoderPad pad link (or id) and choose this service
    //  from the Services menu to open that pad here, without copy-pasting or switching
    //  apps first. The service is declared in Info.plist (NSServices) and registered
    //  via `NSApp.servicesProvider` at launch (see AppDelegate).
//

    import AppKit
    import Foundation

    final class ServicesProvider: NSObject {
        // The @objc Service signature and the NSPasteboard URL reader below are
        // Objective-C bridging contracts, so NSString/NSURL are required here.
        // swiftlint:disable legacy_objc_type
        /// Handles the "Open Pad in CoderPad" service. The selection is routed through
        /// the app's own `coderpad://pad/<id>` deep link via LaunchServices — the same
        /// path the Recent Pads widget and Dock menu use — so it reliably launches or
        /// activates the app and opens a window before the link is delivered, with no
        /// in-process timing race. The `NSMessage` key in Info.plist names this method.
        @objc func openPad(_ pasteboard: NSPasteboard,
                           userData _: String?,
                           error: AutoreleasingUnsafeMutablePointer<NSString>?) {
            guard let id = Self.padID(from: pasteboard) else {
                error?.pointee =
                    String(localized: "No CoderPad pad link or id was found in the selection.") as NSString
                return
            }
            // `padID` only returns PadIDValidation-normalized ids, and the link is
            // built structurally rather than by string interpolation, so nothing in
            // the selection can smuggle extra path/query semantics into the deep
            // link this generates (#1247).
            var components = URLComponents()
            components.scheme = "coderpad"
            components.host = "pad"
            components.path = "/\(id)"
            guard let deepLink = components.url else {
                // Never fail silently: the Services menu shows this to the user
                // instead of appearing to do nothing (#1937).
                error?.pointee =
                    String(localized: "The selected pad link couldn't be converted to an app link.") as NSString
                return
            }

            AppActivator.bringToFront()
            URLOpener.open(deepLink)
        }

        /// Extracts a pad id from the service pasteboard, preferring a real URL item
        /// over selected text (Safari sends both for a selected link).
        static func padID(from pasteboard: NSPasteboard) -> String? {
            let endpoints = allowedPadLinkEndpoints
            if let url = NSURL(from: pasteboard) as URL?,
               let id = padID(fromSelection: url.absoluteString, allowedEndpoints: endpoints) {
                return id
            }
            if let text = pasteboard.string(forType: .string) {
                return padID(fromSelection: text, allowedEndpoints: endpoints)
            }
            return nil
        }

        // swiftlint:enable legacy_objc_type

        /// The web endpoints (lowercased `scheme://host:port`) a selected link may
        /// point at to count as a pad link (#795): the hosted service plus every
        /// configured account's custom server. Keyed by scheme, host, AND resolved
        /// port, so two custom servers sharing a host on different ports are not
        /// interchangeable (#1248), and a plain-HTTP link can't impersonate an
        /// HTTPS-only server by spelling out its port (#1933). Anything else (an
        /// arbitrary selected URL) must not be mistaken for a pad.
        static var allowedPadLinkEndpoints: Set<String> {
            var endpoints: Set<String> = []
            if let endpoint = endpointIdentity(of: CoderPadClient.defaultBaseURL) {
                endpoints.insert(endpoint)
            }
            for account in AccountsStore.shared.accounts {
                if let endpoint = endpointIdentity(of: account.resolvedBaseURL) {
                    endpoints.insert(endpoint)
                }
            }
            return endpoints
        }

        /// A URL's lowercased `scheme://host:port` identity, defaulting the port
        /// from the scheme so `https://example.com` and `https://example.com:443`
        /// compare equal. The scheme is part of the identity: `http://host:443`
        /// must not match an HTTPS-only configured server (#1933).
        static func endpointIdentity(of url: URL) -> String? {
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let host = url.host()?.lowercased(), !host.isEmpty else { return nil }

            let port = url.port ?? (scheme == "http" ? 80 : 443)
            return "\(scheme)://\(host):\(port)"
        }

        /// Web-app routes served on the same hosts as pads (dashboard pages, auth,
        /// account management, and similar). A first path component naming one of
        /// these is app navigation, never a pad id (#1044).
        /// deny-listed defensively and broadly (#1935): a miss opens a bogus pad
        /// request, which the app then fails to load - annoying, not dangerous - so
        /// the list errs toward inclusion of plausible web-app words.
        private static let nonPadRoutes: Set<String> = [
            "about", "account", "accounts", "admin", "api", "auth", "billing", "blog",
            "callback", "candidates", "careers", "contact", "dashboard", "docs",
            "drafts", "features", "help", "integrations", "interviews", "invitations",
            "invite", "invoices", "jobs", "legal", "live", "login", "logout", "oauth",
            "onboarding", "organizations", "pads", "password", "plans", "pricing",
            "privacy", "profile", "questions", "quickstart", "register", "reports",
            "sandbox", "screen", "screens", "search", "security", "settings", "signin",
            "signout", "signup", "sso", "status", "support", "team", "teams",
            "templates", "terms", "tests", "users"
        ]

        /// Path components that may trail a pad id in a shareable pad URL, like
        /// `https://app.coderpad.io/ABC123/playback`. Anything else after the id means
        /// the link points somewhere deeper in the web app, not at a pad.
        private static let padPathSuffixes: Set<String> = ["playback"]

        /// Pure string → id extraction, kept separate so it's unit-testable. Accepts a
        /// CoderPad web URL from a known endpoint (the id is its first path component),
        /// a `coderpad://pad/<id>` deep link, or a bare alphanumeric id token. Returns
        /// nil for anything else, so selecting arbitrary prose, an unrelated web link,
        /// or a non-pad page of the CoderPad web app doesn't fire a bogus open (#795,
        /// #1044). Every branch normalizes through `PadIDValidation`, so the returned
        /// id is always a plain identifier.
        static func padID(fromSelection raw: String, allowedEndpoints: Set<String>) -> String? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
                if scheme == "coderpad" {
                    // Only the app's own pad deep-link form counts; any other
                    // coderpad:// selection must not round-trip into a new deep
                    // link, and a malformed path must not become a bogus open
                    // request (#1246).
                    guard url.host()?.lowercased() == "pad" else { return nil }

                    let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    return PadIDValidation.normalize(id)
                }
                if scheme == "http" || scheme == "https" {
                    // Only links to the hosted service or a configured custom server
                    // are pad links; any other web URL is unrelated selection (#795).
                    // Compared by host AND port (#1248).
                    guard let endpoint = endpointIdentity(of: url),
                          allowedEndpoints.contains(endpoint) else {
                        return nil
                    }

                    return padID(fromWebPathComponents: url.pathComponents)
                }
            }

            // A bare token with no URL structure: accept it as the id only when it
            // validates as one, so a sentence of selected text is ignored.
            return PadIDValidation.normalize(trimmed)
        }

        /// Extracts a pad id from an allowed-host URL's path. A pad link's path is a
        /// single slug-like component (the id), optionally followed by known pad-page
        /// suffixes like `playback`. The web app serves many non-pad routes on the same
        /// host, so the first component must also validate as a plausible pad id and
        /// not name a known app route; previously ANY first path component was taken
        /// as the id, so `.../dashboard` opened a bogus pad (#1044).
        private static func padID(fromWebPathComponents components: [String]) -> String? {
            let parts = components.filter { $0 != "/" && !$0.isEmpty }
            // At most `<id>` or `<id>/<suffix>`: a repeated or stacked suffix like
            // `/<id>/playback/playback` is not a shareable pad URL (#1936).
            guard parts.count <= 2,
                  let first = parts.first,
                  let id = PadIDValidation.normalize(first),
                  !nonPadRoutes.contains(id.lowercased()),
                  parts.dropFirst().allSatisfy({ padPathSuffixes.contains($0.lowercased()) })
            else { return nil }

            return id
        }
    }
#endif
