//
//  ScreenInviteSheet.swift
//  coderpad
//
//  Invite a candidate to a Screen campaign (#436): a form bound to ScreenInvitation,
//  POSTed via ScreenClient.sendInvitation. On success it surfaces the candidate's test
//  URL with copy/open actions and asks the caller to refresh the tests list.
//

import SwiftUI

struct ScreenInviteValidationState: Equatable {
    var candidateEmailIsEmpty = true
    var hint: String?
}

struct ScreenInviteSheet: View {
    let client: ScreenClient
    let campaign: ScreenCampaign
    /// Called after a successful send so the tests list can refresh to show the new
    /// session.
    let onSent: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var candidateEmail = ""
    @State private var candidateName = ""
    @State private var recruiterEmail = ""
    @State private var tags = ""
    @State private var sendEmail = true
    @State private var isSending = false
    @State private var errorText: String?
    @State private var result: ScreenInvitationResult?
    @State private var validationState = ScreenInviteValidationState()
    var body: some View {
        sheetBody
            // A send in flight must not be dismissible: the invitation could succeed
            // after the sheet (its only success UI and refresh path) is gone, inviting
            // a duplicate send (#865).
            .interactiveDismissDisabled(isSending)
            .onChange(of: candidateEmail, initial: true) { _, _ in refreshValidationState() }
            .onChange(of: recruiterEmail) { _, _ in refreshValidationState() }
    }

    @ViewBuilder
    private var sheetBody: some View {
        #if os(iOS)
            NavigationStack {
                sheetContent
                    .padding()
                    .navigationTitle(result == nil ? "Invite Candidate" : "Invitation Sent")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { sheetToolbar }
            }
        #else
            VStack(alignment: .leading, spacing: 16) {
                Text(result == nil ? "Invite Candidate" : "Invitation Sent")
                    .font(.title3.bold())
                sheetContent
            }
            .padding(20)
            .frame(width: 420)
        #endif
    }

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(campaign.name)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let result {
                sentView(result)
            } else {
                form
            }
        }
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
            } else if let hint = validationState.hint {
                Label(hint, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            #if os(macOS)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isSending)
                    sendButton
                }
            #endif
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
                        // An explicit openURL Button, not a bare Link: external Link
                        // controls can silently no-op on iPad (#552, #730). Offered
                        // only for https - the URL is server-provided data, and a
                        // compromised or spoofed response must not be able to launch
                        // arbitrary scheme handlers from a single click (#1839).
                        if url.scheme?.lowercased() == "https" {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open Link", systemImage: "arrow.up.right.square")
                            }
                        }
                    }
                }
            } else {
                Text("No candidate link was returned. The candidate was emailed their invitation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            #if os(macOS)
                HStack {
                    Spacer()
                    doneButton
                }
            #endif
        }
    }

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        if result == nil {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
                    .disabled(isSending)
            }
            ToolbarItem(placement: .confirmationAction) {
                sendButton
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                doneButton
            }
        }
    }

    private var sendButton: some View {
        Button {
            // Invitation creation cannot be recalled once issued. Keep this
            // unstructured task alive across programmatic sheet teardown so its
            // result and parent reconciliation are not silently discarded (#5201).
            Task { await send() }
        } label: {
            if isSending {
                ProgressView().controlSize(.small)
            } else {
                Text("Send")
            }
        }
        #if os(macOS)
        .buttonStyle(.borderedProminent)
        #endif
        .keyboardShortcut(.defaultAction)
        .disabled(isSending || sendDisabled)
    }

    private var doneButton: some View {
        Button("Done") {
            dismiss()
        }
        #if os(macOS)
        .buttonStyle(.borderedProminent)
        #endif
        .keyboardShortcut(.defaultAction)
    }

    /// When emailing the candidate, a plausible address is required; without the email
    /// toggle the API can create a manual (recruiter-shared) test, so the candidate
    /// address stays optional - but any address actually entered must be plausible,
    /// whichever mode is active, and that includes the recruiter notification address
    /// (#1840, #1841). Trims newlines too, so a pasted line break can't enable Send
    /// while the request normalizes the same value away (#874), and rejects clearly
    /// malformed addresses instead of turning them into failed API requests (#920).
    private var sendDisabled: Bool {
        validationState.hint != nil || (sendEmail && validationState.candidateEmailIsEmpty)
    }

    /// The first field-level problem to surface under the form, nil when the form is
    /// sendable (or still empty).
    private static func makeValidationState(candidateEmail: String,
                                            recruiterEmail: String) -> ScreenInviteValidationState {
        let candidate = candidateEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty, !Self.isPlausibleEmail(candidate) {
            return ScreenInviteValidationState(
                candidateEmailIsEmpty: false,
                hint: String(localized: "Enter a valid candidate email address.")
            )
        }
        let recruiter = recruiterEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !recruiter.isEmpty, !Self.isPlausibleEmail(recruiter) {
            return ScreenInviteValidationState(
                candidateEmailIsEmpty: candidate.isEmpty,
                hint: String(localized: "Enter a valid recruiter email address.")
            )
        }
        return ScreenInviteValidationState(candidateEmailIsEmpty: candidate.isEmpty)
    }

    private func refreshValidationState() {
        validationState = Self.makeValidationState(candidateEmail: candidateEmail, recruiterEmail: recruiterEmail)
    }

    /// A light plausibility check, not full RFC validation: one @, a non-empty local
    /// part, a dotted domain, and no whitespace. Internal for tests.
    static func isPlausibleEmail(_ value: String) -> Bool {
        EmailValidation.isPlausibleAddress(value)
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        // Addresses go out normalized (trimmed, domain lowercased) so the same
        // mailbox always reaches the API in one canonical spelling (#1941).
        let invitation = ScreenInvitation(
            candidateEmail: trimmedOrNil(EmailValidation.normalized(candidateEmail)),
            candidateName: trimmedOrNil(candidateName),
            recruiterEmail: trimmedOrNil(EmailValidation.normalized(recruiterEmail)),
            tags: trimmedOrNil(tags, limit: 500),
            sendInvitationEmail: sendEmail
        )
        do {
            let sent = try await client.sendInvitation(campaignID: campaign.id, invitation)

            result = sent
            errorText = nil
            // Reconcile the parent list the moment the server mutation succeeds, not
            // from the Done button - the sheet may never reach it (#865).
            onSent()
        } catch {
            errorText = String(((error as? CoderPadError)?.errorDescription
                    ?? error.localizedDescription).prefix(300))
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trimmed, nil when empty, and length-capped: the fields are free text, and an
    /// accidental mega-paste shouldn't become an oversized API payload (#1842). 254
    /// is the RFC address ceiling; tags get more room.
    private func trimmedOrNil(_ value: String, limit: Int = 254) -> String? {
        let trimmed = trimmed(value)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(limit))
    }
}

#Preview("Invite form") {
    // The memberwise init validates its id and name, so the sample is optional.
    let campaign = try? ScreenCampaign(id: 1, name: "Backend Engineer")
    if let campaign {
        ScreenInviteSheet(client: .live(apiKey: "preview"), campaign: campaign, onSent: {})
    }
}
