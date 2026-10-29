import SwiftUI

/// Files are opened individually so large lockfiles do not all render at once.
struct QuestionProjectStarterFiles: View {
    let files: [QuestionStarterFile]
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Starter Files", systemImage: "doc.on.doc")
            Text("These files customize the project template. Unchanged template files may not be included.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(files.indices, id: \.self) { index in
                QuestionProjectStarterFile(file: files[index], language: language)
                if index != files.count - 1 {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QuestionProjectStarterFile: View {
    let file: QuestionStarterFile
    let language: String?
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false

    var body: some View {
        if file.deleted == true {
            fileLabel
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                if isExpanded {
                    contents
                }
            } label: {
                fileLabel
            }
        }
    }

    private var fileLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: file.path)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            if file.hidden == true {
                Chip(text: String(localized: "Hidden"), systemImage: "eye.slash", tint: .gray)
            }
            if file.deleted == true {
                Label("Removed from template", systemImage: "minus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var contents: some View {
        if let code = file.contents {
            if code.isEmpty {
                Text("Empty file").foregroundStyle(.secondary)
            } else {
                HighlightedCode(contents: code,
                                language: CodeFile.language(forPath: file.path, fallback: language),
                                dark: colorScheme == .dark, usesCodeWell: true)
            }
        } else {
            Text("File contents unavailable").foregroundStyle(.secondary)
        }
    }
}
