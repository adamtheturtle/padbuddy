import Foundation

/// Shared pad path classification for Handoff and the Open Pad service.
enum PadWebRoute {
    /// Web-app routes served on the same hosts as pads (dashboard pages, auth,
    /// account management, and similar). A first path component naming one of
    /// these is app navigation, never a pad id (#1044).
    /// deny-listed defensively and broadly (#1935): a miss opens a bogus pad
    /// request, which the app then fails to load - annoying, not dangerous - so
    /// the list errs toward inclusion of plausible web-app words.
    private nonisolated static let nonPadRoutes: Set<String> = [
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
    private nonisolated static let padPathSuffixes: Set<String> = ["playback"]

    /// Extracts a pad id from an allowed-host URL's path. A pad link's path is a
    /// single slug-like component (the id), optionally followed by known pad-page
    /// suffixes like `playback`. The web app serves many non-pad routes on the same
    /// host, so the first component must also validate as a plausible pad id and
    /// not name a known app route; previously ANY first path component was taken
    /// as the id, so `.../dashboard` opened a bogus pad (#1044).
    nonisolated static func padID(from components: [String]) -> String? {
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
