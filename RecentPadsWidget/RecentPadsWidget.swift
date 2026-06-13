//
//  RecentPadsWidget.swift
//  RecentPadsWidget
//
//  A widget listing the most recently updated pads for the app's current account.
//  Tapping a pad opens it in the app via the `coderpad://pad/<id>` URL scheme.
//

import SwiftUI
import WidgetKit

// MARK: - Timeline

struct RecentPadsEntry: TimelineEntry {
    let date: Date
    let pads: [WidgetPadSnapshot]
}

/// Feeds the widget from the shared App Group snapshot the app maintains. There is
/// no network here — the app owns refreshing the snapshot and nudging WidgetKit.
struct RecentPadsProvider: TimelineProvider {
    func placeholder(in _: Context) -> RecentPadsEntry {
        RecentPadsEntry(date: Date(), pads: RecentPadsProvider.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentPadsEntry) -> Void) {
        let pads = context.isPreview ? RecentPadsProvider.sample : WidgetSharedStore.load()
        completion(RecentPadsEntry(date: Date(), pads: pads))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<RecentPadsEntry>) -> Void) {
        // The app reloads timelines whenever the snapshot changes. We still ask WidgetKit
        // to refresh about hourly so the relative "updated" labels don't go stale between
        // app runs; the data itself only changes when the app rewrites the snapshot.
        let entry = RecentPadsEntry(date: Date(), pads: WidgetSharedStore.load())
        let nextRefresh = Date().addingTimeInterval(60 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
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
        StaticConfiguration(kind: WidgetSharedStore.widgetKind, provider: RecentPadsProvider()) { entry in
            RecentPadsWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recent Pads")
        .description("Your most recently updated CoderPad pads.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
            Text("Open CoderPad to see recent pads.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .widgetURL(URL(string: "coderpad://pads"))
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
                        LanguageBadge(text: language)
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

    /// Medium/large families: a tappable list, one deep link per row.
    private var listView: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        // Dropping the redundant header frees a row, so large shows the full snapshot.
        let limit = family == .systemLarge ? 8 : 3
        return Array(entry.pads.prefix(limit))
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
                    LanguageBadge(text: language)
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

/// A compact language pill, mirroring the app's accent-tinted `Chip`.
private struct LanguageBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.16), in: Capsule())
            .foregroundStyle(Color.accentColor)
            .overlay(Capsule().stroke(Color.accentColor.opacity(0.25), lineWidth: 0.5))
    }
}

#Preview(as: .systemMedium) {
    RecentPadsWidget()
} timeline: {
    RecentPadsEntry(date: Date(), pads: RecentPadsProvider.sample)
    RecentPadsEntry(date: Date(), pads: [])
}
