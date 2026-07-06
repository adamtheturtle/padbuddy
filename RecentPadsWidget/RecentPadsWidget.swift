//
//  RecentPadsWidget.swift
//  RecentPadsWidget
//
//  A widget listing the most recently updated pads for the app's current account.
//  Tapping a pad opens it in the app via the `coderpad://pad/<id>` URL scheme.
//

import AppIntents
#if os(macOS)
import AppKit
#endif
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct RecentPadsEntry: TimelineEntry {
    let date: Date
    let pads: [WidgetPadSnapshot]
    /// How many rows the user chose to show. Defaults to automatic for the
    /// placeholder/preview, matching the prior behavior.
    var rowCount: WidgetRowCount = .automatic
    /// The favourite question the New Pad button is configured to seed from, and the
    /// account that owns it (question ids are only unique within an org). Both nil
    /// when the button should just create a blank pad.
    var newPadAccountID: String?
    var newPadQuestionID: Int?
}

/// Feeds the widget from the shared App Group snapshots the app maintains, scoped to
/// the account the user pinned in the widget's configuration (or the current account
/// when none is pinned). There is no network here — the app owns refreshing the
/// snapshots and nudging WidgetKit.
struct RecentPadsProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> RecentPadsEntry {
        RecentPadsEntry(date: Date(), pads: RecentPadsProvider.sample)
    }

    func snapshot(for configuration: RecentPadsConfigurationIntent, in context: Context) async -> RecentPadsEntry {
        let pads = context.isPreview ? RecentPadsProvider.sample : load(for: configuration)
        return entry(pads: pads, configuration: configuration)
    }

    func timeline(for configuration: RecentPadsConfigurationIntent,
                  in _: Context) async -> Timeline<RecentPadsEntry> {
        // The app reloads timelines whenever a snapshot changes. We still ask WidgetKit
        // to refresh about hourly so the relative "updated" labels don't go stale between
        // app runs; the data itself only changes when the app rewrites the snapshot.
        let entry = entry(pads: load(for: configuration), configuration: configuration)
        let nextRefresh = Date().addingTimeInterval(60 * 60)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    /// Builds an entry from the loaded pads and the user's configuration, carrying the
    /// row count and the New Pad button's seeded question (if any).
    private func entry(pads: [WidgetPadSnapshot],
                       configuration: RecentPadsConfigurationIntent) -> RecentPadsEntry {
        RecentPadsEntry(date: Date(), pads: pads, rowCount: configuration.rowCount,
                        newPadAccountID: configuration.newPadQuestion?.accountID,
                        newPadQuestionID: configuration.newPadQuestion?.questionID)
    }

    /// Loads the snapshot for the configured account, or the default (current-account)
    /// snapshot when none is pinned.
    private func load(for configuration: RecentPadsConfigurationIntent) -> [WidgetPadSnapshot] {
        WidgetSharedStore.load(account: configuration.account?.id)
    }

    /// Gallery/preview placeholder data. Kept free of dashes per the app's copy style.
    static let sample: [WidgetPadSnapshot] = [
        WidgetPadSnapshot(id: "ab12cd34", title: "Backend Phone Screen",
                          subtitle: "you@example.com", language: "python", updatedAt: Date()),
        WidgetPadSnapshot(id: "ef56gh78", title: "Systems Design Round",
                          subtitle: "you@example.com", language: "go", updatedAt: Date()),
        WidgetPadSnapshot(id: "ij90kl12", title: "Frontend Pairing",
                          subtitle: "you@example.com", language: "javascript", updatedAt: Date())
    ]
}

// MARK: - Widget

struct RecentPadsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetSharedStore.widgetKind,
                               intent: RecentPadsConfigurationIntent.self,
                               provider: RecentPadsProvider()) { entry in
            RecentPadsWidgetEntryView(entry: entry)
                // An explicit opaque grey, NOT `.background`/`.fill.tertiary`: the
                // semantic `BackgroundStyle` (`.background`) resolved to opaque black on
                // the systemSmall/systemLarge tiles (medium rendered fine with identical
                // code), and the translucent `.fill.tertiary` read as near-black over the
                // tile's black base. `windowBackgroundColor` is a solid, scheme-adaptive
                // grey (dark-grey in dark mode, light-grey in light) that fills every
                // family consistently (#456).
                .containerBackground(for: .widget) {
                    widgetContainerBackground
                }
        }
        .configurationDisplayName("Recent Pads")
        .description("Your most recently updated CoderPad pads.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// A solid, scheme-adaptive grey that fills every widget family consistently.
/// See the `.containerBackground` note above for why this is an explicit opaque
/// color rather than a semantic `BackgroundStyle` (#456). On macOS this is
/// `windowBackgroundColor`; iOS uses the matching grouped-background system grey.
private var widgetContainerBackground: Color {
    #if os(macOS)
    Color(nsColor: .windowBackgroundColor)
    #else
    Color(uiColor: .systemGroupedBackground)
    #endif
}

// MARK: - Configuration

/// The widget's user configuration: which account's pads to show and how many rows.
struct RecentPadsConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource {
        "Recent Pads"
    }

    // Read by the AppIntents framework (Shortcuts metadata), not Swift.
    // periphery:ignore
    static var description: IntentDescription {
        IntentDescription("Choose which account's pads to show, and how many.")
    }

    /// The account to pin. Optional — when unset the widget follows the account
    /// currently selected in the app (the prior behavior).
    @Parameter(title: "Account")
    var account: WidgetAccountEntity?

    @Parameter(title: "Rows", default: .automatic)
    var rowCount: WidgetRowCount

    /// Seeds the widget's New Pad button with a favourite question. Optional — when
    /// unset the button creates a blank pad in the current account.
    @Parameter(title: "New Pad question")
    var newPadQuestion: WidgetQuestionEntity?

    /// Hides the "Rows" control on families where it does nothing (#410). Small shows a
    /// single pad and ignores the count entirely; medium clamps every choice to three,
    /// so the picker is meaningless there too. Only the large family can vary between
    /// three, five, and seven rows, so it's the only one that surfaces "Rows". Omitting
    /// a parameter from a family's `Summary` removes it from that family's config editor.
    static var parameterSummary: some ParameterSummary {
        Switch(.widgetFamily) {
            Case(.systemLarge) {
                Summary {
                    \.$account
                    \.$rowCount
                    \.$newPadQuestion
                }
            }
            DefaultCase {
                Summary {
                    \.$account
                    \.$newPadQuestion
                }
            }
        }
    }
}

/// A pinnable account, sourced from the account index the app mirrors into the App
/// Group so the picker can list accounts from inside the widget process.
struct WidgetAccountEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Account"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let defaultQuery = WidgetAccountQuery()
}

struct WidgetAccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetAccountEntity] {
        WidgetSharedStore.loadAccounts()
            .filter { identifiers.contains($0.id) }
            .map { WidgetAccountEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [WidgetAccountEntity] {
        WidgetSharedStore.loadAccounts().map { WidgetAccountEntity(id: $0.id, name: $0.name) }
    }
}

/// A favourite question the New Pad button can be seeded from, sourced from the
/// per-account favourites the app mirrors into the App Group. Its id is a composite
/// `accountUUID:questionID` so the new-pad deep link carries both — question ids are
/// only unique within their owning org.
struct WidgetQuestionEntity: AppEntity {
    let id: String
    let accountID: String
    let questionID: Int
    let title: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Question"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    static let defaultQuery = WidgetQuestionQuery()
}

struct WidgetQuestionQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetQuestionEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetQuestionEntity] {
        all()
    }

    /// Every account's favourite questions, flattened. When more than one account has
    /// favourites the account name is appended so otherwise-identical titles stay
    /// distinguishable in the picker.
    private func all() -> [WidgetQuestionEntity] {
        let accounts = WidgetSharedStore.loadAccounts()
        let qualify = accounts.count > 1
        return accounts.flatMap { account in
            WidgetSharedStore.loadFavorites(account: account.id).map { question in
                let label = qualify ? "\(question.title) · \(account.name)" : question.title
                return WidgetQuestionEntity(id: "\(account.id):\(question.id)",
                                            accountID: account.id, questionID: question.id, title: label)
            }
        }
    }
}

/// How many pad rows to show. `automatic` keeps the size-driven default (three on
/// medium, seven on large beneath the New Pad header); explicit counts are clamped
/// to what each family can fit.
enum WidgetRowCount: String, AppEnum {
    case automatic
    case three
    case five
    case seven

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Rows"
    }

    static var caseDisplayRepresentations: [WidgetRowCount: DisplayRepresentation] {
        [.automatic: "Automatic", .three: "3", .five: "5", .seven: "7"]
    }

    /// Resolved maximum rows for `family`, clamped to the family's ceiling so an
    /// over-large choice never overflows the widget.
    func maxRows(for family: WidgetFamily) -> Int {
        let ceiling = family == .systemLarge ? 7 : 3
        switch self {
        case .automatic: return ceiling
        case .three: return min(3, ceiling)
        case .five: return min(5, ceiling)
        case .seven: return min(7, ceiling)
        }
    }
}

// MARK: - Views

struct RecentPadsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecentPadsEntry

    var body: some View {
        if entry.pads.isEmpty {
            emptyState
        } else if family == .systemSmall {
            smallView
        } else {
            listView
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No recent pads")
                .font(.headline)
            Text("Create one to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            // With no pads to open, creating one is the most useful action, so surface
            // the New Pad button on every family — the interactive intent button works
            // even on small, where the compact icon-only pill fits (#456).
            NewPadButton(accountID: entry.newPadAccountID, questionID: entry.newPadQuestionID,
                         compact: family == .systemSmall)
                .padding(.top, 2)
        }
        .padding()
        .widgetURL(URL(string: "coderpad://pads"))
    }

    /// A compact header above the pad list carrying the New Pad action, so a pad
    /// can be created straight from the widget without opening the app first.
    private var listHeader: some View {
        HStack(spacing: 4) {
            Text("Recent Pads")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            NewPadButton(accountID: entry.newPadAccountID, questionID: entry.newPadQuestionID)
        }
    }

    /// Small family: the most recent pad fills the widget, the whole tile opens it
    /// (`widgetURL`), and a compact New Pad button is pinned top-right as its own tap
    /// target. The button is an interactive `Button(intent:)`, which (unlike `Link`)
    /// works on systemSmall and coexists with `widgetURL` — taps on the button create a
    /// pad, taps elsewhere open the pad (#456).
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let first = entry.pads.first {
                HStack(alignment: .top, spacing: 6) {
                    Text(first.title)
                        .font(.headline)
                        .lineLimit(3)
                    Spacer(minLength: 4)
                    NewPadButton(accountID: entry.newPadAccountID,
                                 questionID: entry.newPadQuestionID, compact: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if let language = first.languageLabel {
                        LanguageBadge(text: language, tint: languageTint(for: first.language))
                    }
                    Spacer(minLength: 0)
                    if let updated = first.relativeUpdated {
                        Text(updated)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(entry.pads.first.flatMap { URL(string: "coderpad://pad/\($0.id)") })
    }

    /// Medium/large families: a New Pad header plus a tappable list, one deep link
    /// per row.
    private var listView: some View {
        VStack(alignment: .leading, spacing: 8) {
            listHeader
            ForEach(visiblePads) { pad in
                Link(destination: URL(string: "coderpad://pad/\(pad.id)") ?? fallbackURL) {
                    RecentPadRow(pad: pad)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var fallbackURL: URL {
        URL(string: "coderpad://pads") ?? URL(filePath: "/")
    }

    private var visiblePads: [WidgetPadSnapshot] {
        // The chosen row count, clamped to what the family can show beneath the
        // New Pad header (seven on large, three on medium).
        Array(entry.pads.prefix(entry.rowCount.maxRows(for: family)))
    }
}

/// Creates a new pad straight from the widget. An interactive `Button` backed by
/// `CreatePadIntent`, NOT a `Link` or `Button(intent: OpenURLIntent(...))`: `Link` is
/// ignored on the small widget family and `OpenURLIntent` can't open the app's custom
/// URL scheme, so neither put a working New Pad button on every family. The intent
/// records the request in the App Group and the app performs it on activation (#456,
/// #485). When a favourite question is configured, the intent carries its account and
/// id so the app switches to that account and pre-seeds the create sheet.
private struct NewPadButton: View {
    var accountID: String?
    var questionID: Int?
    /// Icon-only circular pill for the small family, where there's no room for the
    /// "New Pad" label; the larger families show the full pill.
    var compact = false

    var body: some View {
        // `.buttonStyle(.plain)` so the hand-built accent pill shows rather than the
        // default bordered chrome (#426).
        Button(intent: CreatePadIntent(account: accountID, question: questionID)) {
            if compact {
                Image(systemName: "plus")
                    .font(.caption2.weight(.bold))
                    .padding(5)
                    .background(Color.accentColor, in: Circle())
                    .foregroundStyle(.white)
                    .accessibilityLabel("New Pad")
            } else {
                Label("New Pad", systemImage: "plus")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct RecentPadRow: View {
    let pad: WidgetPadSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(pad.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if !pad.subtitle.isEmpty {
                    Text(pad.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                if let language = pad.languageLabel {
                    LanguageBadge(text: language, tint: languageTint(for: pad.language))
                }
                if let updated = pad.relativeUpdated {
                    Text(updated)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pad.accessibilityDescription)
    }
}

/// A compact language pill, mirroring the app's `Chip`. The tint is chosen per
/// language so the user can tell a Python pad from a Go one at a glance.
private struct LanguageBadge: View {
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
            .overlay(Capsule().stroke(tint.opacity(0.25), lineWidth: 0.5))
    }
}

/// A minimal language→color map, duplicated locally so the widget target stays
/// dependency-free (it can't import the app's `SyntaxHighlighting`). Colors are
/// chosen to stay legible as both the capsule tint and its text; an unknown
/// language falls back to the accent color, preserving the prior look. Grouped
/// aliases share a hue so, e.g., every Python variant reads the same.
private func languageTint(for language: String?) -> Color {
    switch language?.lowercased() {
    case "python", "python2", "python3": .blue
    case "javascript", "node", "node.js", "nodejs": .orange
    case "typescript": .blue
    case "swift": .orange
    case "go", "golang": .teal
    case "rust": .red
    case "java": .red
    case "kotlin": .purple
    case "ruby": .pink
    case "c", "cpp", "c++": .indigo
    case "csharp", "c#": .green
    case "php": .indigo
    case "html", "css": .pink
    case "sql", "mysql", "postgresql", "postgres": .teal
    default: .accentColor
    }
}

#Preview(as: .systemMedium) {
    RecentPadsWidget()
} timeline: {
    RecentPadsEntry(date: Date(), pads: RecentPadsProvider.sample)
    RecentPadsEntry(date: Date(), pads: [])
}

#Preview(as: .systemSmall) {
    RecentPadsWidget()
} timeline: {
    RecentPadsEntry(date: Date(), pads: RecentPadsProvider.sample)
    RecentPadsEntry(date: Date(), pads: [])
}
