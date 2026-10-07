import SwiftUI

struct ScreenAIConversationsSection: View {
    let client: ScreenClient
    let session: ScreenTestSession
    @State private var selected: UUID?

    private var projects: [ScreenDetailedQuestion] {
        session.detailedQuestions.filter { $0.type == "PROJECT" }
    }

    private var current: UUID? {
        selected.flatMap { id in projects.contains { $0.id == id } ? id : nil } ?? projects.first?.id
    }

    var body: some View {
        DetailSection(title: "Screen AI Assist Conversations", systemImage: "bubble.left.and.bubble.right") {
            VStack(alignment: .leading, spacing: 12) {
                if !projects.isEmpty {
                    Picker("Project question", selection: Binding(get: { current }, set: { selected = $0 })) {
                        ForEach(projects) { question in
                            Text(verbatim: question.title ?? question.id.uuidString).tag(Optional(question.id))
                        }
                    }
                }
                if let questionID = current {
                    Text(verbatim: questionID.uuidString).font(.caption).textSelection(.enabled)
                    ScreenAIConversationsView(client: client, identity: ScreenAIConversationIdentity(
                        clientIdentity: client.taskIdentity, testID: session.id, questionID: questionID
                    ))
                } else {
                    Text("No UUID project question results are available for this session.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ScreenAIConversationsView: View {
    let client: ScreenClient
    let identity: ScreenAIConversationIdentity
    @State private var model = ScreenAIConversationModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("Refresh AI Assist Conversations", systemImage: "arrow.clockwise") {
                Task { await model.load(client: client, identity: identity) }
            }.disabled(model.loading)
            if model.identity == identity {
                if model.loading {
                    ProgressView("Loading AI Assist conversations…")
                } else if let conversations = model.conversations {
                    ScreenAIConversationContent(conversations: conversations)
                } else if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text("AI Assist conversations are available after completion or while awaiting manual review.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { Task { await model.load(client: client, identity: identity) } }
                }
            }
        }
        .task(id: identity) { await model.load(client: client, identity: identity) }
    }
}

struct ScreenAIConversationContent: View {
    let conversations: [ScreenAIConversation]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if conversations.isEmpty {
                Text("No AI Assist conversations were returned for this project.").foregroundStyle(.secondary)
            }
            ForEach(conversations.indices.prefix(200), id: \.self) { index in
                let conversation = conversations[index]
                DisclosureGroup {
                    Text(verbatim: conversation.id).font(.caption).textSelection(.enabled)
                    if let time = conversation.creationTime {
                        Text(verbatim: time).font(.caption).textSelection(.enabled)
                    }
                    if conversation.messages.isEmpty {
                        Text("This conversation has no messages.").foregroundStyle(.secondary)
                    }
                    ForEach(conversation.messages.indices.prefix(1000), id: \.self) { messageIndex in
                        ScreenAIMessageView(message: conversation.messages[messageIndex])
                    }
                    if conversation.messages.count > 1000 {
                        Text("Only the first 1000 messages are shown.")
                    }
                } label: { Text(verbatim: conversation.subject ?? conversation.id) }
            }
            if conversations.count > 200 {
                Text("Only the first 200 conversations are shown.")
            }
        }
    }
}

struct ScreenAIMessageView: View {
    let message: ScreenAIMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(message.role == .user ? LocalizedStringKey("Candidate") : LocalizedStringKey("AI Assist"))
                    .font(.headline)
                Spacer()
                if let time = message.creationTime {
                    Text(verbatim: time).font(.caption).textSelection(.enabled)
                }
            }
            Text(verbatim: message.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let items = message.outputItems {
                if items.isEmpty {
                    Text("This message has an empty output list.").foregroundStyle(.secondary)
                } else {
                    StructuredContentView(.array(items))
                    DisclosureGroup("Original Structured Output") { ScreenAIOriginalOutputView(items: items) }
                }
            } else {
                Text("Message output was not provided.").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}
