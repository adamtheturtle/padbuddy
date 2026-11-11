import SwiftUI

/// Only a recognized, completely decoded file array is used as template defaults.
/// Unknown catalogue fields remain unavailable rather than being treated as an empty template.
nonisolated enum QuestionTemplateFiles {
    static func decode(_ value: JSONValue) -> [QuestionStarterFile]? {
        guard case let .object(object) = value, case let .array(files) = object["file_contents"],
              let data = try? JSONEncoder().encode(JSONValue.array(files)),
              let decoded = try? JSONDecoder().decode([QuestionStarterFile].self, from: data),
              decoded.allSatisfy({ !$0.path.isEmpty }), Set(decoded.map(\.path)).count == decoded.count
        else { return nil }

        return decoded
    }

    static func resolve(defaults: [QuestionStarterFile], overlays: [QuestionStarterFile]) -> [QuestionStarterFile] {
        var result = defaults
        for file in overlays {
            if let index = result.firstIndex(where: { $0.path == file.path }) {
                result[index] = file
            } else {
                result.append(file)
            }
        }
        return result
    }
}

nonisolated struct QuestionTemplateScope: Hashable {
    let client: ClientTaskIdentity
    let template: String?
}

@Observable
final class QuestionTemplateFilesModel {
    private(set) var scope: QuestionTemplateScope?
    private(set) var defaults: [QuestionStarterFile]?
    private(set) var loading = false
    private(set) var failed = false
    private var generation = 0

    func load(client: CoderPadClient, template: String?,
              fetch: ((CoderPadClient, String) async throws -> JSONValue)? = nil) async {
        generation += 1
        let claim = generation
        scope = QuestionTemplateScope(client: client.taskIdentity, template: template)
        defaults = nil
        failed = false
        guard let template, !template.isEmpty else {
            loading = false
            return
        }

        loading = true
        defer {
            if generation == claim {
                loading = false
            }
        }
        do {
            let payload: JSONValue = if let fetch {
                try await fetch(client, template)
            } else {
                try await client.getLanguage(template)
            }
            guard generation == claim, !Task.isCancelled else { return }

            defaults = QuestionTemplateFiles.decode(payload)
        } catch {
            guard generation == claim, !Task.isCancelled else { return }

            failed = true
        }
    }
}

struct QuestionProjectFilesView: View {
    let client: CoderPadClient
    let template: String?
    let files: [QuestionStarterFile]
    @State private var model = QuestionTemplateFilesModel()

    private var scope: QuestionTemplateScope {
        QuestionTemplateScope(client: client.taskIdentity, template: template)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let defaults = model.scope == scope ? model.defaults : nil
            QuestionProjectStarterFiles(
                files: defaults.map { QuestionTemplateFiles.resolve(defaults: $0, overlays: files) } ?? files,
                language: template, includesTemplateDefaults: defaults != nil
            )
            if model.scope != scope || model.loading {
                ProgressView("Loading template files…").controlSize(.small)
            } else if defaults == nil {
                Text("Template files unavailable. Only returned customizations are shown.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.failed {
                    Button("Retry Template Files") { Task { await model.load(client: client, template: template) } }
                }
            }
        }
        .task(id: scope) { await model.load(client: client, template: template) }
    }
}
