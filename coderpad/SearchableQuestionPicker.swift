//
//  SearchableQuestionPicker.swift
//  coderpad
//
//  Split from PadOwnerPicker.swift to keep it within the lint length limit:
//  the searchable question picker (a sibling of the owner picker) moved here.
//

import SwiftUI

/// A searchable replacement for a long `Picker` of questions. Shows the current
/// selection as a button; tapping opens a popover with a search field that filters
/// the (potentially large) question list so you don't scroll a huge menu.
struct SearchableQuestionPicker: View {
    @Binding var selection: Int?
    let questions: [Question]

    @State private var isPresented = false
    @State private var query = ""
    /// Deduplicated display rows with precomputed titles and search keys, rebuilt only
    /// when `questions` changes: filtering per keystroke used to re-derive every title
    /// and run a locale-aware compare over the whole list (#2227, #2229).
    @State private var options: [Option] = []
    /// Id-keyed titles so labeling the button doesn't linear-scan the list per render (#2230).
    @State private var titlesByID: [Int: String] = [:]
    @FocusState private var searchFocused: Bool
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// One selectable question row: its display title plus a lowercased search key.
    private struct Option: Identifiable, Equatable {
        let id: Int
        let title: String
        let searchKey: String
    }

    private func title(for question: Question) -> String {
        // Whitespace-only titles fall back to the stable #id label too, not just
        // empty ones, so no option row renders blank (#2215).
        let trimmed = question.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "#\(question.id)" : trimmed
    }

    /// Rebuilds the option rows and the id-keyed title lookup. Duplicate ids (e.g. a
    /// question present in both cache and a fresh API page) keep their first occurrence
    /// so `ForEach` identities stay unique (#2212).
    private func rebuildOptions() {
        var seen = Set<Int>()
        var rows: [Option] = []
        rows.reserveCapacity(questions.count)
        var titles = [Int: String](minimumCapacity: questions.count)
        for question in questions {
            guard seen.insert(question.id).inserted else { continue }

            let title = title(for: question)
            titles[question.id] = title
            // The search key covers the visible title plus the id, language, and owner,
            // so a known question number or language also finds the row (#2213).
            let language = question.language ?? ""
            rows.append(Option(
                id: question.id,
                title: title,
                searchKey: "\(title) #\(question.id) \(language) \(question.ownerEmail)".lowercased()
            ))
        }
        options = rows
        titlesByID = titles
    }

    private var selectedTitle: String {
        guard let id = selection else { return String(localized: "None") }

        if let title = titlesByID[id] { return title }
        // Before the first rebuild the lookup is empty; resolve directly so the
        // label never flashes the unavailable fallback.
        if let question = questions.first(where: { $0.id == id }) { return title(for: question) }

        // A stale saved selection that no longer exists in the list is shown as
        // such instead of being concealed as "None" (#2211).
        return String(localized: "Question #\(id) (unavailable)")
    }

    private var filtered: [Option] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return options }

        let needle = trimmed.lowercased()
        return options.filter { $0.searchKey.contains(needle) }
    }

    #if os(iOS)
        private var usesSheetPresentation: Bool {
            horizontalSizeClass == .compact
        }
    #else
        private var usesSheetPresentation: Bool {
            false
        }
    #endif

    var body: some View {
        picker
            .onAppear(perform: rebuildOptions)
            .onChange(of: questions) { rebuildOptions() }
    }

    @ViewBuilder
    private var picker: some View {
        #if os(iOS)
            if usesSheetPresentation {
                button
                    .sheet(isPresented: $isPresented) {
                        NavigationStack {
                            pickerContent(maxListHeight: nil)
                                .navigationTitle("Question")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button("Done") { isPresented = false }
                                    }
                                }
                        }
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                        .onAppear { searchFocused = true }
                    }
            } else {
                popoverButton
            }
        #else
            popoverButton
        #endif
    }

    private var popoverButton: some View {
        button
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                pickerContent(maxListHeight: 240)
                    .frame(width: 320)
                    .onAppear { searchFocused = true }
            }
    }

    private var button: some View {
        Button {
            // Each opening starts unfiltered: keeping the previous search text made
            // a reopened picker look mysteriously empty or incomplete (#2214).
            query = ""
            isPresented = true
        } label: {
            HStack {
                Text(selectedTitle)
                    .foregroundStyle(selection == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // Decorative dropdown indicator: the button's text already names
                    // the selection, so VoiceOver shouldn't read the symbol on top.
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: 280, alignment: .leading)
        .buttonStyle(.bordered)
    }

    private func pickerContent(maxListHeight: CGFloat?) -> some View {
        VStack(spacing: 0) {
            TextField("Search questions", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding(8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    questionRow(id: nil, title: String(localized: "None"))
                    ForEach(filtered) { option in
                        questionRow(id: option.id, title: option.title)
                    }
                    if filtered.isEmpty {
                        Text("No questions match “\(query)”")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .padding(8)
                    }
                }
            }
            .frame(maxHeight: maxListHeight)
        }
    }

    @ViewBuilder
    private func questionRow(id: Int?, title: String) -> some View {
        let isSelected = id == selection
        Button {
            selection = id
            isPresented = false
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(id == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Selected")
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, usesSheetPresentation ? 12 : 6)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
    }
}
