//
//  QuestionsView.swift
//  coderpad
//

import SwiftUI

struct QuestionsView: View {
    let client: CoderPadClient
    @Environment(\.orgDirectory) private var directory
    @State private var questions: [Question] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var selection: Question?
    @State private var search = ""
    @State private var languageFilter: String? = nil
    @State private var ownerFilter: String? = nil
    @State private var takeHomeFilter: String? = nil
    @State private var draftFilter: String? = nil

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 300, ideal: 360)
        } detail: {
            if let selection {
                QuestionDetailView(question: selection)
                    .id(selection.id)
            } else {
                ContentUnavailableView("Select a question",
                                       systemImage: "questionmark.bubble",
                                       description: Text("Pick one to view details."))
            }
        }
        .task(id: client.apiKey) { await reload() }
    }

    private var filtered: [Question] {
        let lowered = search.lowercased()
        return questions.filter { q in
            (languageFilter == nil || (q.language ?? "").lowercased() == languageFilter) &&
            (ownerFilter == nil || q.ownerEmail == ownerFilter) &&
            (takeHomeFilter == nil
             || (takeHomeFilter == "yes" && q.takeHome == true)
             || (takeHomeFilter == "no" && q.takeHome != true)) &&
            (draftFilter == nil
             || (draftFilter == "draft" && q.isDraft == true)
             || (draftFilter == "published" && q.isDraft != true)) &&
            (lowered.isEmpty
             || q.title.lowercased().contains(lowered)
             || q.ownerEmail.lowercased().contains(lowered)
             || (q.language ?? "").lowercased().contains(lowered)
             || (q.authorName ?? "").lowercased().contains(lowered))
        }
    }

    private var availableLanguages: [String] {
        Array(Set(questions.compactMap { $0.language?.lowercased() }).filter { !$0.isEmpty }).sorted()
    }
    private var availableOwners: [String] {
        Array(Set(questions.map { $0.ownerEmail }).filter { !$0.isEmpty }).sorted()
    }

    private var activeFilterCount: Int {
        [languageFilter, ownerFilter, takeHomeFilter, draftFilter].compactMap { $0 }.count
    }

    private var sidebar: some View {
        Group {
            if isLoading && questions.isEmpty {
                ProgressView("Loading questions…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                APIErrorView(error: error) { Task { await reload() } }
            } else {
                VStack(spacing: 0) {
                    filterBar
                    Divider()
                    List(filtered, selection: $selection) { q in
                        NavigationLink(value: q) {
                            QuestionRow(question: q)
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .navigationTitle("Questions")
        .searchable(text: $search, placement: .toolbar, prompt: "Search title, author…")
        .toolbar {
            ToolbarItem {
                Button { Task { await reload() } } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
    }

    @ViewBuilder
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChipMenu(title: "Language", icon: "chevron.left.slash.chevron.right",
                               selected: $languageFilter, options: availableLanguages,
                               formatter: { $0 })
                SearchableFilterChip(title: "Owner", icon: "person",
                                     selected: $ownerFilter, options: availableOwners,
                                     formatter: { directory.display($0) })
                FilterChipMenu(title: "Take-home", icon: "house",
                               selected: $takeHomeFilter, options: ["yes", "no"],
                               formatter: { $0.capitalized })
                FilterChipMenu(title: "Status", icon: "doc.badge.ellipsis",
                               selected: $draftFilter, options: ["draft", "published"],
                               formatter: { $0.capitalized })
                if activeFilterCount > 0 {
                    Button(role: .destructive) {
                        languageFilter = nil; ownerFilter = nil
                        takeHomeFilter = nil; draftFilter = nil
                    } label: {
                        Label("Clear", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func reload() async {
        guard !client.apiKey.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let fetched = try await client.listQuestions()
            questions = fetched.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        } catch {
            self.error = error
        }
    }
}

private struct QuestionRow: View {
    let question: Question

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarCircle(label: question.ownerEmail, diameter: 30, tint: .indigo)
            VStack(alignment: .leading, spacing: 4) {
                Text(question.title.isEmpty ? "#\(question.id)" : question.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let lang = question.language, !lang.isEmpty {
                        Chip(text: lang, systemImage: "chevron.left.slash.chevron.right", tint: lang.languageColor)
                    }
                    if question.takeHome == true {
                        Chip(text: "Take-home", systemImage: "house", tint: .pink)
                    }
                    if let used = question.used, used > 0 {
                        Chip(text: "Used \(used)×", systemImage: "chart.bar", tint: .blue)
                    }
                    if question.isDraft == true {
                        Chip(text: "Draft", systemImage: "doc.badge.ellipsis", tint: .orange)
                    }
                }
                if let author = question.authorName {
                    Text(author).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct QuestionDetailView: View {
    let question: Question

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metaCards
                if let description = question.description, !description.isEmpty {
                    descriptionCard(title: "Description", body: description)
                }
                if !question.candidateInstructions.isEmpty {
                    instructionsCard
                }
                if let solution = question.solution, !solution.isEmpty {
                    descriptionCard(title: "Solution", body: solution)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(question.title.isEmpty ? "#\(question.id)" : question.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AvatarCircle(label: question.ownerEmail, diameter: 48, tint: .indigo)
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.title.isEmpty ? "Untitled Question" : question.title)
                        .font(.title2.weight(.semibold))
                    if let author = question.authorName {
                        Text(author).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            HStack(spacing: 6) {
                if let lang = question.language, !lang.isEmpty {
                    Chip(text: lang, systemImage: "chevron.left.slash.chevron.right", tint: lang.languageColor)
                }
                if let type = question.padType, !type.isEmpty {
                    Chip(text: type, systemImage: "tag")
                }
                if question.takeHome == true {
                    Chip(text: "Take-home", systemImage: "house", tint: .pink)
                }
                if question.shared == true {
                    Chip(text: "Shared", systemImage: "person.2", tint: .blue)
                }
                if question.testCasesEnabled == true {
                    Chip(text: "Test cases", systemImage: "checkmark.seal", tint: .teal)
                }
                if question.isDraft == true {
                    Chip(text: "Draft", systemImage: "doc.badge.ellipsis", tint: .orange)
                }
            }
        }
    }

    private var metaCards: some View {
        HStack(spacing: 12) {
            if let used = question.used {
                StatTile(title: "Times used", value: "\(used)", systemImage: "chart.bar.fill", tint: .blue)
            }
            if let createdAt = question.createdAt {
                StatTile(title: "Created", value: createdAt.formatted(date: .abbreviated, time: .omitted),
                         systemImage: "calendar.badge.plus", tint: .teal)
            }
            if let updatedAt = question.updatedAt {
                StatTile(title: "Updated", value: updatedAt.formatted(date: .abbreviated, time: .omitted),
                         systemImage: "clock.arrow.circlepath", tint: .orange)
            }
        }
    }

    private var instructionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Candidate Instructions", systemImage: "text.book.closed")
                ForEach(Array(question.candidateInstructions.enumerated()), id: \.offset) { _, item in
                    Text(item.instructions.isEmpty ? "(empty)" : item.instructions)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func descriptionCard(title: String, body: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title, systemImage: "doc.text")
                Text(body)
                    .font(.callout)
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
