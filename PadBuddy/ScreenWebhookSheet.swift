//
//  ScreenWebhookSheet.swift
//  coderpad
//
//  View and configure the org's CoderPad Screen webhook (#438): the URL Screen POSTs
//  test-session events to. Loads the current value, lets the user set a valid https
//  URL or remove it (with confirmation).
//

import SwiftUI

struct ScreenWebhookSheet: View {
    let client: ScreenClient
    let accountID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var draftRevision = 0
    /// The webhook URL as loaded, so Remove can be offered only when one is configured.
    @State private var existingURL: String?
    @State private var isLoading = true
    @State private var loadGeneration = 0
    @State private var isSaving = false
    @State private var savingLabel = String(localized: "Testing delivery…")
    @State private var error: String?
    @State private var confirmRemove = false
    @State private var isValidHTTPS = false
    /// The in-flight save/remove. Programmatic teardown may cancel its reversible
    /// preflight, but never a Screen mutation that has already been issued.
    @State private var mutationTask: Task<Void, Never>?
    /// Once the Screen write has been issued, cancellation cannot roll it back.
    /// Let that request settle even if programmatic teardown removes the sheet.
    @State private var mutationWasIssued = false

    var body: some View {
        sheetContent
            // A save/remove in flight must not be dismissible: the mutation would
            // complete invisibly and invite a conflicting retry (#899).
            .interactiveDismissDisabled(isSaving)
            .task(id: context) { await load() }
            .onDisappear {
                if ScreenWebhookMutationLifetime.shouldCancelOnDisappear(
                    mutationWasIssued: mutationWasIssued
                ) {
                    mutationTask?.cancel()
                }
            }
            .alert("Remove the webhook?", isPresented: $confirmRemove) {
                Button("Cancel", role: .cancel) {}
                Button("Remove Webhook", role: .destructive) { startMutation { await remove() } }
            } message: {
                // Name the endpoint being removed, so the confirmation is about a
                // URL the user actually reviewed (#1851).
                Text("""
                "\(existingURL ?? "")" will be removed. Screen will stop sending event \
                callbacks until a new webhook is set.
                """)
            }
    }

    @ViewBuilder
    private var sheetContent: some View {
        #if os(iOS)
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    description
                    loadingOrContent
                }
                .padding()
                .navigationTitle("Screen Webhook")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { sheetToolbar }
            }
        #else
            VStack(alignment: .leading, spacing: 16) {
                Text("Screen Webhook")
                    .font(.title3.bold())
                description
                loadingOrContent
            }
            .padding(20)
            .frame(width: 440)
        #endif
    }

    private var description: some View {
        Text("CoderPad Screen sends test-session events (started, completed, …) to this URL.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var loadingOrContent: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Webhook URL", text: $url, prompt: Text("https://example.com/screen-hook"))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityLabel("Webhook URL")
                .onChange(of: url, initial: true) { _, newValue in
                    isValidHTTPS = Self.validateHTTPSURL(newValue)
                }
                .onChange(of: url) { _, _ in draftRevision &+= 1 }
                // Return in the field commits the webhook, like the Save button (#469).
                // A focused TextField swallows Return, so the default-action shortcut on
                // Save alone doesn't fire while the field has focus.
                .onSubmit {
                    if isValidHTTPS, !isSaving {
                        startMutation { await save() }
                    }
                }

            if let error {
                Label(error, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if !url.isEmpty, !isValidHTTPS {
                Label("Enter a valid https:// URL.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                if existingURL != nil {
                    Button("Remove", role: .destructive) { confirmRemove = true }
                        .disabled(isSaving)
                }
                #if os(macOS)
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isSaving)
                    saveButton
                #endif
            }
        }
    }

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) { dismiss() }
                .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            saveButton
        }
    }

    private var saveButton: some View {
        Button {
            startMutation { await save() }
        } label: {
            if isSaving {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(savingLabel)
                }
            } else {
                Text("Save")
            }
        }
        #if os(macOS)
        .buttonStyle(.borderedProminent)
        #endif
        .keyboardShortcut(.defaultAction)
        .disabled(isSaving || !isValidHTTPS)
    }

    private static func validateHTTPSURL(_ url: String) -> Bool {
        ScreenClient.normalizedWebhookURL(url) != nil
    }

    private var context: ScreenWebhookContext {
        ScreenWebhookContext(accountID: accountID, clientIdentity: client.taskIdentity)
    }

    private var isCurrentContext: Bool {
        guard let account = AccountsStore.shared.accounts.first(where: { $0.id == accountID }),
              let current = account.makeScreenClient() else { return false }

        return context.matches(accountID: account.id, clientIdentity: current.taskIdentity)
    }

    private func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        let requestedContext = context
        let requestedDraft = (revision: draftRevision, value: url, baseline: existingURL ?? "")
        guard isCurrentContext else {
            dismiss()
            return
        }

        isLoading = true
        defer {
            if ScreenWebhookLoadIdentity.isCurrent(
                generation,
                currentGeneration: loadGeneration,
                requestedContext: requestedContext,
                currentContext: context
            ) {
                isLoading = false
            }
        }
        do {
            let current = try await client.webhookURL()
            guard !Task.isCancelled, isCurrentContext,
                  ScreenWebhookLoadIdentity.isCurrent(
                      generation,
                      currentGeneration: loadGeneration,
                      requestedContext: requestedContext,
                      currentContext: context
                  ) else { return }

            error = nil
            existingURL = current
            // Compare revisions rather than emptiness: clearing the field is a real
            // in-flight edit and must not be repopulated by this response (#5172).
            if ScreenWebhookDraftIdentity.canApply(
                loadRevision: requestedDraft.revision,
                currentRevision: draftRevision,
                draftAtLoad: requestedDraft.value, loadedBaseline: requestedDraft.baseline
            ) {
                url = current ?? ""
            }
        } catch {
            guard !Task.isCancelled, isCurrentContext,
                  ScreenWebhookLoadIdentity.isCurrent(
                      generation,
                      currentGeneration: loadGeneration,
                      requestedContext: requestedContext,
                      currentContext: context
                  ) else { return }

            self.error = Self.presentableError(error)
        }
    }

    /// Bounded so long or sensitive server diagnostics can't flood the sheet (#1849).
    private static func presentableError(_ error: any Error) -> String {
        let text = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        return String(text.prefix(300))
    }

    /// Starts a mutation, claiming it synchronously so two Return presses — or Return
    /// plus a click — cannot launch two concurrent `save()` calls, which would send two
    /// delivery-test POSTs and two `setWebhookURL` writes. `isSaving` used to be set only
    /// once the task body began running, leaving the button enabled in between (#4751).
    /// Replacing `mutationTask` also used to abandon the task it replaced, so
    /// `onDisappear` cancelled only the last one.
    private func startMutation(_ operation: @escaping @MainActor () async -> Void) {
        guard !isSaving else { return }

        isSaving = true
        mutationWasIssued = false
        mutationTask?.cancel()
        mutationTask = Task {
            await operation()
            isSaving = false
            mutationWasIssued = false
        }
    }

    private func save() async {
        guard isCurrentContext else {
            dismiss()
            return
        }

        do {
            let proposedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            savingLabel = String(localized: "Testing delivery…")
            try await ScreenWebhookDeliveryTest.send(to: proposedURL)
            guard !Task.isCancelled, isCurrentContext else { return }

            savingLabel = String(localized: "Saving…")
            mutationWasIssued = true
            try await client.setWebhookURL(proposedURL)
            guard isCurrentContext else { return }

            dismiss()
        } catch {
            guard !Task.isCancelled || mutationWasIssued, isCurrentContext else { return }

            self.error = Self.presentableError(error)
        }
    }

    private func remove() async {
        guard isCurrentContext else {
            dismiss()
            return
        }

        do {
            mutationWasIssued = true
            try await client.deleteWebhook()
            guard isCurrentContext else { return }

            dismiss()
        } catch {
            guard !Task.isCancelled || mutationWasIssued, isCurrentContext else { return }

            self.error = Self.presentableError(error)
        }
    }
}

#Preview("Webhook sheet") {
    // Resolve the client in its own statement so the preview expression stays
    // under the 250ms type-check budget (warnings-as-errors makes it fatal).
    let client = ScreenClient.live(apiKey: "preview")
    ScreenWebhookSheet(client: client, accountID: UUID())
}
