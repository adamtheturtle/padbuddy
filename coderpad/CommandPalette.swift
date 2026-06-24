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
    case template = "Template"
    case command = "Command"
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
            category: kind.rawValue,
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
    var body: some View {
        CommandPaletteView(
            placeholder: "Jump to a pad, question, section, account, or command…",
            candidates: { CommandPaletteBuilder.build() }
        )
    }
}
