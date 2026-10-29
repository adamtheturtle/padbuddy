import SwiftUI

@Observable
final class InterviewKeyOwnerModel {
    private(set) var user: InterviewUser?
    private(set) var identity: ClientTaskIdentity?
    private(set) var error: String?
    private(set) var loading = false
    private var generation = 0

    func load(client: CoderPadClient,
              fetch: ((CoderPadClient) async throws -> InterviewUser)? = nil) async {
        generation += 1
        let claim = generation
        identity = client.taskIdentity
        user = nil
        error = nil
        loading = true
        defer {
            if generation == claim {
                loading = false
            }
        }
        do {
            let result: InterviewUser = if let fetch {
                try await fetch(client)
            } else {
                try await client.getUser()
            }
            guard generation == claim, !Task.isCancelled else { return }

            user = result
        } catch is CancellationError {
            return
        } catch {
            guard generation == claim, !Task.isCancelled else { return }

            self.error = error.localizedDescription
        }
    }
}

struct InterviewKeyOwnerView: View {
    let client: CoderPadClient
    @State private var model = InterviewKeyOwnerModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.identity == client.taskIdentity, let user = model.user {
                InterviewKeyOwnerDetails(user: user)
            } else if model.identity == client.taskIdentity, let error = model.error {
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button("Retry") { Task { await model.load(client: client) } }
            } else if model.loading || model.identity != client.taskIdentity {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: client.taskIdentity) { await model.load(client: client) }
    }
}

struct InterviewKeyOwnerDetails: View {
    let user: InterviewUser

    private var displayName: String {
        let name = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? String(localized: "Name unavailable") : String(name.prefix(256))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: displayName)
                .textSelection(.enabled)
            LabeledContent("Pad creation") {
                Text(user.allowPadCreation ? "Allowed" : "Not allowed")
            }
            if !user.analyticsID.isEmpty {
                LabeledContent("Anonymous identifier") {
                    Text(verbatim: user.analyticsID).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            Text("CoderPad does not return this user's email or organization role. Choose your email below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
