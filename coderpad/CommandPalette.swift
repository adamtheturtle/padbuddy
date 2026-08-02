//
//  CommandPalette.swift
//  coderpad
//
//  The Cmd-K "jump to anything" palette (#526). The fuzzy-scoring engine and the UI shell
//  now live in the standalone CommandPaletteKit package (#560/#561); this file keeps only
//  the CoderPad-specific glue: the domain `PaletteKind` tags, a convenience initializer
//  that maps them onto the package's free-text `category`, and the configured palette view
//  that feeds it candidates from `CommandPaletteBuilder`.
//

import CommandPaletteKit
import SwiftUI

/// The CoderPad categories a palette row can belong to. CommandPaletteKit takes a
/// free-text `category` string; keeping a typed enum here gives the builder's call sites
/// type-safety and one place to localise the trailing tag. `rawValue` is the tag the row
/// shows (e.g. "Pad", "Command").
enum PaletteKind: String {
    case pad = "Pad"
    case question = "Question"
    case section = "Section"
    case account = "Account"
    case command = "Command"

    var localizedName: String {
        switch self {
        case .account: String(localized: "Account")
        case .command: String(localized: "Command")
        default: rawValue
        }
    }
}

extension PaletteResult {
    /// CoderPad-flavoured initializer: takes a typed ``PaletteKind`` (mapped onto the
    /// package's `category`), an SF Symbol name, and a `perform` action, so the builder's
    /// call sites read the same as they did before the engine moved into CommandPaletteKit.
    init(
        id: String,
        kind: PaletteKind,
        title: String,
        subtitle: String?,
        systemImage: String,
        searchText: String,
        onlyWhenSearching: Bool = false,
        perform: @escaping @MainActor () -> Void
    ) {
        self.init(
            id: id,
            title: title,
            subtitle: subtitle,
            category: kind.localizedName,
            systemImage: systemImage,
            searchText: searchText,
            showsOnlyWhenSearching: onlyWhenSearching,
            action: perform
        )
    }
}

/// The Cmd-K palette as presented over the main window: CommandPaletteKit's view wired to
/// the CoderPad candidate list and placeholder. The package's defaults already reproduce
/// the shipped look (620x460 surface, accent-colour selection, white-on-accent text), so
/// only the placeholder and the candidate source need supplying here.
struct CoderPadCommandPalette: View {
    @State private var padsCache = PadsCacheStore.shared
    @State private var questionsCache = QuestionsCacheStore.shared
    @State private var candidateGeneration = 0

    var body: some View {
        CommandPaletteView(
            placeholder: "Jump to a pad, question, section, account, or command…",
            scorer: diacriticInsensitivePaletteScore,
            candidates: { CommandPaletteBuilder.build() }
        )
        // CommandPaletteKit deliberately evaluates its provider once on appearance.
        // Recreate only that local UI shell when either observable list snapshot is
        // replaced, so an already-open palette cannot retain a deleted row or omit a
        // newly fetched one (#1980). The palette owns no durable navigation state, so
        // refreshing it is also safer than letting an action capture a stale record.
        .id(candidateGeneration)
        .onChange(of: padsCache.padsByAccount) { _, _ in refreshCandidates() }
        .onChange(of: questionsCache.questionsByAccount) { _, _ in refreshCandidates() }
    }

    private func refreshCandidates() {
        candidateGeneration &+= 1
    }
}

/// Match names the way Finder and Spotlight do: accents refine display, but should
/// not prevent a plain-keyboard query such as "resume" finding "Résumé" (#3152).
private nonisolated func diacriticInsensitivePaletteScore(_ query: String, _ text: String) -> Int? {
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
    return paletteFuzzyScore(
        query.folding(options: options, locale: .current),
        text.folding(options: options, locale: .current)
    )
}
