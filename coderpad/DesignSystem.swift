//
//  DesignSystem.swift
//  coderpad
//

import SwiftUI

extension Color {
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let subtleStroke = Color.primary.opacity(0.08)
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
        case "draft": return .orange
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
            .padding(16)
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
            return "chevron.left.slash.chevron.right"
        }
    }
}

// MARK: - GetAPIKeyLink

enum CoderPadLinks {
    static let apiSettings = URL(string: "https://app.coderpad.io/dashboard/settings")!
    static let apiDocs = URL(string: "https://coderpad.io/resources/docs/coderpad-interview/api/")!
    static let sourceRepo = URL(string: "https://github.com/adamtheturtle/coderpad-macos")!
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
    await work()
    while !Task.isCancelled {
        do {
            try await Task.sleep(for: interval)
        } catch {
            break
        }
        await work()
    }
}

struct PaneTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.largeTitle.bold())
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 10)
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

struct MarkdownText: View {
    let raw: String

    init(_ raw: String) {
        self.raw = raw
    }

    var body: some View {
        if raw.isEmpty {
            Text("(empty)").foregroundStyle(.secondary)
        } else if let attributed = try? AttributedString(
            markdown: raw,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
        } else {
            Text(raw)
        }
    }
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
        let client = account.isMock ? CoderPadClient.mock() : CoderPadClient.live(apiKey: account.apiKey)
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

// MARK: - Searchable filter chip

struct SearchableFilterChip: View {
    let title: String
    let icon: String
    @Binding var selected: String?
    let options: [String]
    let formatter: (String) -> String

    @State private var presented = false
    @State private var search = ""

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

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption)
                Text(selected.map(formatter) ?? title)
                    .font(.callout).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                (selected == nil ? Color.subtleStroke : Color.accentColor.opacity(0.18)),
                in: Capsule()
            )
            .foregroundStyle(selected == nil ? Color.primary : Color.accentColor)
            .overlay(Capsule().stroke(selected == nil ? Color.subtleStroke : Color.accentColor.opacity(0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(options.isEmpty)
        .accessibilityLabel("\(title) filter")
        .accessibilityValue(selected.map(formatter) ?? "All")
        .accessibilityHint(accessibilityHint)
        .popover(isPresented: $presented, arrowEdge: .top) {
            VStack(spacing: 0) {
                TextField("Search \(title.lowercased())", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(10)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        PopoverRow(label: "All", subtitle: nil, isSelected: selected == nil) {
                            selected = nil
                            presented = false
                        }
                        Divider()
                        ForEach(filtered, id: \.self) { option in
                            PopoverRow(
                                label: formatter(option),
                                subtitle: formatter(option) == option ? nil : option,
                                isSelected: option == selected
                            ) {
                                selected = option
                                presented = false
                            }
                        }
                        if filtered.isEmpty {
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

// MARK: - FocusedValue for the selected pad

struct FocusedPadKey: FocusedValueKey {
    typealias Value = Pad
}

extension FocusedValues {
    var focusedPad: Pad? {
        get { self[FocusedPadKey.self] }
        set { self[FocusedPadKey.self] = newValue }
    }
}

// MARK: - LastFetchedLabel

struct LastFetchedLabel: View {
    let date: Date?
    var body: some View {
        if let date {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text("Updated \(date.formatted(.relative(presentation: .named)))")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .help("Last refreshed at \(date.formatted(date: .omitted, time: .standard))")
        }
    }
}

// MARK: - Environment: openSettings

private struct OpenSettingsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openSettings: () -> Void {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
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
                Button("Open Settings") { openSettings() }
                    .buttonStyle(.borderedProminent)
                GetAPIKeyLink()
                if let onRetry {
                    Button("Retry", action: onRetry)
                }
            }
        } else if let api = error as? CoderPadError, case .missingAPIKey = api {
            ContentUnavailableView {
                Label("No API key", systemImage: "key")
            } description: {
                Text("Add an account in Settings to start using the app.")
            } actions: {
                Button("Open Settings") { openSettings() }
                    .buttonStyle(.borderedProminent)
                GetAPIKeyLink()
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
