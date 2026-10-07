import SwiftUI

enum ScreenQuestionFields {
    static func included<T>(
        _ title: String, value: Binding<T?>, make: @autoclosure @escaping () -> T,
        @ViewBuilder content: (Binding<T>) -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { value.wrappedValue != nil }, set: { enabled in
                value.wrappedValue = enabled ? value.wrappedValue ?? make() : nil
            })) { Text(verbatim: title) }
            if value.wrappedValue != nil {
                content(Binding(get: { value.wrappedValue ?? make() }, set: { value.wrappedValue = $0 }))
                    .padding(.leading)
            }
        }
    }

    static func text(_ title: String, value: Binding<String?>) -> some View {
        included(title, value: value, make: "") { binding in
            TextField(String(localized: "Value"), text: binding, axis: .vertical).lineLimit(1 ... 8)
        }
    }

    static func integer(_ title: String, value: Binding<Int?>) -> some View {
        included(title, value: value, make: 0) { ScreenQuestionIntegerField(value: $0) }
    }

    static func boolean(_ title: String, value: Binding<Bool?>) -> some View {
        Picker(selection: value) {
            Text("Use service default").tag(nil as Bool?)
            Text("Enabled").tag(true as Bool?)
            Text("Disabled").tag(false as Bool?)
        } label: { Text(verbatim: title) }
    }

    static func enumeration<T: RawRepresentable & CaseIterable & Hashable>(
        _ title: String, value: Binding<T?>, type: T.Type
    ) -> some View where T.RawValue == String {
        Picker(selection: value) {
            Text("Use service default").tag(nil as T?)
            ForEach(Array(type.allCases), id: \.self) { Text(verbatim: $0.rawValue).tag(Optional($0)) }
        } label: { Text(verbatim: title) }
    }

    static func localized(_ title: String, value: Binding<[String: String]?>) -> some View {
        included(title, value: value, make: [:]) { binding in
            ScreenQuestionMap(
                value: binding,
                make: { "" },
                content: { TextField("Text", text: $0, axis: .vertical) }
            )
        }
    }

    static func timeouts(_ title: String, value: Binding<[String: Int]?>) -> some View {
        included(title, value: value, make: [:]) { binding in
            ScreenQuestionMap(value: binding, make: { 0 }, content: { ScreenQuestionIntegerField(value: $0) })
        }
    }

    static func schema(_ title: String, value: Binding<[String: JSONValue]?>) -> some View {
        included(title, value: value, make: [:]) { ScreenQuestionSchemaMap(value: $0) }
    }

    static func array<T>(
        _ title: String, value: Binding<[T]?>, make: @autoclosure @escaping () -> T,
        @ViewBuilder content: @escaping (Binding<T>) -> some View
    ) -> some View {
        included(title, value: value, make: []) { binding in
            ScreenQuestionArray(value: binding, make: make, content: content)
        }
    }
}

struct ScreenQuestionIntegerField: View {
    @Binding var value: Int
    @State private var text = ""

    var body: some View {
        TextField("Whole number", text: $text)
            .onAppear { text = String(value) }
            .onChange(of: text) { _, text in
                value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
            }
    }
}

struct ScreenQuestionArray<T, Content: View>: View {
    @Binding var value: [T]
    let make: () -> T
    @ViewBuilder let content: (Binding<T>) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(value.indices, id: \.self) { index in
                DisclosureGroup {
                    content(Binding(
                        get: { value.indices.contains(index) ? value[index] : make() },
                        set: { updated in
                            if value.indices.contains(index) {
                                value[index] = updated
                            }
                        }
                    ))
                    HStack {
                        Button("Move Up", systemImage: "arrow.up") { value.swapAt(index, index - 1) }
                            .disabled(index == 0)
                        Button("Move Down", systemImage: "arrow.down") { value.swapAt(index, index + 1) }
                            .disabled(index + 1 == value.count)
                        Button("Remove", role: .destructive) { value.remove(at: index) }
                    }
                } label: { Text("Item \(index + 1)") }
            }
            Button("Add Item", systemImage: "plus") { value.append(make()) }.disabled(value.count >= 200)
        }
    }
}

struct ScreenQuestionMap<T, Content: View>: View {
    @Binding var value: [String: T]
    let make: () -> T
    @ViewBuilder let content: (Binding<T>) -> Content
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(value.keys.sorted(), id: \.self) { key in
                VStack(alignment: .leading) {
                    HStack {
                        Text(verbatim: key).font(.caption)
                        Spacer()
                        Button("Remove", role: .destructive) { value.removeValue(forKey: key) }
                    }
                    content(Binding(get: { value[key] ?? make() }, set: { value[key] = $0 }))
                }
            }
            HStack {
                TextField("Language or field key", text: $key)
                Button("Add Field", systemImage: "plus") {
                    value[key.trimmingCharacters(in: .whitespacesAndNewlines)] = make()
                    key = ""
                }
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || value[key.trimmingCharacters(in: .whitespacesAndNewlines)] != nil || value.count >= 200)
            }
        }
    }
}
