import Foundation

nonisolated struct QuestionDatabasePresentation {
    struct Column {
        let name: String
        let type: String
        let isPrimaryKey: Bool
        let isNotNull: Bool
    }

    struct Table {
        let name: String
        let columns: [Column]
        let omittedColumns: Int
    }

    let title: String
    let description: String
    let language: String
    let schema: QuestionContentPreview?
    let tables: [Table]
    let omittedTables: Int

    init(_ database: QuestionCustomDatabase) {
        title = ExternalText.singleLine(database.title ?? "", limit: 200)
        description = ExternalText.singleLine(database.description ?? "", limit: 1024)
        language = ExternalText.singleLine(database.language ?? "", limit: 80)
        let arrangement = database.schemaJSON?.arrangement ?? []
        omittedTables = max(0, arrangement.count - 16)
        tables = arrangement.prefix(16).map { table in
            Table(name: ExternalText.singleLine(table.name, limit: 120),
                  columns: table.columns.prefix(32).map {
                      Column(name: ExternalText.singleLine($0.name, limit: 120),
                             type: ExternalText.singleLine($0.type, limit: 80), isPrimaryKey: $0.pk, isNotNull: $0.nn)
                  }, omittedColumns: max(0, table.columns.count - 32))
        }
        schema = arrangement.isEmpty ? database.schema.map { QuestionContentPreview($0, limit: 16384) } : nil
    }
}
