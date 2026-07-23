//
//  QuestionDetailView+Cards.swift
//  coderpad
//
//  The lower question-detail cards (test cases, custom files, starter code, and the
//  inline-editable description/solution), split from QuestionDetailView+Content.swift
//  to keep that file within the lint length budget.
//

import SwiftUI

extension QuestionDetailView {
    @ViewBuilder
    var customDatabaseCard: some View {
        if let database = question.customDatabase {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Database", systemImage: "cylinder")
                if let title = database.title, !title.isEmpty { Text(title).font(.headline) }
                if let description = database.description, !description.isEmpty {
                    Text(description).foregroundStyle(.secondary)
                }
                if let language = database.language, !language.isEmpty {
                    LabeledRow(label: "Language", value: language)
                }
                if let tables = database.schemaJSON?.arrangement, !tables.isEmpty {
                    ForEach(Array(tables.enumerated()), id: \.offset) { _, table in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(table.name).font(.callout.weight(.semibold)).textSelection(.enabled)
                            ForEach(Array(table.columns.enumerated()), id: \.offset) { _, column in
                                let constraints = [column.pk ? "primary key" : nil,
                                                   column.nn ? "not null" : nil].compactMap(\.self)
                                Text(
                                    "\(column.name): \(column.type)"
                                        + "\(constraints.isEmpty ? "" : " (\(constraints.joined(separator: ", ")))")"
                                )
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } else if let schema = database.schema, !schema.isEmpty {
                    Text(schema).font(.callout.monospaced()).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The question's test cases, shown to an interviewer in full. The candidate
    /// only sees the cases marked `visible`, so hidden ones carry a badge to make
    /// that distinction clear when reviewing.
    var testCasesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Test Cases", systemImage: "checkmark.seal")
            ForEach(question.testCases) { testCase in
                testCaseRow(testCase)
                if testCase.id != question.testCases.last?.id {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func testCaseRow(_ testCase: QuestionTestCase) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                testCaseLine(label: "Input", value: argumentsDisplay(testCase.arguments))
                testCaseLine(label: "Expected", value: testCase.returnValue ?? String(localized: "None"))
            }
            Spacer(minLength: 8)
            if testCase.visible == false {
                Chip(text: String(localized: "Hidden"), systemImage: "eye.slash", tint: .gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func testCaseLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The API returns each argument as its own already-formatted string (e.g. a
    /// quoted string or a JSON literal), so join them into a call-style list.
    func argumentsDisplay(_ arguments: [String]?) -> String {
        guard let arguments, !arguments.isEmpty else { return String(localized: "None") }

        return arguments.joined(separator: ", ")
    }

    /// The question's attached custom files. The API exposes only metadata (name,
    /// description, size) for these, not their contents, so this is a manifest of
    /// what's bundled rather than a viewer.
    var filesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Files", systemImage: "doc.on.doc")
            ForEach(Array(question.customFiles.enumerated()), id: \.offset) { index, file in
                fileRow(file)
                if index != question.customFiles.count - 1 {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func fileRow(_ file: QuestionCustomFile) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName(file))
                    .font(.callout.weight(.medium))
                    .textSelection(.enabled)
                if let description = file.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let size = file.filesize, !size.isEmpty {
                Text(size)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A display name for a custom file: its filename, falling back to its title,
    /// then a generic placeholder when the API supplies neither.
    func fileName(_ file: QuestionCustomFile) -> String {
        if let filename = file.filename, !filename.isEmpty { return filename }
        if let title = file.title, !title.isEmpty { return title }
        return String(localized: "Untitled file")
    }

    /// The starter code a candidate begins from when this question is used (the
    /// API's `contents`), plus the test-cases variant when it's present and
    /// meaningfully different. Already in hand from the question fetch — no extra
    /// call — and hidden when absent.
    @ViewBuilder
    var starterCodeCards: some View {
        if let contents = question.contents, !contents.isEmpty {
            starterCodeCard(title: "Starter Code", code: contents)
            if question.contentsForTestCases?.isEmpty == false, question.contentsForTestCases != contents {
                Divider()
            }
        }
        if let testContents = question.contentsForTestCases, !testContents.isEmpty,
           testContents != question.contents {
            starterCodeCard(title: "Starter Code (Test Cases)", code: testContents)
        }
    }

    func starterCodeCard(title: LocalizedStringKey, code: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, systemImage: "chevron.left.slash.chevron.right")
            HighlightedCode(
                contents: code, language: question.language, dark: colorScheme == .dark, usesCodeWell: true
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The question's description, edited in place. Always shown (empty or not) so
    /// a missing description can be added without a separate editor (#333, #335).
    var descriptionCard: some View {
        editableLongFormCard(title: "Description", text: question.description ?? "",
                             placeholder: "Empty", label: "description") {
            await commitDescription($0, basedOn: $1)
        }
    }

    /// The question's solution, edited in place, always shown like the description.
    var solutionCard: some View {
        editableLongFormCard(title: "Solution", text: question.solution ?? "",
                             placeholder: "Empty", label: "solution", showsHeader: false) {
            await commitSolution($0, basedOn: $1)
        }
    }

    /// A section pairing its header with an inline-editable long-form field.
    /// `onSave` returns `true` once the edit is committed so the editor can close.
    func editableLongFormCard(title: LocalizedStringKey, text: String, placeholder: LocalizedStringKey, label: String,
                              showsHeader: Bool = true,
                              onSave: @escaping (String, String) async -> Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                SectionHeader(title: title, systemImage: "doc.text")
            }
            InlineEditableText(text: text, placeholder: placeholder, label: label,
                               draftKey: inlineDraftKey(label), onSave: onSave)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Identity for a field's stashed in-progress edit (#1020): account-qualified,
    /// since per-org question ids collide across accounts in the combined view.
    func inlineDraftKey(_ field: String) -> String {
        "question/\(accountID?.uuidString ?? "current")/\(question.id)/\(field)"
    }
}
