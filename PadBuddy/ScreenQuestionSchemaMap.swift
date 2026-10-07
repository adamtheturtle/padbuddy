import SwiftUI

struct ScreenQuestionSchemaMap: View {
    @Binding var value: [String: JSONValue]
    var depth = 0

    var body: some View {
        ScreenQuestionMap(value: $value, make: { .string("") }, content: {
            ScreenQuestionSchemaValue(value: $0, depth: depth)
        })
    }
}

struct ScreenQuestionSchemaValue: View {
    @Binding var value: JSONValue
    let depth: Int

    private var kind: String {
        switch value {
        case .string: "String"
        case .number: "Number"
        case .bool: "Boolean"
        case .null: "Null"
        case .object: "Object"
        case .array: "Array"
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Picker("Field type", selection: Binding(get: { kind }, set: changeKind)) {
                Text("String").tag("String")
                Text("Number").tag("Number")
                Text("Boolean").tag("Boolean")
                Text("Null").tag("Null")
                Text("Object").tag("Object")
                Text("Array").tag("Array")
            }
            content
        }
    }

    private var content: AnyView {
        switch value {
        case let .string(text):
            AnyView(TextField("Text", text: Binding(get: { text }, set: { value = .string($0) }), axis: .vertical))

        case let .number(decimal):
            AnyView(TextField(
                "Number",
                value: Binding(get: { decimal }, set: { value = .number($0) }),
                format: .number
            ))

        case let .bool(flag):
            AnyView(Toggle("Enabled", isOn: Binding(get: { flag }, set: { value = .bool($0) })))

        case .null:
            AnyView(Text("Null"))

        case let .object(fields):
            nested {
                ScreenQuestionSchemaMap(
                    value: Binding(get: { fields }, set: { value = .object($0) }),
                    depth: depth + 1
                )
            }

        case let .array(items):
            nested {
                ScreenQuestionArray(
                    value: Binding(get: { items }, set: { value = .array($0) }),
                    make: { .string("") },
                    content: { Self(value: $0, depth: depth + 1) }
                )
            }
        }
    }

    private func nested(@ViewBuilder content: () -> some View) -> AnyView {
        if depth < 16 {
            return AnyView(content())
        }
        return AnyView(Text("Nested content is preserved. Edit a shallower field to change its structure."))
    }

    private func changeKind(_ kind: String) {
        switch kind {
        case "Number": value = .number(0)
        case "Boolean": value = .bool(false)
        case "Null": value = .null
        case "Object": value = .object([:])
        case "Array": value = .array([])
        default: value = .string("")
        }
    }
}
