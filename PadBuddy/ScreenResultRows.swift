import Foundation

indirect enum ScreenResultRow: Equatable {
    case value(String, String)
    case group(String, [Self])
}

enum ScreenResultRows {
    static func value(_ label: String, _ value: (some Any)?) -> ScreenResultRow {
        .value(label, value.map { String(describing: $0) } ?? String(localized: "Not provided"))
    }

    static func value(_ label: String, _ value: Bool?) -> ScreenResultRow {
        .value(
            label,
            value.map { $0 ? String(localized: "True") : String(localized: "False") }
                ?? String(localized: "Not provided")
        )
    }

    static func group<T>(_ label: String, _ value: T?, rows: (T) -> [ScreenResultRow]) -> ScreenResultRow {
        value.map { .group(label, rows($0)) } ?? .value(label, String(localized: "Not provided"))
    }

    static func list<T>(_ label: String, _ values: [T]?, rows: (T) -> [ScreenResultRow]) -> ScreenResultRow {
        guard let values else { return .value(label, String(localized: "Not provided")) }

        var children = values.prefix(200).enumerated().map { index, value in
            ScreenResultRow.group(String(localized: "Item \(index + 1)"), rows(value))
        }
        if values.count > 200 {
            children.append(.value(
                String(localized: "Display limit"),
                String(localized: "Only the first 200 entries are shown.")
            ))
        }
        return .group(label, children)
    }

    static func values(_ label: String, _ values: [some Any]?) -> ScreenResultRow {
        list(label, values) { [.value(String(localized: "Value"), String(describing: $0))] }
    }
}
