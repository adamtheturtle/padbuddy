import SwiftUI

extension QuestionDetailView {
    @ViewBuilder
    var customDatabaseCard: some View {
        if let database = question.customDatabase {
            QuestionDatabasePreview(database: QuestionDatabasePresentation(database))
        }
    }
}

struct QuestionDatabasePreview: View {
    let database: QuestionDatabasePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Database", systemImage: "cylinder")
            if !database.title.isEmpty {
                Text(database.title).font(.headline)
            }
            if !database.description.isEmpty {
                Text(database.description).foregroundStyle(.secondary)
            }
            if !database.language.isEmpty {
                LabeledRow(label: "Language", value: database.language)
            }
            ForEach(Array(database.tables.enumerated()), id: \.offset) { _, table in
                tablePreview(table)
            }
            if database.omittedTables > 0 {
                Text(String(localized: "\(database.omittedTables) tables omitted.", table: "QuestionPreviews"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let schema = database.schema, !schema.text.isEmpty {
                Text(schema.text).font(.callout.monospaced()).textSelection(.enabled)
                if schema.isTruncated {
                    QuestionPreviewNotice()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tablePreview(_ table: QuestionDatabasePresentation.Table) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(table.name).font(.callout.weight(.semibold)).textSelection(.enabled)
            ForEach(Array(table.columns.enumerated()), id: \.offset) { _, column in
                let constraints = [column.isPrimaryKey ? "primary key" : nil,
                                   column.isNotNull ? "not null" : nil].compactMap(\.self)
                Text("\(column.name): \(column.type)"
                    + "\(constraints.isEmpty ? "" : " (\(constraints.joined(separator: ", ")))")")
                    .font(.caption.monospaced()).textSelection(.enabled)
            }
            if table.omittedColumns > 0 {
                Text(String(localized: "\(table.omittedColumns) columns omitted.", table: "QuestionPreviews"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
