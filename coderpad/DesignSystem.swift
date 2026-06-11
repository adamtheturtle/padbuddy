//
//  DesignSystem.swift
//  coderpad
//

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

struct StateBadge: View {
    let state: String

    var body: some View {
        Text(state.capitalized)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
            .overlay(Capsule().stroke(tint.opacity(0.25), lineWidth: 0.5))
    }

    private var tint: Color {
        switch state.lowercased() {
        case "started", "active", "live": return .green
        case "ended", "finished": return .gray
        case "pending", "draft": return .orange
        case "joined": return .blue
        case "left": return .secondary
        case "deleted": return .red
        default: return .accentColor
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
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(Spacing.card)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.subtleStroke, lineWidth: 1))
    }
}

struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil

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
    var systemImage: String? = nil
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
    var systemImage: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2)
            }
            Text(text).font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
        .foregroundStyle(tint)
        .overlay(Capsule().stroke(tint.opacity(0.2), lineWidth: 0.5))
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
    var chip: Chip { Chip(text: label, systemImage: systemImage, tint: tint) }
}

extension String {
    var languageColor: Color {
        switch self.lowercased() {
        case "python", "python3": return .blue
        case "javascript", "typescript", "node", "node.js": return .yellow
        case "swift": return .orange
        case "go", "golang": return .cyan
        case "rust": return .brown
        case "java", "kotlin": return .red
        case "ruby": return .pink
        case "c", "cpp", "c++", "objective-c": return .gray
        default: return .accentColor
        }
    }

    var languageDisplayName: String {
        switch self.lowercased() {
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
            let lowered = self.lowercased()
            if lowered.hasPrefix("multifile_") {
                let base = String(lowered.dropFirst("multifile_".count))
                return base.languageDisplayName + " Project"
            }
            guard !self.isEmpty else { return self }
            return self.prefix(1).uppercased() + self.dropFirst()
        }
    }

    var languageSymbol: String {
        switch self.lowercased() {
        case "html", "css", "javascript", "typescript", "node", "node.js", "nodejs":
            return "globe"
        case "python", "python2", "python3", "ruby", "perl", "lua", "r", "bash", "shell", "sh":
            return "terminal"
        case "swift", "objective-c", "objc":
            return "swift"
        case "go", "golang", "rust", "c", "cpp", "c++", "csharp", "c#", "java", "kotlin", "scala":
            return "cpu"
        case "sql", "mysql", "postgresql", "postgres":
            return "cylinder"
        case "haskell", "elixir", "erlang", "clojure", "ocaml", "f#", "fsharp":
            return "function"
        case "dart":
            return "iphone"
        case "php":
            return "globe.americas"
        case "plaintext", "plain-text", "plain_text":
            return "doc.plaintext"
        default:
            let lowered = self.lowercased()
            if lowered.hasPrefix("multifile_") {
                return String(lowered.dropFirst("multifile_".count)).languageSymbol
            }
            return "chevron.left.slash.chevron.right"
        }
    }
}

// MARK: - GetAPIKeyLink

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
    var subtitle: String? = nil
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

struct GetAPIKeyLink: View {
    var prominent: Bool = false
    var body: some View {
        Link(destination: CoderPadLinks.apiSettings) {
            Label("Get an API key from CoderPad", systemImage: "key.viewfinder")
        }
        .if(prominent) { $0.buttonStyle(.borderedProminent) }
    }
}

extension View {
    @ViewBuilder
    fileprivate func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - MarkdownText

/// Renders GitHub-flavored Markdown via swift-markdown-ui, themed to match the
/// app's typography. Call sites are unchanged: `MarkdownText(raw)`.
struct MarkdownText: View {
    let raw: String

    init(_ raw: String) {
        self.raw = raw
    }

    var body: some View {
        if raw.isEmpty {
            Text("(empty)").foregroundStyle(.secondary)
        } else {
            Markdown(raw)
                .markdownTheme(.coderpad)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension Theme {
    /// Approximates the app's previous hand-rolled Markdown styling: bold
    /// headings, monospaced inline/code blocks, and a subtle code-block fill.
    static let coderpad = Theme()
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.9))
        }
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.8), bottom: .em(0.4))
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.5))
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.8), bottom: .em(0.4))
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.3))
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.8), bottom: .em(0.4))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.15))
                }
        }
        .codeBlock { configuration in
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.9))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.subtleStroke.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .markdownMargin(top: .em(0.5), bottom: .em(0.5))
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
}

#Preview("MarkdownText") {
    ScrollView {
        MarkdownText(
            """
            # Reverse a Linked List
            Implement a function that reverses a singly linked list **in place**.

            ## Requirements
            - Run in `O(n)` time and `O(1)` extra space
            - Handle the *empty list* and single-node cases
            - Return the new head

            ### Example
            Given `1 -> 2 -> 3`, return `3 -> 2 -> 1`.

            1. Walk the list
            2. Re-point each `next`
            3. Track the previous node

            ```swift
            func reverse(_ head: Node?) -> Node? {
                var prev: Node? = nil
                var node = head
                while let current = node {
                    node = current.next
                    current.next = prev
                    prev = current
                }
                return prev
            }
            ```

            | Case | Input | Output |
            | --- | --- | --- |
            | Empty | `nil` | `nil` |
            | Single | `1` | `1` |
            """
        )
        .padding()
    }
    .frame(width: 460, height: 640)
}

// MARK: - EmailLink

struct EmailLink: View {
    let email: String

    var body: some View {
        if email.isEmpty {
            Text("(no email)").foregroundStyle(.secondary)
        } else if let url = URL(string: "mailto:\(email)") {
            Link(email, destination: url)
        } else {
            Text(email)
        }
    }
}

// MARK: - Org directory (email -> name lookup)

@Observable
final class OrgDirectory {
    private(set) var nameByEmail: [String: String] = [:]
    private var loadedAccountID: UUID?
    private var inFlight: UUID?

    func load(for account: Account) async {
        guard loadedAccountID != account.id, inFlight != account.id else { return }
        inFlight = account.id
        defer { inFlight = nil }
        let client = account.isMock ? CoderPadClient.mock() : CoderPadClient.live(apiKey: account.apiKey, baseURL: account.resolvedBaseURL)
        if let org = try? await client.organization() {
            var map: [String: String] = [:]
            for user in org.users {
                if let name = user.name, !name.isEmpty {
                    map[user.email] = name
                }
            }
            nameByEmail = map
            loadedAccountID = account.id
        }
    }

    func name(for email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return nameByEmail[trimmed]
    }

    func display(_ email: String) -> String {
        name(for: email) ?? email
    }
}

private struct OrgDirectoryKey: EnvironmentKey {
    static let defaultValue = OrgDirectory()
}

extension EnvironmentValues {
    var orgDirectory: OrgDirectory {
        get { self[OrgDirectoryKey.self] }
        set { self[OrgDirectoryKey.self] = newValue }
    }
}

// MARK: - Filter bar width measurement

/// Carries the natural (unclipped) width of a filter bar up the view tree so the
/// enclosing split-view column can refuse to shrink below it. Reduces to the
/// widest reporter, and never below a sensible floor.
struct FilterBarWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 380
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Measures this view's laid-out width and reports it via `FilterBarWidthKey`.
    /// Attach either to a horizontally-scrolling filter bar's content (so the
    /// measured value is the chips' natural row width) or to each individual chip
    /// in a wrapping filter bar — because the key reduces by `max`, the per-chip
    /// case yields the widest single chip, the right floor for a bar that wraps.
    func measuresFilterBarWidth() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: FilterBarWidthKey.self, value: proxy.size.width)
            }
        )
    }
}

// MARK: - Flow layout

/// Arranges its subviews left-to-right, wrapping to a new line whenever the next
/// subview would overflow the available width. Lets a row of filter chips reflow
/// onto multiple lines as its container narrows, instead of being clipped or
/// forcing a horizontal scroll.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                widestRow = max(widestRow, x - spacing)
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        widestRow = max(widestRow, x - spacing)
        let width = maxWidth.isFinite ? maxWidth : widestRow
        return CGSize(width: max(0, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Searchable filter chip

struct SearchableFilterChip: View {
    let title: String
    let icon: String
    @Binding var selected: String?
    let options: [String]
    let formatter: (String) -> String
    /// When set, a "Me" shortcut is pinned to the top of the popover and the
    /// chip reads "Me" while this value is selected. Nil hides the shortcut
    /// (e.g. when the account has no known user email).
    var meEmail: String? = nil

    @State private var presented = false
    @State private var search = ""

    private var chipText: String {
        guard let selected else { return title }
        if let meEmail, selected == meEmail { return "Me" }
        return formatter(selected)
    }

    private var accessibilityHint: String {
        if let selected { return "Filter applied: \(formatter(selected)). Activate to change." }
        return "No \(title.lowercased()) filter. Activate to choose one."
    }

    private var filtered: [String] {
        let q = search.lowercased()
        guard !q.isEmpty else { return options }
        return options.filter {
            formatter($0).lowercased().contains(q) || $0.lowercased().contains(q)
        }
    }

    // Explicitly-typed style helpers keep the `body` type-checker from
    // exploring these ternaries combinatorially (was ~6s to type-check).
    private var isActive: Bool { selected != nil }
    // Idle state is transparent so this chip matches the borderless `Menu`-based
    // FilterChipMenu chips, which don't paint a capsule fill until a filter is set.
    private var fillColor: Color { isActive ? Color.accentColor.opacity(0.18) : Color.clear }
    private var strokeColor: Color { isActive ? Color.accentColor.opacity(0.4) : Color.clear }
    private var labelColor: Color { isActive ? Color.accentColor : Color.primary }

    var body: some View {
        // A plain tappable label rather than a `Button`: a macOS `Button` keeps
        // AppKit's default push-button control height and centers its label within
        // it (even with `.fixedSize()`), rendering taller than the FilterChipMenu
        // chips. The remaining mismatch is that `Menu`'s `.borderlessButton` reports
        // its layout height *without* the label's 5pt vertical padding (it draws the
        // capsule overflowing that smaller box), so the menu chips measure ~10pt
        // shorter than this label's true padded height. Since FlowLayout top-aligns
        // each chip by its reported height, the taller Owner chip sat lower. The
        // `.padding(.vertical, -5)` cancels exactly that padding from measurement
        // while the capsule still draws, so this chip reports the same height as the
        // menu chips and lines up with them. We re-add button a11y semantics by hand.
        ChipLabel(
            title: title,
            icon: icon,
            text: chipText,
            fillColor: fillColor,
            strokeColor: strokeColor,
            labelColor: labelColor
        )
        .padding(.vertical, -5)
        .contentShape(Capsule())
        .onTapGesture { presented.toggle() }
        .disabled(options.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(title) filter")
        .accessibilityValue(selected.map(formatter) ?? "All")
        .accessibilityHint(accessibilityHint)
        .popover(isPresented: $presented, arrowEdge: .top) {
            SearchableFilterPopover(
                title: title,
                options: filtered,
                selected: $selected,
                presented: $presented,
                formatter: formatter,
                search: $search,
                meEmail: meEmail
            )
        }
    }
}

// Extracted so the label's styling chain type-checks independently of the
// chip's outer modifier/popover chain — keeps SearchableFilterChip.body fast
// to compile (was ~671ms as one expression).
private struct ChipLabel: View {
    let title: String
    let icon: String
    let text: String
    let fillColor: Color
    let strokeColor: Color
    let labelColor: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption)
            Text(text)
                .font(.callout).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(fillColor, in: Capsule())
        .foregroundStyle(labelColor)
        .overlay(Capsule().stroke(strokeColor, lineWidth: 0.5))
    }
}

// Extracted so its ScrollView/ForEach/ternary contents type-check independently
// of the chip's modifier chain, keeping each `body` fast to compile.
private struct SearchableFilterPopover: View {
    let title: String
    let options: [String]
    @Binding var selected: String?
    @Binding var presented: Bool
    let formatter: (String) -> String
    @Binding var search: String
    var meEmail: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search \(title.lowercased())", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let meEmail {
                        PopoverRow(
                            label: "Me",
                            subtitle: formatter(meEmail) == meEmail ? meEmail : formatter(meEmail),
                            isSelected: selected == meEmail
                        ) {
                            selected = meEmail
                            presented = false
                        }
                        Divider()
                    }
                    PopoverRow(label: "All", subtitle: nil, isSelected: selected == nil) {
                        selected = nil
                        presented = false
                    }
                    Divider()
                    ForEach(options, id: \.self) { option in
                        PopoverRow(
                            label: formatter(option),
                            subtitle: formatter(option) == option ? nil : option,
                            isSelected: option == selected
                        ) {
                            selected = option
                            presented = false
                        }
                    }
                    if options.isEmpty {
                        Text("No matches")
                            .font(.callout).foregroundStyle(.secondary)
                            .padding(10)
                    }
                }
            }
            .frame(width: 320, height: 320)
        }
    }
}

private struct PopoverRow: View {
    let label: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark" : "circle")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
                Text(label).lineLimit(1)
                Spacer(minLength: 4)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(hovered ? Color.accentColor.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Focused scene value for the selected pad

/// The pad selected in the active window's list, published via
/// `focusedSceneValue` so the Pad menu commands can act on it whenever the
/// window is frontmost — independent of which subview holds keyboard focus.
struct FocusedPadKey: FocusedValueKey {
    typealias Value = Pad
}

extension FocusedValues {
    var focusedPad: Pad? {
        get { self[FocusedPadKey.self] }
        set { self[FocusedPadKey.self] = newValue }
    }
}

/// Action published by whichever pane currently owns a search field, so the
/// global ⌘F command can focus it. Panes set this via `focusedSceneValue` while
/// visible; the command reads it both to perform the find and to know whether
/// Find applies in the current context (it's disabled when no pane provides one).
///
/// `Equatable` on a stable per-pane `id` is load-bearing: the wrapped closure
/// can't be compared, so without it every body pass re-publishes a "new" value
/// for the same scene key. Because `NavigationSplitView` re-evaluates its panes
/// several times per layout pass, SwiftUI flags those redundant writes as
/// "FocusedValue update tried to update multiple times per frame." Comparing by
/// `id` lets SwiftUI dedupe the identical re-assignments instead.
struct FindAction: Equatable {
    /// Identifies the owning pane (e.g. "pads"), so re-publishes from the same
    /// pane compare equal while a genuine pane switch compares unequal.
    let id: String
    let perform: () -> Void

    static func == (lhs: FindAction, rhs: FindAction) -> Bool {
        lhs.id == rhs.id
    }
}

struct FindActionKey: FocusedValueKey {
    typealias Value = FindAction
}

extension FocusedValues {
    var findAction: FindAction? {
        get { self[FindActionKey.self] }
        set { self[FindActionKey.self] = newValue }
    }
}

// MARK: - APIErrorView

struct APIErrorView: View {
    let error: Error
    var onRetry: (() -> Void)? = nil
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let api = error as? CoderPadError, api.isUnauthorized {
            ContentUnavailableView {
                Label("Key not authorized", systemImage: "lock.shield")
            } description: {
                Text("Your API key was rejected (HTTP 401/403). Open Settings to switch accounts or paste a new key.")
            } actions: {
                VStack(spacing: 8) {
                    Button("Open Settings") { openSettings() }
                        .buttonStyle(.borderedProminent)
                    GetAPIKeyLink()
                    if let onRetry {
                        Button("Retry", action: onRetry)
                    }
                }
            }
        } else if let api = error as? CoderPadError, case .missingAPIKey = api {
            ContentUnavailableView {
                Label("No API key", systemImage: "key")
            } description: {
                Text("Add an account in Settings to start using the app.")
            } actions: {
                VStack(spacing: 8) {
                    Button("Open Settings") { openSettings() }
                        .buttonStyle(.borderedProminent)
                    GetAPIKeyLink()
                }
            }
        } else {
            ContentUnavailableView {
                Label("Something went wrong", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                if let onRetry {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
