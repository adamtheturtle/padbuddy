import SwiftUI

struct ScreenAIOriginalOutputView: View {
    let items: [JSONValue]

    static func originalJSON(_ items: [JSONValue]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(items)
        guard let json = String(bytes: bytes, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }

        return json
    }

    var body: some View {
        if let json = try? Self.originalJSON(items) {
            Text(verbatim: String(json.prefix(65536))).font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            if json.count > 65536 {
                Text("Original output is truncated to 65536 characters.").foregroundStyle(.secondary)
            }
        } else {
            Text("The original output could not be displayed.").foregroundStyle(.secondary)
        }
    }
}
