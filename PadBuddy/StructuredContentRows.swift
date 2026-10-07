import Foundation

nonisolated struct StructuredContentRow: Identifiable, Equatable {
    let id: Int
    let label: String
    let text: String
    let depth: Int
}

nonisolated struct StructuredContentRows {
    let rows: [StructuredContentRow]
    let truncated: Bool

    init(_ value: JSONValue) {
        var rows: [StructuredContentRow] = []
        var truncated = false
        Self.append(value, label: "", depth: 0, rows: &rows, truncated: &truncated)
        self.rows = rows
        self.truncated = truncated
    }

    private static func append(_ value: JSONValue, label: String, depth: Int,
                               rows: inout [StructuredContentRow], truncated: inout Bool) {
        guard rows.count < 200, depth <= 16 else {
            truncated = true
            return
        }

        switch value {
        case let .object(fields):
            appendObject(fields, label: label, depth: depth, rows: &rows, truncated: &truncated)

        case let .array(values):
            appendArray(values, label: label, depth: depth, rows: &rows, truncated: &truncated)

        default:
            let text = scalarText(value)
            if text.count > 8192 {
                truncated = true
            }
            rows.append(StructuredContentRow(id: rows.count, label: label,
                                             text: String(text.prefix(8192)), depth: depth))
        }
    }

    private static func appendObject(_ fields: [String: JSONValue], label: String, depth: Int,
                                     rows: inout [StructuredContentRow], truncated: inout Bool) {
        if !label.isEmpty {
            rows.append(StructuredContentRow(id: rows.count, label: label, text: "", depth: depth))
        }
        for key in fields.keys.sorted().prefix(201) {
            guard let field = fields[key] else { continue }

            append(field, label: key.replacingOccurrences(of: "_", with: " "), depth: depth + 1,
                   rows: &rows, truncated: &truncated)
        }
        if fields.count > 201 {
            truncated = true
        }
    }

    private static func appendArray(_ values: [JSONValue], label: String, depth: Int,
                                    rows: inout [StructuredContentRow], truncated: inout Bool) {
        if !label.isEmpty {
            rows.append(StructuredContentRow(id: rows.count, label: label, text: "", depth: depth))
        }
        for (index, field) in values.prefix(201).enumerated() {
            append(field, label: String(index + 1), depth: depth + 1, rows: &rows, truncated: &truncated)
        }
        if values.count > 201 {
            truncated = true
        }
    }

    private static func scalarText(_ value: JSONValue) -> String {
        switch value {
        case let .string(text): text

        case let .number(number): number.description

        case let .bool(boolean): if boolean {
                String(localized: "Yes")
            } else {
                String(localized: "No")
            }

        case .null: String(localized: "Not provided")

        default: ""
        }
    }
}
