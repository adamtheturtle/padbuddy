//
//  DesignSystem.swift
//  coderpad
//

import AppKit
import MarkdownUI
import SwiftUI

extension Color {
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let subtleStroke = Color.primary.opacity(0.08)
}

/// Shared layout constants so pane chrome stays in sync across detail views.
/// Tweak these here instead of hunting for matching literals in every view.
enum Spacing {
    /// Horizontal inset for pane content, matched to ``PaneTitle``.
    static let paneH: CGFloat = 22
    /// ``PaneTitle``'s top inset.
    static let paneTitleTop: CGFloat = 18
    /// ``PaneTitle``'s bottom inset.
    static let paneTitleBottom: CGFloat = 10
    /// Vertical inset for pane content (below a ``PaneTitle`` or search field).
    static let paneV: CGFloat = 22
    /// Interior padding for ``Card``.
    static let card: CGFloat = 16
    /// Horizontal inset for the inline banner.
    static let bannerH: CGFloat = 14
}

/// Shared typography so matching text styles stay in sync across views.
enum Typography {
    /// The large title shown by ``PaneTitle`` at the top of a pane.
    static let paneTitle: Font = .largeTitle.bold()
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

struct StateBadge: View {
    let state: PadState
    /// Under "Increase Contrast" the subtle tinted fill/stroke are strengthened so
    /// the badge stays legible for low-vision users (see ChipContrast).
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(state.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(ChipContrast.fill(0.16, contrast)), in: Capsule())
            .foregroundStyle(tint)
            .overlay(Capsule().stroke(tint.opacity(ChipContrast.stroke(0.25, contrast)),
                                      lineWidth: ChipContrast.lineWidth(contrast)))
    }

    private var tint: Color {
        switch state {
        case .active: .green
        case .ended: .gray
        case .pending: .orange
        case .deleted: .red
        case .other: .accentColor
        }
    }
}

struct AvatarCircle: View {
    let label: String
    var diameter: CGFloat = 32
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.18))
            Circle().stroke(tint.opacity(0.25), lineWidth: 0.5)
            Text(initials)
                .font(.system(size: diameter * 0.4, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: diameter, height: diameter)
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

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(Spacing.card)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.subtleStroke, lineWidth: 1))
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
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(ChipContrast.fill(0.12, contrast)), in: Capsule())
        .foregroundStyle(tint)
        .overlay(Capsule().stroke(tint.opacity(ChipContrast.stroke(0.2, contrast)),
                                  lineWidth: ChipContrast.lineWidth(contrast)))
    }
}

extension InterviewType {
    /// SF Symbol paired with this type in chips and filter menus.
    var systemImage: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .takeHome: "house"
        }
    }

    /// Accent color for this type's chip.
    var tint: Color {
        switch self {
        case .live: .green
        case .takeHome: .pink
        }
    }

    /// Standard badge for this type, used across list rows and detail headers.
    var chip: Chip {
        Chip(text: label, systemImage: systemImage, tint: tint)
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
        "html", "css",
        "plaintext"
    ]
}

/// Runs `work` immediately, then re-runs it on `interval` until the task is cancelled.
/// Cancellation breaks the loop cleanly instead of being swallowed by `try?`.
func periodicReload(interval: Duration, work: () async -> Void) async {
    await periodicReload(interval: { interval }, work: work)
}

/// Variant whose interval is recomputed after each run, letting callers stretch the
/// cadence based on how heavy the last run turned out to be — e.g. a big org with
/// thousands of pads polling far less often than a small one.
func periodicReload(interval: () -> Duration, work: () async -> Void) async {
    await work()
    while !Task.isCancelled {
        do {
            try await Task.sleep(for: interval())
        } catch {
            break
        }
        await work()
    }
}

struct PaneTitle<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.paneTitle)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.paneH)
        .padding(.top, Spacing.paneTitleTop)
        .padding(.bottom, Spacing.paneTitleBottom)
    }
}

extension PaneTitle where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
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
