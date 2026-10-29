//
//  RecentPadsWidget.swift
//  RecentPadsWidget
//
//  A widget listing the most recently updated pads for the app's current account.
//  Tapping a pad opens it in the app via the `com.adamdangoor.padbuddy://pad/<id>` URL scheme.
//

import AppIntents
#if os(macOS)
    import AppKit
#endif
import SwiftUI
import WidgetKit

// MARK: - Timeline

@available(visionOS 26.0, *)
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
    var openPadAccountID: String?
    var snapshotUpdatedAt: Date?
    var accessUnavailable = false
}

/// Feeds the widget from the shared App Group snapshots the app maintains, scoped to
/// the account the user pinned in the widget's configuration (or the current account
/// when none is pinned). There is no network here — the app owns refreshing the
/// snapshots and nudging WidgetKit.
@available(visionOS 26.0, *)
struct RecentPadsProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> RecentPadsEntry {
        RecentPadsEntry(date: Date(), pads: RecentPadsProvider.sample)
    }

    func snapshot(for configuration: RecentPadsConfigurationIntent, in context: Context) async -> RecentPadsEntry {
        if context.isPreview {
            return entry(loaded: WidgetPadSnapshotLoad(pads: Self.sample, lastUpdated: Date()),
                         configuration: configuration, account: nil)
        }
        let loaded = load(for: configuration)
        return entry(loaded: loaded.snapshot, configuration: configuration, account: loaded.account)
    }

    func timeline(for configuration: RecentPadsConfigurationIntent,
                  in _: Context) async -> Timeline<RecentPadsEntry> {
        // The app reloads timelines whenever a snapshot changes. We still ask WidgetKit
        // to refresh about hourly so each pad row's relative date stays roughly current
        // between app runs; the data itself only changes when the app rewrites the snapshot.
        let loaded = load(for: configuration)
        let entry = entry(loaded: loaded.snapshot, configuration: configuration, account: loaded.account)
        let nextRefresh = Date().addingTimeInterval(60 * 60)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    /// Builds an entry from the loaded pads and the user's configuration, carrying the
    /// row count and the New Pad button's seeded question (if any).
    private func entry(loaded: WidgetPadSnapshotLoad,
                       configuration: RecentPadsConfigurationIntent, account: String?) -> RecentPadsEntry {
        RecentPadsEntry(date: Date(), pads: loaded.pads,
                        rowCount: configuration.rowCount,
                        newPadAccountID: configuration.newPadQuestion?.accountID,
                        newPadQuestionID: configuration.newPadQuestion?.questionID,
                        openPadAccountID: account,
                        snapshotUpdatedAt: loaded.lastUpdated,
                        accessUnavailable: loaded.accessUnavailable)
    }

    /// Loads the snapshot for the configured account, or the default (current-account)
    /// snapshot when none is pinned.
    ///
    /// A pinned account whose snapshot has gone falls back to the default rather than
    /// rendering an empty widget. Account ids are per-install, so a restore to a new
    /// Mac or a reinstall leaves the configuration pointing at a file that will never
    /// exist again (#2582); showing the current account's recent pads is far more
    /// useful than "No pads", and the account picker still offers the live accounts
    /// so the pin can be re-made.
    private func load(for configuration: RecentPadsConfigurationIntent)
        -> (snapshot: WidgetPadSnapshotLoad, account: String?) {
        guard let account = configuration.account?.id else {
            return (accessAware(WidgetSharedStore.loadSnapshot()), nil)
        }

        let storedAccount = WidgetSharedStore.loadAccounts().first {
            $0.id == account || $0.legacyID == account
        }
        let resolvedID = storedAccount?.id ?? account
        let pinned = WidgetSharedStore.loadSnapshot(account: resolvedID)
        // Through `accessAware` like the fallback paths: a pinned account that resolves in
        // the index but whose snapshot cannot be read used to return an empty load with
        // `accessUnavailable` still false, so the widget said "No recent pads · Create one
        // to get started" where the unpinned path would have offered the "Open PadBuddy"
        // guidance for the identical condition (#4770).
        guard pinned.pads.isEmpty, storedAccount == nil else { return (accessAware(pinned), resolvedID) }

        return (accessAware(WidgetSharedStore.loadSnapshot()), nil)
    }

    /// `loadSnapshot` reports unreadable access directly now, so this only passes it
    /// through. It used to infer it from an empty account index, which was wrong in both
    /// directions: a user with genuinely no accounts was told access was unavailable, and
    /// a truly unreadable container went unnoticed whenever the index still decoded
    /// (#4771).
    private func accessAware(_ loaded: WidgetPadSnapshotLoad) -> WidgetPadSnapshotLoad {
        loaded
    }

    /// Gallery/preview placeholder data. Kept free of dashes per the app's copy style.
    static let sample: [WidgetPadSnapshot] = [
        WidgetPadSnapshot(id: "ab12cd34", title: "Backend Phone Screen",
                          subtitle: "", language: "python", updatedAt: Date()),
        WidgetPadSnapshot(id: "ef56gh78", title: "Systems Design Round",
                          subtitle: "", language: "go", updatedAt: Date()),
        WidgetPadSnapshot(id: "ij90kl12", title: "Frontend Pairing",
                          subtitle: "", language: "javascript", updatedAt: Date())
    ]
}

// MARK: - Widget

@available(visionOS 26.0, *)
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
@available(visionOS 26.0, *)
private var widgetContainerBackground: Color {
    #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
    #else
        Color(uiColor: .systemGroupedBackground)
    #endif
}

// MARK: - Configuration

/// The widget's user configuration: which account's pads to show and how many rows.
@available(visionOS 26.0, *)
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
        let accounts = try WidgetSharedStore.loadAccountsForConfiguration()
        return identifiers.compactMap { identifier in
            accounts.first { $0.id == identifier || $0.legacyID == identifier }
                .map { WidgetAccountEntity(id: $0.id, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [WidgetAccountEntity] {
        try WidgetSharedStore.loadAccountsForConfiguration().map { WidgetAccountEntity(id: $0.id, name: $0.name) }
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
        try all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetQuestionEntity] {
        try all()
    }

    /// Every account's favourite questions, flattened. When more than one account has
    /// favourites the account name is appended so otherwise-identical titles stay
    /// distinguishable in the picker.
    private func all() throws -> [WidgetQuestionEntity] {
        let accounts = try WidgetSharedStore.loadAccountsForConfiguration()
        guard !accounts.isEmpty else { return [] }

        if accounts.count == 1, let account = accounts.first {
            return try WidgetSharedStore.loadFavoritesForConfiguration(account: account.id).map { question in
                WidgetQuestionEntity(id: "\(account.id):\(question.id)",
                                     accountID: account.id, questionID: question.id, title: question.title)
            }
        }

        let favorites = try WidgetSharedStore.loadFavoritesForConfiguration(accounts: accounts.map(\.id))
        return accounts.flatMap { account in
            (favorites[account.id] ?? []).map { question in
                let label = "\(question.title) · \(account.name)"
                return WidgetQuestionEntity(id: "\(account.id):\(question.id)",
                                            accountID: account.id, questionID: question.id, title: label)
            }
        }
    }
}

/// How many pad rows to show. `automatic` keeps the size-driven default (three on
/// medium, seven on large beneath the New Pad header); explicit counts are clamped
/// to what each family can fit.
@available(visionOS 26.0, *)
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

@available(visionOS 26.0, *)
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
        VStack(spacing: family == .systemSmall ? 5 : 6) {
            Image(systemName: "doc.text")
                .font(family == .systemSmall ? .title3 : .title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(family == .systemSmall ? String(localized: "No pads") : String(localized: "No recent pads"))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(emptyStateGuidance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(family == .systemSmall ? 1 : 2)
                .minimumScaleFactor(0.85)
            snapshotTimestamp
            // With no pads to open, creating one is the most useful action, so surface
            // the New Pad button on every family — the interactive intent button works
            // even on small, where the compact icon-only pill fits (#456).
            NewPadButton(accountID: entry.newPadAccountID, questionID: entry.newPadQuestionID,
                         compact: family == .systemSmall)
                .padding(.top, 2)
        }
        .padding(family == .systemSmall ? 10 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(widgetPadsURL(account: entry.openPadAccountID))
    }

    private var emptyStateGuidance: String {
        if entry.accessUnavailable {
            return family == .systemSmall
                ? String(localized: "Open PadBuddy.")
                : String(localized: "Open PadBuddy to add or select an account.")
        }
        return family == .systemSmall
            ? String(localized: "Create one.")
            : String(localized: "Create one to get started.")
    }

    /// A compact header above the pad list carrying the New Pad action, so a pad
    /// can be created straight from the widget without opening the app first.
    private var listHeader: some View {
        HStack(spacing: 4) {
            Text("Recent Pads")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            snapshotTimestamp
            NewPadButton(accountID: entry.newPadAccountID, questionID: entry.newPadQuestionID)
        }
    }

    @ViewBuilder
    private var snapshotTimestamp: some View {
        if let updated = entry.snapshotUpdatedAt {
            Text(updated, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    "Updated \(updated.formatted(date: .abbreviated, time: .shortened))"
                )
        }
    }

    /// Small family: the most recent pad fills the widget and a compact New Pad button
    /// is pinned top-right as its own tap target. iPadOS uses an interactive intent for
    /// the pad tap too, because custom-scheme widget links can show the right affordance
    /// without delivering the URL to the app (#660). macOS keeps the existing `widgetURL`
    /// path, which works there and preserves the whole-tile link behavior.
    @ViewBuilder
    private var smallView: some View {
        if let first = entry.pads.first {
            smallPadView(first)
        }
    }

    @ViewBuilder
    private func smallPadView(_ pad: WidgetPadSnapshot) -> some View {
        #if os(iOS)
            ZStack(alignment: .topTrailing) {
                Button(intent: OpenPadIntent(id: pad.id, account: entry.openPadAccountID)) {
                    smallPadContent(pad)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(openPadAccessibilityLabel(pad))
                .accessibilityHint("Opens this pad in PadBuddy.")

                NewPadButton(accountID: entry.newPadAccountID,
                             questionID: entry.newPadQuestionID, compact: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #else
            smallPadContent(pad, showsNewPadButton: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .widgetURL(widgetPadURL(id: pad.id, account: entry.openPadAccountID))
        #endif
    }

    private func smallPadContent(_ pad: WidgetPadSnapshot,
                                 showsNewPadButton: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Text(pad.title)
                    .font(.headline)
                    .lineLimit(3)
                Spacer(minLength: 4)
                if showsNewPadButton {
                    NewPadButton(accountID: entry.newPadAccountID,
                                 questionID: entry.newPadQuestionID, compact: true)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let language = pad.languageLabel {
                    LanguageBadge(text: language, tint: languageTint(for: pad.language))
                }
                Spacer(minLength: 0)
                if let updated = pad.relativeUpdated {
                    Text(updated)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Medium/large families: a New Pad header plus a tappable list, one deep link
    /// per row.
    ///
    /// The row count adapts to the widget's actual height via `ViewThatFits`, which
    /// picks the first candidate (most rows) whose content fits the space. This
    /// matters on iPad, where the medium and large widget frames are shorter than
    /// their iPhone counterparts, so the family-fixed maximum (three on medium) would
    /// otherwise clip the last row off the bottom (#659). Candidates run from the
    /// configured maximum down to one, and the outer `.topLeading` frame pins the
    /// chosen list to the top so any slack sits at the bottom.
    private var listView: some View {
        ViewThatFits(in: .vertical) {
            ForEach(rowCountCandidates, id: \.self) { count in
                listStack(rowCount: count)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Row counts to try, largest first: the configured maximum for the family — or
    /// the number of pads there are, whichever is smaller — down to one.
    /// `ViewThatFits` renders the first that fits, or the last (one row) if none do.
    ///
    /// Capping at the pad count is what keeps the measuring cheap. A candidate asking
    /// for more rows than there are pads builds exactly the same subtree as one asking
    /// for all of them, so with two pads in a large widget `ViewThatFits` used to
    /// construct and measure six identical layouts before reaching one that could
    /// differ (#2137). The chosen layout is unchanged.
    private var rowCountCandidates: [Int] {
        let maximum = min(entry.rowCount.maxRows(for: family), max(entry.pads.count, 1))
        return Array(stride(from: maximum, through: 1, by: -1))
    }

    /// The header plus `rowCount` pad rows, sized to its content (no trailing spacer)
    /// so `ViewThatFits` can measure each candidate's true height.
    private func listStack(rowCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            listHeader
            ForEach(entry.pads.prefix(rowCount)) { pad in
                #if os(iOS)
                    Button(intent: OpenPadIntent(id: pad.id, account: entry.openPadAccountID)) {
                        RecentPadRow(pad: pad)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(openPadAccessibilityLabel(pad))
                    .accessibilityHint("Opens this pad in PadBuddy.")
                #else
                    Link(destination: widgetPadURL(id: pad.id, account: entry.openPadAccountID)
                        ?? fallbackURL) {
                            RecentPadRow(pad: pad)
                        }
                        .accessibilityLabel(openPadAccessibilityLabel(pad))
                        .accessibilityHint("Opens this pad in PadBuddy.")
                #endif
            }
        }
    }

    private var fallbackURL: URL {
        widgetPadsURL(account: entry.openPadAccountID) ?? URL(filePath: "/")
    }

    private func openPadAccessibilityLabel(_ pad: WidgetPadSnapshot) -> String {
        String(localized: "Open pad, \(pad.accessibilityDescription)")
    }
}

/// Creates a new pad straight from the widget. An interactive `Button` backed by
/// `CreatePadIntent`, NOT a `Link` or `Button(intent: OpenURLIntent(...))`: `Link` is
/// ignored on the small widget family and `OpenURLIntent` can't open the app's custom
/// URL scheme, so neither put a working New Pad button on every family. The intent
/// records the request in the App Group and the app performs it on activation (#456,
/// #485). When a favourite question is configured, the intent carries its account and
/// id so the app switches to that account and pre-seeds the create sheet.
@available(visionOS 26.0, *)
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityLabel: String {
        questionID == nil ? String(localized: "New Pad") : String(localized: "New Pad from Favorite Question")
    }

    private var accessibilityHint: String {
        questionID == nil
            ? String(localized: "Creates a blank pad in PadBuddy.")
            : String(localized: "Creates a pad seeded from the selected favorite question.")
    }
}

private struct RecentPadRow: View {
    let pad: WidgetPadSnapshot

    var body: some View {
        // Formatted once and used for both the label and the VoiceOver description
        // (#2136).
        let updated = pad.relativeUpdated
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
                if let updated {
                    Text(updated)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pad.accessibilityDescription(relativeUpdated: updated))
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
            .lineLimit(1)
            .frame(maxWidth: 88)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
            .overlay(Capsule().stroke(tint.opacity(0.25), lineWidth: 0.5))
    }
}

/// A minimal language→color map, duplicated locally so the widget target stays
/// The characters a pad id may contribute to a deep-link path.
private let widgetPadPathAllowed = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
)

/// A `com.adamdangoor.padbuddy://pad/<id>` link, percent-encoded and carrying the pinned
/// account.
///
/// The macOS branches interpolated `pad.id` straight into a URL string. An id containing
/// `/`, `?`, `#`, or a space either changed what the link routed to or made
/// `URL(string:)` return nil, at which point the row silently fell back to the Pads list
/// while still looking like a link to that pad (#4768). They also dropped
/// `openPadAccountID`, which the iOS intent path carries, so a widget pinned to one
/// account opened the pad under whichever account happened to be current (#4767).
func widgetPadURL(id: String, account: String?) -> URL? {
    guard !id.isEmpty,
          let encoded = id.addingPercentEncoding(withAllowedCharacters: widgetPadPathAllowed),
          encoded == id else { return nil }

    var components = URLComponents()
    components.scheme = "com.adamdangoor.padbuddy"
    components.host = "pad"
    components.percentEncodedPath = "/\(encoded)"
    if let account, !account.isEmpty {
        components.queryItems = [URLQueryItem(name: "account", value: account)]
    }
    return components.url
}

/// The Pads-list link, carrying the pinned account so the app switches to it (#4767).
func widgetPadsURL(account: String?) -> URL? {
    var components = URLComponents()
    components.scheme = "com.adamdangoor.padbuddy"
    components.host = "pads"
    if let account, !account.isEmpty {
        components.queryItems = [URLQueryItem(name: "account", value: account)]
    }
    return components.url
}

/// dependency-free (it can't import the app's `SyntaxHighlighting`). Colors are
/// chosen to stay legible as both the capsule tint and its text; an unknown
/// language falls back to the accent color, preserving the prior look. Grouped
/// aliases share a hue so, e.g., every Python variant reads the same.
func languageTint(for language: String?) -> Color {
    // The `multifile_` prefix is stripped first, as `languageDisplayName` already does for
    // the label beside this badge. Switching on the raw value meant every project pad fell
    // through to the accent colour: a badge reading "Python Project" in accent rather than
    // Python's blue, while its non-project counterpart was tinted correctly — for the one
    // badge whose whole job is telling a Python pad from a Go one at a glance (#4772).
    var lowered = language?.lowercased()
    if let value = lowered, value.hasPrefix("multifile_") {
        let base = String(value.dropFirst("multifile_".count))
        lowered = base.isEmpty ? nil : base
    }
    switch lowered {
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

#if !os(visionOS)
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
#endif
