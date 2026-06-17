//
//  ScreenInviteSheet.swift
//  coderpad
//
//  Invite a candidate to a Screen campaign (#436): a form bound to ScreenInvitation,
//  POSTed via ScreenClient.sendInvitation. On success it surfaces the candidate's test
//  URL with copy/open actions and asks the caller to refresh the tests list.
//

import SwiftUI

struct ScreenInviteSheet: View {
    let client: ScreenClient
    let campaign: ScreenCampaign
    /// Called after a successful send so the tests list can refresh to show the new
    /// session.
    let onSent: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var candidateEmail = ""
    @State private var candidateName = ""
    @State private var recruiterEmail = ""
    @State private var tags = ""
    @State private var sendEmail = true
    @State private var isSending = false
    @State private var errorText: String?
    @State private var result: ScreenInvitationResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(result == nil ? "Invite Candidate" : "Invitation Sent")
                .font(.title3.bold())
            Text(campaign.name)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let result {
                sentView(result)
            } else {
                form
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                TextField("Candidate email", text: $candidateEmail, prompt: Text("candidate@example.com"))
                    .textContentType(.emailAddress)
                TextField("Candidate name", text: $candidateName, prompt: Text("Optional"))
                TextField("Recruiter email", text: $recruiterEmail, prompt: Text("Result notifications (optional)"))
                    .textContentType(.emailAddress)
                TextField("Tags", text: $tags, prompt: Text("Comma-separated (optional)"))
                Toggle("Email the candidate an invitation", isOn: $sendEmail)
            }
            .formStyle(.grouped)
            .frame(height: 200)

            if let errorText {
                Label(errorText, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Send")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSending || sendDisabled)
            }
        }
    }

    private func sentView(_ result: ScreenInvitationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("The test session was created.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

            if let urlString = result.testURL, let url = URL(string: urlString) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Candidate link")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(urlString)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                    HStack {
                        Button { Clipboard.copy(urlString) } label: {
                            Label("Copy Link", systemImage: "doc.on.doc")
                        }
                        Link(destination: url) {
                            Label("Open Link", systemImage: "arrow.up.right.square")
                        }
                    }
                }
            } else {
                Text("No candidate link was returned — the candidate was emailed their invitation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Done") {
                    onSent()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// When emailing the candidate, an address is required; without the email toggle the
    /// API can create a manual (recruiter-shared) test, so an address is optional.
    private var sendDisabled: Bool {
        sendEmail && candidateEmail.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        let invitation = ScreenInvitation(
            candidateEmail: trimmedOrNil(candidateEmail),
            candidateName: trimmedOrNil(candidateName),
            recruiterEmail: trimmedOrNil(recruiterEmail),
            tags: trimmedOrNil(tags),
            sendInvitationEmail: sendEmail
        )
        do {
            result = try await client.sendInvitation(campaignID: campaign.id, invitation)
            errorText = nil
        } catch {
            errorText = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview("Invite form") {
    ScreenInviteSheet(
        client: .live(apiKey: "preview"),
        campaign: ScreenCampaign(id: 1, name: "Backend Engineer"),
        onSent: {}
    )
}
