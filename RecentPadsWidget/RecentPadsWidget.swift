//
//  RecentPadsWidget.swift
//  RecentPadsWidget
//
//  A widget listing the most recently updated pads for the app's current account.
//  Tapping a pad opens it in the app via the `coderpad://pad/<id>` URL scheme.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct RecentPadsEntry: TimelineEntry {
    let date: Date
    let pads: [WidgetPadSnapshot]
    /// How many rows the user chose to show. Defaults to automatic for the
    /// placeholder/preview, matching the prior behavior.
    var rowCount: WidgetRowCount = .automatic
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
        return RecentPadsEntry(date: Date(), pads: pads, rowCount: configuration.rowCount)
    }

    func timeline(for configuration: RecentPadsConfigurationIntent,
                  in _: Context) async -> Timeline<RecentPadsEntry> {
        // The app reloads timelines whenever a snapshot changes. We still ask WidgetKit
        // to refresh about hourly so the relative "updated" labels don't go stale between
        // app runs; the data itself only changes when the app rewrites the snapshot.
        let entry = RecentPadsEntry(date: Date(), pads: load(for: configuration), rowCount: configuration.rowCount)
        let nextRefresh = Date().addingTimeInterval(60 * 60)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
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
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recent Pads")
        .description("Your most recently updated CoderPad pads.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Configuration

/// The widget's user configuration: which account's pads to show and how many rows.
struct RecentPadsConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Recent Pads" }
    static var description: IntentDescription {
        IntentDescription("Choose which account's pads to show, and how many.")
    }

    /// The account to pin. Optional — when unset the widget follows the account
    /// currently selected in the app (the prior behavior).
    @Parameter(title: "Account")
    var account: WidgetAccountEntity?

    @Parameter(title: "Rows", default: .automatic)
    var rowCount: WidgetRowCount
}

/// A pinnable account, sourced from the account index the app mirrors into the App
/// Group so the picker can list accounts from inside the widget process.
struct WidgetAccountEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Account" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
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

/// How many pad rows to show. `automatic` keeps the size-driven default (three on
/// medium, seven on large beneath the New Pad header); explicit counts are clamped
/// to what each family can fit.
enum WidgetRowCount: String, AppEnum {
    case automatic
    case three
    case five
    case seven

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Rows" }
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
            // With no pads to open, the most useful action is creating one, so
            // surface the New Pad button here too. The small family allows only a
            // single tap target, so it keeps its whole-widget link instead.
            if family != .systemSmall {
                NewPadButton()
                    .padding(.top, 2)
            }
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
            NewPadButton()
                .font(.caption2)
        }
    }

    /// Small family: a single tap target summarizing the most recent pad.
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let first = entry.pads.first {
                Text(first.title)
                    .font(.headline)
                    .lineLimit(3)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.pads.first.map { "Recent pad, \($0.accessibilityDescription)" } ?? "")
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

/// Creates a new pad straight from the widget. It opens the app via the
/// `coderpad://new-pad` deep link the app already routes (the same one the
/// Control Center `NewPadControl` uses), so the widget extension stays
/// dependency-free and never has to compile the app-only `NewPadIntent`.
private struct NewPadButton: View {
    private static let newPadURL = URL(string: "coderpad://new-pad")!

    var body: some View {
        Button(intent: OpenURLIntent(Self.newPadURL)) {
            Label("New Pad", systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .tint(.accentColor)
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
    case "python", "python2", "python3": return .blue
    case "javascript", "node", "node.js", "nodejs": return .orange
    case "typescript": return .blue
    case "swift": return .orange
    case "go", "golang": return .teal
    case "rust": return .red
    case "java": return .red
    case "kotlin": return .purple
    case "ruby": return .pink
    case "c", "cpp", "c++": return .indigo
    case "csharp", "c#": return .green
    case "php": return .indigo
    case "html", "css": return .pink
    case "sql", "mysql", "postgresql", "postgres": return .teal
    default: return .accentColor
    }
}

#Preview(as: .systemMedium) {
    RecentPadsWidget()
} timeline: {
    RecentPadsEntry(date: Date(), pads: RecentPadsProvider.sample)
    RecentPadsEntry(date: Date(), pads: [])
}
