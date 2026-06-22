//
//  CommandPalette.swift
//  coderpad
//
//  An in-app, instant "jump to anything" palette (Cmd-K, #526): type to fuzzy-search
//  across pads, questions, sections, and accounts, plus a few common commands (New Pad,
//  Reload, Open Pad by URL). Results come straight from the in-memory caches
//  (`PadsCacheStore` / `QuestionsCacheStore`), so there's no network round-trip and no
//  index to build - distinct from the system-wide Spotlight indexing. Selecting a result
//  routes through the existing `AppNavigation` (switching account first when the item
//  belongs to another one, mirroring the Spotlight-result path), so the palette adds no
//  new navigation machinery of its own.
//

import AppKit
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
        case template = "Template"
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
/// fuzzy subsequence match that rewards consecutive runs - enough to feel smart without
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
    /// Local key-event monitor for the up/down arrows. The search field is focused so
    /// the user can type, but AppKit's field editor then swallows the arrow keys for
    /// caret movement before SwiftUI's `.onKeyPress` ever sees them (#532) - so we watch
    /// for them at the event level and drive the selection ourselves.
    @State private var arrowKeyMonitor: Any?

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
            installArrowKeyMonitor()
        }
        .onDisappear(perform: removeArrowKeyMonitor)
    }

    /// Watches key-down events while the palette is open and moves the selection on the
    /// up/down arrows, consuming them so the focused field doesn't also move its caret.
    /// `keyCode` 125 is the down arrow, 126 the up arrow.
    private func installArrowKeyMonitor() {
        guard arrowKeyMonitor == nil else { return }

        arrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 125: move(by: 1); return nil
            case 126: move(by: -1); return nil
            default: return event
            }
        }
    }

    private func removeArrowKeyMonitor() {
        if let monitor = arrowKeyMonitor {
            NSEvent.removeMonitor(monitor)
            arrowKeyMonitor = nil
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.title3)
                .accessibilityHidden(true)
            TextField("Jump to a pad, question, section, account, or command…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($queryFocused)
                .onSubmit(activateSelection)
                .onChange(of: query) { _, _ in selectedIndex = 0 }
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
                                // Identify the row by the result's stable id (matching the
                                // ForEach identity), not its position: a bare `.id(index)`
                                // keeps ids 0,1,2… fixed while a search re-orders the content
                                // under them, so the highlight and scroll target drift (#535).
                                .id(result.id)
                                .contentShape(Rectangle())
                                .onTapGesture { activate(result) }
                                // One combined element per row so VoiceOver reads it as a
                                // single button, and the selected one announces (and exposes
                                // for tests, #532) the `.isSelected` trait.
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
                        }
                    }
                }
                .padding(8)
            }
            .onChange(of: selectedIndex) { _, new in
                // Scroll by the selected result's stable id, and only enough to keep it
                // visible (no forced centering, which lurches a short filtered list).
                guard results.indices.contains(new) else { return }

                let id = results[new].id
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) }
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
                .accessibilityHidden(true)
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
