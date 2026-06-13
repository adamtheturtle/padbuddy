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
        // The app reloads timelines whenever the snapshot changes, so a single entry
        // with `.never` is enough; no need to schedule speculative refreshes.
        let entry = RecentPadsEntry(date: Date(), pads: WidgetSharedStore.load())
        completion(Timeline(entries: [entry], policy: .never))
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
            Label("Recent Pads", systemImage: "doc.text")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let first = entry.pads.first {
                Text(first.title)
                    .font(.headline)
                    .lineLimit(3)
                if let language = first.language, !language.isEmpty {
                    Text(language.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(entry.pads.first.flatMap { URL(string: "coderpad://pad/\($0.id)") })
    }

    /// Medium/large families: a tappable list, one deep link per row.
    private var listView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Pads")
                .font(.headline)
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
        let limit = family == .systemLarge ? 7 : 3
        return Array(entry.pads.prefix(limit))
    }
}

private struct RecentPadRow: View {
    let pad: WidgetPadSnapshot

    var body: some View {
        HStack(spacing: 8) {
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
            if let language = pad.language, !language.isEmpty {
                Text(language.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview(as: .systemMedium) {
    RecentPadsWidget()
} timeline: {
    RecentPadsEntry(date: Date(), pads: RecentPadsProvider.sample)
    RecentPadsEntry(date: Date(), pads: [])
}
