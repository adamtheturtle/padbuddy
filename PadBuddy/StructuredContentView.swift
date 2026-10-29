import SwiftUI

struct StructuredContentView: View {
    let content: StructuredContentRows

    init(_ value: JSONValue) {
        content = StructuredContentRows(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if content.rows.isEmpty {
                Text("No structured content.").foregroundStyle(.secondary)
            }
            ForEach(content.rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    if !row.label.isEmpty {
                        Text(verbatim: row.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    if !row.text.isEmpty {
                        Text(verbatim: row.text).textSelection(.enabled)
                    }
                }
                .padding(.leading, CGFloat(min(row.depth, 4)) * 8)
            }
            if content.truncated {
                Text("Some structured content is too large to display in full.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
