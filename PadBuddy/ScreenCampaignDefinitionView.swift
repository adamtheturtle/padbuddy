import SwiftUI

struct ScreenCampaignDefinitionIdentity: Hashable {
    let accountID: UUID
    let clientIdentity: ClientTaskIdentity
    let campaignID: Int
}

@Observable
final class ScreenCampaignDefinitionModel {
    private(set) var details: ScreenCampaignDetails?
    private(set) var identity: ScreenCampaignDefinitionIdentity?
    private(set) var error: String?
    private(set) var loading = false
    private var generation = 0

    func load(client: ScreenClient, identity: ScreenCampaignDefinitionIdentity,
              fetch: ((Int) async throws -> ScreenCampaignDetails)? = nil) async {
        guard identity.clientIdentity == client.taskIdentity else { return }

        generation += 1
        let claim = generation
        self.identity = identity
        details = nil
        error = nil
        loading = true
        defer {
            if claim == generation {
                loading = false
            }
        }
        do {
            let result: ScreenCampaignDetails = if let fetch {
                try await fetch(identity.campaignID)
            } else {
                try await client.getCampaign(id: identity.campaignID)
            }
            guard claim == generation, !Task.isCancelled else { return }
            guard result.id == identity.campaignID else {
                throw CoderPadError.decode(String(
                    localized: "The campaign response did not match the requested campaign."
                ))
            }

            details = result
        } catch is CancellationError {
            return
        } catch {
            guard claim == generation, !Task.isCancelled else { return }

            self.error = error.localizedDescription
        }
    }
}

struct ScreenCampaignDefinitionView: View {
    let client: ScreenClient
    let accountID: UUID
    let campaignID: Int
    @State private var model = ScreenCampaignDefinitionModel()
    @Environment(\.dismiss) private var dismiss

    private var identity: ScreenCampaignDefinitionIdentity {
        .init(accountID: accountID, clientIdentity: client.taskIdentity, campaignID: campaignID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.identity == identity, let details = model.details {
                    ScreenCampaignDefinitionContent(details: details, client: client, accountID: accountID)
                } else if model.identity == identity, let error = model.error {
                    VStack(spacing: 12) {
                        Text(error).foregroundStyle(.secondary)
                        Button("Retry") { Task { await reload() } }
                    }
                    .padding()
                } else {
                    ProgressView("Loading campaign details…")
                }
            }
            .navigationTitle("Campaign Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .automatic) {
                    Button("Reload", systemImage: "arrow.clockwise") { Task { await reload() } }
                        .disabled(model.loading)
                }
            }
        }
        .frame(minWidth: 340, minHeight: 480)
        .task(id: identity) { await reload() }
    }

    private func reload() async {
        await model.load(client: client, identity: identity)
    }
}

struct ScreenCampaignDefinitionContent: View {
    let details: ScreenCampaignDetails
    let client: ScreenClient
    let accountID: UUID

    var body: some View {
        Form {
            Section {
                Text(verbatim: details.name).font(.headline).textSelection(.enabled)
                LabeledContent("Campaign ID", value: String(details.id))
                if let teamID = details.teamID {
                    LabeledContent("Team ID") { Text(verbatim: teamID.uuidString).textSelection(.enabled) }
                }
            }
            Section("Questions") {
                ForEach(details.questions.indices, id: \.self) { index in
                    switch details.questions[index] {
                    case let .question(id):
                        NavigationLink {
                            ScreenBankQuestionDetailView(client: client,
                                                         bankIdentity: .init(accountID: accountID,
                                                                             clientIdentity: client.taskIdentity),
                                                         questionID: id)
                        } label: {
                            VStack(alignment: .leading) {
                                Text("Question \(index + 1)")
                                Text(verbatim: id.uuidString).font(.caption).foregroundStyle(.secondary)
                            }
                        }

                    case let .randomQuestionSet(configuration):
                        DisclosureGroup("Random question set \(index + 1)") {
                            ScreenCampaignRandomSelectionDetails(configuration: configuration)
                        }
                    }
                }
                if details.questions.isEmpty {
                    Text("No questions returned.").foregroundStyle(.secondary)
                }
            }
            if let settings = details.settings {
                ScreenCampaignDefinitionSettings(settings: settings)
            }
        }
        .formStyle(.grouped)
    }
}
