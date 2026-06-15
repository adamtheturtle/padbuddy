//
//  DesignSystem.swift
//  coderpad
//

import AppKit
import SwiftUI

extension Color {
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let subtleStroke = Color.primary.opacity(0.08)

    /// Parses an "#RRGGBB" (or "RRGGBB") hex string into an sRGB color, or `nil` if
    /// it isn't a well-formed six-digit hex value.
    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    /// This color as an "#RRGGBB" sRGB hex string, or `nil` if it can't be resolved
    /// to fixed components (e.g. a dynamic/catalog color).
    var hexString: String? {
        guard let resolved = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((resolved.redComponent * 255).rounded())
        let g = Int((resolved.greenComponent * 255).rounded())
        let b = Int((resolved.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Shared layout constants so pane chrome stays in sync across detail views.
/// Tweak these here instead of hunting for matching literals in every view.
enum Spacing {
    /// Horizontal inset for pane content.
    static let paneH: CGFloat = 22
    /// Vertical inset for pane content (its top gap below the toolbar and its
    /// bottom padding).
    static let paneV: CGFloat = 22
    /// Interior padding for ``Card``.
    static let card: CGFloat = 16
    /// Horizontal inset for the inline banner.
    static let bannerH: CGFloat = 14
}

/// Contrast-aware opacities for the app's tinted chips and badges. Their default
/// fills are deliberately subtle; under the system "Increase Contrast"
/// accessibility setting they're raised (and the hairline stroke thickened) so
/// the controls stay legible for low-vision users.
enum ChipContrast {
    static func fill(_ base: Double, _ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? min(1, base * 2.2) : base
    }

    static func stroke(_ base: Double, _ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? min(1, base * 2.4) : base
    }

    static func lineWidth(_ contrast: ColorSchemeContrast) -> CGFloat {
        contrast == .increased ? 1 : 0.5
    }
}

/// A pad's lifecycle state. A live pad is the one status that genuinely benefits
/// from standing out, so it keeps a subtle green capsule; every other state reads
/// as restrained secondary metadata (an SF Symbol + text, see ``MetaLabel``) so the
/// list doesn't fill up with competing coloured pills.
struct StateBadge: View {
    let state: PadState
    /// Under "Increase Contrast" the subtle tinted fill/stroke are strengthened so
    /// the badge stays legible for low-vision users (see ChipContrast).
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if state == .active {
            Text(state.label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(ChipContrast.fill(0.16, contrast)), in: Capsule())
                .foregroundStyle(.green)
                .overlay(Capsule().stroke(Color.green.opacity(ChipContrast.stroke(0.25, contrast)),
                                          lineWidth: ChipContrast.lineWidth(contrast)))
        } else {
            MetaLabel(text: state.label, systemImage: state.systemImage)
        }
    }
}

struct AvatarCircle: View {
    let label: String
    var diameter: CGFloat = 32
    var tint: Color = .accentColor
    /// When set, the avatar shows this SF Symbol (tinted) instead of the initials.
    var symbol: String?

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.18))
            Circle().stroke(tint.opacity(0.25), lineWidth: 0.5)
            if let symbol, !symbol.isEmpty {
                Image(systemName: symbol)
                    .font(.system(size: diameter * 0.42, weight: .medium))
                    .foregroundStyle(tint)
            } else {
                Text(initials)
                    .font(.system(size: diameter * 0.4, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: diameter, height: diameter)
        // Decorative throughout: every avatar sits beside text that names the same
        // person or account, so the initials/symbol would only be VoiceOver noise.
        .accessibilityHidden(true)
    }

    private var initials: String {
        let parts = label
            .replacingOccurrences(of: "@", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .map(String.init)
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        let result = letters.joined().uppercased()
        return result.isEmpty ? "?" : result
    }
}

extension AvatarCircle {
    /// Builds the avatar from an account: its chosen symbol and tint when set,
    /// otherwise the name's initials on the account's default tint.
    init(account: Account, diameter: CGFloat = 32) {
        self.init(label: account.name, diameter: diameter,
                  tint: account.avatarTint, symbol: account.iconSymbol)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(Spacing.card)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.subtleStroke, lineWidth: 1))
    }
}

/// A native-feeling grouped detail section: a section header (with an optional
/// trailing accessory) over its content, separated by a hairline — no card fill or
/// border. Used for pad-detail metadata (details, participants, events) so the pane
/// reads like a native grouped list rather than a stack of dashboard cards. ``Card``
/// is reserved for genuine card affordances (code and whiteboard previews).
struct DetailSection<Content: View, Trailing: View>: View {
    let title: String
    var systemImage: String?
    let trailing: Trailing
    let content: Content

    init(title: String, systemImage: String? = nil,
         @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SectionHeader(title: title, systemImage: systemImage)
                Spacer(minLength: 0)
                trailing
            }
            Divider()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension DetailSection where Trailing == EmptyView {
    init(title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, systemImage: systemImage, trailing: { EmptyView() }, content: content)
    }
}

struct SectionHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.callout) }
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
        }
        .foregroundStyle(.secondary)
    }
}

struct LabeledRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .leading)
            if monospaced {
                Text(value).font(.callout.monospaced())
            } else {
                Text(value).font(.callout)
            }
            Spacer(minLength: 0)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var systemImage: String?
    var tint: Color = .accentColor

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .foregroundStyle(tint)
                    }
                    Text(title.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                }
                Text(value)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}

struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2)
            }
            Text(text).font(.caption)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(ChipContrast.fill(0.12, contrast)), in: Capsule())
        .foregroundStyle(tint)
        .overlay(Capsule().stroke(tint.opacity(ChipContrast.stroke(0.2, contrast)),
                                  lineWidth: ChipContrast.lineWidth(contrast)))
    }
}

/// A restrained, native-feeling metadata label: an optional SF Symbol plus
/// secondary text, with no coloured capsule. This is the default treatment for
/// informational status (account, team, language, interview type, execution…) so
/// colour stays reserved for the one or two states that genuinely need to pop —
/// see ``StateBadge`` and the few remaining tinted ``Chip`` uses (e.g. "Draft").
struct MetaLabel: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2)
            }
            Text(text).font(.caption)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(.secondary)
    }
}

extension InterviewType {
    /// SF Symbol paired with this type in metadata labels and filter menus.
    var systemImage: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .takeHome: "house"
        }
    }

    /// Standard metadata label for this type, used across list rows and detail
    /// headers. Informational, so it reads as restrained secondary text rather
    /// than a coloured pill.
    var chip: MetaLabel {
        MetaLabel(text: label, systemImage: systemImage)
    }
}

extension String {
    var languageDisplayName: String {
        switch lowercased() {
        case "python": return "Python"
        case "python2": return "Python 2"
        case "python3": return "Python 3"
        case "javascript": return "JavaScript"
        case "typescript": return "TypeScript"
        case "node", "node.js", "nodejs": return "Node.js"
        case "swift": return "Swift"
        case "go", "golang": return "Go"
        case "rust": return "Rust"
        case "java": return "Java"
        case "kotlin": return "Kotlin"
        case "ruby": return "Ruby"
        case "c": return "C"
        case "cpp", "c++": return "C++"
        case "csharp", "c#": return "C#"
        case "objective-c", "objc": return "Objective-C"
        case "php": return "PHP"
        case "html": return "HTML"
        case "css": return "CSS"
        case "sql": return "SQL"
        case "mysql": return "MySQL"
        case "postgresql", "postgres": return "PostgreSQL"
        case "bash": return "Bash"
        case "shell", "sh": return "Shell"
        case "r": return "R"
        case "scala": return "Scala"
        case "elixir": return "Elixir"
        case "erlang": return "Erlang"
        case "haskell": return "Haskell"
        case "perl": return "Perl"
        case "lua": return "Lua"
        case "dart": return "Dart"
        case "clojure": return "Clojure"
        case "ocaml": return "OCaml"
        case "f#", "fsharp": return "F#"
        case "julia": return "Julia"
        case "markdown": return "Markdown"
        case "solidity": return "Solidity"
        case "tcl": return "Tcl"
        case "verilog": return "Verilog"
        case "plaintext", "plain-text", "plain_text": return "Plain text"
        default:
            let lowered = lowercased()
            if lowered.hasPrefix("multifile_") {
                let base = String(lowered.dropFirst("multifile_".count))
                return base.isEmpty ? "Project" : base.languageDisplayName + " Project"
            }
            guard !isEmpty else { return self }
            return prefix(1).uppercased() + dropFirst()
        }
    }
}

// MARK: - CoderPad links and languages

enum CoderPadLinks {
    static let apiSettings = URL(string: "https://app.coderpad.io/dashboard/settings")!
    static let apiDocs = URL(string: "https://coderpad.io/resources/docs/coderpad-interview/api/")!

    /// Where "Send Feedback…" delivers. This is an unofficial client, so reports go
    /// to the developer rather than CoderPad.
    static let feedbackEmail = "hello@adamdangoor.com"

    /// A pre-filled feedback email addressed to the developer. The app and macOS
    /// versions are appended so each report carries the context needed to act on it;
    /// the user types their message above the divider. Falls back to a bare mailto if
    /// the query somehow fails to encode.
    static var feedbackMailto: URL {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let body = """


        ---
        App version: \(version) (\(build))
        macOS: \(os)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "CoderPad for Mac feedback"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url ?? URL(string: "mailto:\(feedbackEmail)")!
    }
}

enum CoderPadLanguages {
    static let pickerOptions: [String] = [
        "python3", "python2",
        "javascript", "typescript", "nodejs",
        "swift",
        "go",
        "rust",
        "java", "kotlin", "scala",
        "ruby",
        "c", "cpp", "csharp", "objective-c",
        "php",
        "r",
        "sql", "mysql", "postgresql",
        "bash", "shell",
        "elixir", "erlang", "haskell", "perl", "lua", "dart", "clojure", "ocaml", "fsharp",
        "julia", "solidity", "tcl", "verilog",
        "html", "css", "markdown",
        "plaintext"
    ]

    /// Where to create the project and framework environments (React, Django, Rails,
    /// and so on) that this list omits. CoderPad's pad-creation API only mints
    /// single-file language environments, so those can't be made from here; they're
    /// created in the web app instead.
    static let projectEnvironmentsURL = URL(string: "https://app.coderpad.io")!
}

/// Wall-clock scheduling for ``periodicReload``: works out when the next refresh
/// should fire on a fixed cadence, independent of how long a refresh itself takes.
enum RefreshSchedule {
    /// The next fire instant on a fixed cadence. Advances `last` by `interval`, then
    /// skips any boundaries that have already passed (a refresh ran long, or the app
    /// was inactive between ticks) so the loop realigns to the next *future* boundary
    /// instead of firing a catch-up burst. The result is always strictly after `now`,
    /// so the caller never sleeps for a non-positive duration.
    static func nextFire(after last: ContinuousClock.Instant,
                         interval: Duration,
                         now: ContinuousClock.Instant) -> ContinuousClock.Instant {
        // A non-positive interval would never advance the grid; fall back to a fixed
        // one-second cadence so the loop still makes forward progress.
        guard interval > .zero else { return now.advanced(by: .seconds(1)) }
        var fire = last.advanced(by: interval)
        // Skip boundaries already in the past. Capped so a pathological `last`/`now`
        // gap can never spin here — past the cap we simply schedule one interval out.
        var steps = 0
        while fire <= now, steps < 100_000 {
            fire = fire.advanced(by: interval)
            steps += 1
        }
        return fire > now ? fire : now.advanced(by: interval)
    }
}

/// Runs `work` immediately, then re-runs it on `interval` until the task is cancelled.
/// Cancellation breaks the loop cleanly instead of being swallowed by `try?`.
func periodicReload(interval: Duration, work: () async -> Void) async {
    await periodicReload(interval: { interval }, work: work)
}

/// Variant whose interval is recomputed after each run, letting callers stretch the
/// cadence based on how heavy the last run turned out to be — e.g. a big org with
/// thousands of pads polling far less often than a small one.
///
/// Refreshes fire on a fixed wall-clock grid anchored at the first run, so the time
/// a refresh takes doesn't push the next one out (no cumulative drift), and a long
/// gap realigns to the next boundary rather than triggering a burst (see
/// ``RefreshSchedule``).
func periodicReload(interval: () -> Duration, work: () async -> Void) async {
    let clock = ContinuousClock()
    await work()
    var last = clock.now
    while !Task.isCancelled {
        let fire = RefreshSchedule.nextFire(after: last, interval: interval(), now: clock.now)
        do {
            try await clock.sleep(until: fire, tolerance: nil)
        } catch {
            break
        }
        last = fire
        await work()
    }
}

// MARK: - ReloadToolbarButton

/// The Reload action shared by every section's window toolbar. Kept as a stable
/// `Label` (rather than swapping the whole control for a `ProgressView` while
/// loading) so the toolbar item keeps a fixed size and identity inside the
/// Liquid Glass cluster, and so the "Icon and Text" customization mode always has
/// text to show. The spinning feedback comes from a symbol effect on the icon.
struct ReloadToolbarButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Reload", systemImage: "arrow.clockwise")
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: isLoading)
        }
        .help("Reload")
        .accessibilityLabel("Reload")
        .disabled(isLoading)
    }
}
