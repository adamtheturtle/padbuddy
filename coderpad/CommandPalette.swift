//
//  CommandPalette.swift
//  coderpad
//
//  An in-app, instant "jump to anything" palette (Cmd-K, #526): type to fuzzy-search
//  across pads, questions, sections, and accounts, plus a few common commands (New Pad,
//  Reload, Open Pad by URL). Results come straight from the in-memory caches
//  (`PadsCacheStore` / `QuestionsCacheStore`), so there's no network round-trip and no
//  index to build — distinct from the system-wide Spotlight indexing. Selecting a result
//  routes through the existing `AppNavigation` (switching account first when the item
//  belongs to another one, mirroring the Spotlight-result path), so the palette adds no
//  new navigation machinery of its own.
//

import SwiftUI

/// One row in the command palette: enough to render it and a closure that performs its
/// action on the main actor. `id` is namespaced by kind so ids never collide across
/// categories (a pad slug and a question number could otherwise clash).
struct PaletteResult: Identifiable {
    enum Kind: String {
        case pad = "Pad"
        case question = "Question"
        case section = "Section"
        case account = "Account"
        case command = "Command"
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let systemImage: String
    /// The text the query is scored against (usually the title, sometimes with extra
    /// keywords folded in so a command like "Reload" can also be found by "refresh").
    let searchText: String
    let perform: @MainActor () -> Void
}

/// Scores how well `query` matches `text`; higher is better, `nil` means no match. An
/// empty query matches everything at a neutral score (so the full list shows). Exact and
/// prefix matches rank highest, then substring (with a word-boundary bonus), then a
/// fuzzy subsequence match that rewards consecutive runs — enough to feel smart without
/// pulling in a dependency.
func paletteFuzzyScore(_ query: String, _ text: String) -> Int? {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return 0 }

    let haystack = text.lowercased()
    let needle = trimmed.lowercased()

    if haystack == needle { return 1000 }
    if haystack.hasPrefix(needle) { return 850 }

    if let range = haystack.range(of: needle) {
        let start = range.lowerBound
        let atWordStart = start == haystack.startIndex
            || !haystack[haystack.index(before: start)].isLetter
            && !haystack[haystack.index(before: start)].isNumber
        let offset = haystack.distance(from: haystack.startIndex, to: start)
        return (atWordStart ? 650 : 450) - min(offset, 100)
    }

    // Subsequence match: every character of the needle appears in order. Consecutive
    // matches score progressively higher so "npd" prefers "NewPaD" over scattered hits.
    var score = 0
    var consecutive = 0
    var index = haystack.startIndex
    for character in needle {
        var matched = false
        while index < haystack.endIndex {
            let current = haystack[index]
            index = haystack.index(after: index)
            if current == character {
                matched = true
                consecutive += 1
                score += 8 + consecutive
                break
            }
            consecutive = 0
        }
        if !matched { return nil }
    }
    return score
}

/// The Cmd-K palette, presented as a sheet over the main window. Owns the query and the
/// keyboard-driven selection; the candidate list is rebuilt on appear from the caches and
/// re-scored on every keystroke.
struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var candidates: [PaletteResult] = []
    @State private var selectedIndex = 0
    @FocusState private var queryFocused: Bool

    /// At most this many results are shown, so a huge org doesn't render thousands of
    /// rows; the highest-scoring ones win.
    private let resultLimit = 40

    private var results: [PaletteResult] {
        let scored = candidates.compactMap { result -> (PaletteResult, Int)? in
            guard let score = paletteFuzzyScore(query, result.searchText) else { return nil }
            return (result, score)
        }
        // Stable order: by score, then keep the original (already category-grouped) order
        // for ties so an empty query reads top-to-bottom as Commands, Sections, then data.
        return scored
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.1 != rhs.element.1 ? lhs.element.1 > rhs.element.1 : lhs.offset < rhs.offset
            }
            .prefix(resultLimit)
            .map(\.element.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsList
        }
        .frame(width: 620, height: 460)
        .onAppear {
            candidates = CommandPaletteBuilder.build()
            queryFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.title3)
            TextField("Jump to a pad, question, section, account, or command…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($queryFocused)
                .onSubmit(activateSelection)
                .onChange(of: query) { _, _ in selectedIndex = 0 }
                .onKeyPress(.downArrow) { move(by: 1); return .handled }
                .onKeyPress(.upArrow) { move(by: -1); return .handled }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .onExitCommand { dismiss() }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if results.isEmpty {
                        Text(query.trimmingCharacters(in: .whitespaces).isEmpty
                            ? "Start typing to search."
                            : "No matches.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            PaletteRow(result: result, isSelected: index == selectedIndex)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture { activate(result) }
                        }
                    }
                }
                .padding(8)
            }
            .onChange(of: selectedIndex) { _, new in
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    /// Moves the selection by `delta`, clamped to the result bounds.
    private func move(by delta: Int) {
        let count = results.count
        guard count > 0 else { return }

        selectedIndex = min(max(selectedIndex + delta, 0), count - 1)
    }

    private func activateSelection() {
        let current = results
        guard current.indices.contains(selectedIndex) else { return }

        activate(current[selectedIndex])
    }

    private func activate(_ result: PaletteResult) {
        dismiss()
        result.perform()
    }
}

/// A single palette row: leading glyph, title and optional subtitle, and a trailing
/// category tag. Highlights when it's the keyboard selection.
private struct PaletteRow: View {
    let result: PaletteResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.systemImage)
                .frame(width: 22)
                .foregroundStyle(isSelected ? Color.white : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white : .primary)
                if let subtitle = result.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
                }
            }
            Spacer(minLength: 8)
            Text(result.kind.rawValue)
                .font(.caption2)
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }
}

/// Assembles the palette's candidate list from the shared stores. Ordered Commands,
/// Sections, Accounts, then Pads and Questions, so an empty query reads sensibly and ties
/// in scoring keep that order.
@MainActor
enum CommandPaletteBuilder {
    static func build() -> [PaletteResult] {
        var results: [PaletteResult] = []
        results += commands()
        results += sections()
        results += accounts()
        results += padsAndQuestions()
        return results
    }

    private static func commands() -> [PaletteResult] {
        [
            PaletteResult(
                id: "command.new-pad",
                kind: .command,
                title: "New Pad",
                subtitle: "Create a pad",
                systemImage: "plus.square",
                searchText: "New Pad create"
            ) { AppNavigation.shared.showPads(PadsRequest(startCreating: true)) },
            PaletteResult(
                id: "command.new-question",
                kind: .command,
                title: "New Question",
                subtitle: "Create a question",
                systemImage: "plus.bubble",
                searchText: "New Question create"
            ) { AppNavigation.shared.showQuestions(QuestionsRequest(startCreating: true)) },
            PaletteResult(
                id: "command.open-by-url",
                kind: .command,
                title: "Open Pad by URL…",
                subtitle: "Open a pad from its link",
                systemImage: "link",
                searchText: "Open Pad by URL link"
            ) { AppRouter.requestOpenPadByURL() },
            PaletteResult(
                id: "command.reload",
                kind: .command,
                title: "Reload",
                subtitle: "Refresh the current section",
                systemImage: "arrow.clockwise",
                searchText: "Reload refresh"
            ) { AppRouter.requestReload() },
        ]
    }

    private static func sections() -> [PaletteResult] {
        AppSection.navigable.map { section in
            let meta = paletteMeta(section)
            return PaletteResult(
                id: "section.\(section.rawValue)",
                kind: .section,
                title: meta.label,
                subtitle: "Go to \(meta.label)",
                systemImage: meta.icon,
                searchText: meta.label
            ) { AppNavigation.shared.show(section) }
        }
    }

    private static func accounts() -> [PaletteResult] {
        let store = AccountsStore.shared
        // Only worth offering as a switch target when there's more than one account.
        guard store.accounts.count > 1 else { return [] }

        return store.accounts.map { account in
            PaletteResult(
                id: "account.\(account.id.uuidString)",
                kind: .account,
                title: account.name,
                subtitle: account.userEmail.isEmpty ? "Switch account" : account.userEmail,
                systemImage: "person.crop.circle",
                searchText: "\(account.name) \(account.userEmail)"
            ) { AccountsStore.shared.currentAccountID = account.id }
        }
    }

    private static func padsAndQuestions() -> [PaletteResult] {
        let store = AccountsStore.shared
        let accounts = store.isMergedView ? store.mergeableAccounts : [store.currentAccount].compactMap { $0 }
        let showAccount = accounts.count > 1

        var results: [PaletteResult] = []
        for account in accounts {
            for pad in PadsCacheStore.shared.get(account.id) {
                let title = pad.title.isEmpty ? pad.id : pad.title
                results.append(PaletteResult(
                    id: "pad.\(account.id.uuidString).\(pad.id)",
                    kind: .pad,
                    title: title,
                    subtitle: subtitle(account: showAccount ? account.name : nil, detail: pad.ownerEmail),
                    systemImage: "doc.text",
                    searchText: "\(title) \(pad.ownerEmail)"
                ) { jump(toPad: pad.id, in: account.id) })
            }
            for question in QuestionsCacheStore.shared.get(account.id) {
                results.append(PaletteResult(
                    id: "question.\(account.id.uuidString).\(question.id)",
                    kind: .question,
                    title: question.displayTitle,
                    subtitle: subtitle(account: showAccount ? account.name : nil, detail: question.language),
                    systemImage: "questionmark.bubble",
                    searchText: "\(question.displayTitle) \(question.language ?? "")"
                ) { jump(toQuestion: question.id, in: account.id) })
            }
        }
        return results
    }

    /// Switches to `account` (only if it isn't already current — per-org question ids
    /// collide, so the owning account must be selected first, exactly as the Spotlight
    /// result path does) and selects the pad once its list has it.
    private static func jump(toPad id: String, in account: UUID) {
        if AccountsStore.shared.currentAccountID != account,
           AccountsStore.shared.accounts.contains(where: { $0.id == account }) {
            AccountsStore.shared.currentAccountID = account
        }
        AppNavigation.shared.showFavoritePad(id: id)
    }

    private static func jump(toQuestion id: Int, in account: UUID) {
        if AccountsStore.shared.currentAccountID != account,
           AccountsStore.shared.accounts.contains(where: { $0.id == account }) {
            AccountsStore.shared.currentAccountID = account
        }
        AppNavigation.shared.showFavoriteQuestion(id: id)
    }

    /// Joins an optional account name and an optional detail into one subtitle line.
    private static func subtitle(account: String?, detail: String?) -> String? {
        let parts = [account, detail?.isEmpty == true ? nil : detail].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The label and SF Symbol for each navigable section. Mirrors the sidebar's own
    /// `sectionMeta` (kept here as plain strings since the palette scores against them).
    private static func paletteMeta(_ section: AppSection) -> (label: String, icon: String) {
        switch section {
        case .pads: ("Pads", "doc.text")
        case .questions: ("Questions", "questionmark.bubble")
        case .organization: ("Organization", "building.2")
        case .quota: ("Quota", "gauge.with.dots.needle.67percent")
        case .screen: ("Screen", "person.crop.rectangle.stack")
        }
    }
}
