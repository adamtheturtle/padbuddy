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
    @FocusState private var searchFocused: Bool
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private func title(for question: Question) -> String {
        question.title.isEmpty ? "#\(question.id)" : question.title
    }

    private var selectedTitle: String {
        guard let id = selection,
              let question = questions.first(where: { $0.id == id }) else { return String(localized: "None") }

        return title(for: question)
    }

    private var filtered: [Question] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return questions }

        return questions.filter { title(for: $0).localizedCaseInsensitiveContains(trimmed) }
    }

    #if os(iOS)
    private var usesSheetPresentation: Bool {
        horizontalSizeClass == .compact
    }
    #else
    private var usesSheetPresentation: Bool { false }
    #endif

    var body: some View {
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
                    ForEach(filtered) { question in
                        questionRow(id: question.id, title: title(for: question))
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
