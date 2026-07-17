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
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    /// The webhook URL as loaded, so Remove can be offered only when one is configured.
    @State private var existingURL: String?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmRemove = false

    var body: some View {
        sheetContent
            // A save/remove in flight must not be dismissible: the mutation would
            // complete invisibly and invite a conflicting retry (#899).
            .interactiveDismissDisabled(isSaving)
            .task { await load() }
            .alert("Remove the webhook?", isPresented: $confirmRemove) {
                Button("Cancel", role: .cancel) {}
                Button("Remove Webhook", role: .destructive) { Task { await remove() } }
            } message: {
                Text("Screen will stop sending event callbacks until a new webhook is set.")
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
                // Return in the field commits the webhook, like the Save button (#469).
                // A focused TextField swallows Return, so the default-action shortcut on
                // Save alone doesn't fire while the field has focus.
                .onSubmit { if isValidHTTPS, !isSaving { Task { await save() } } }

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
            Task { await save() }
        } label: {
            if isSaving {
                ProgressView().controlSize(.small)
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

    /// Whether the trimmed URL is a syntactically valid https URL with a host.
    private var isValidHTTPS: Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed),
              parsed.scheme?.lowercased() == "https",
              let host = parsed.host, !host.isEmpty else { return false }

        return true
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let current = try await client.webhookURL()
            existingURL = current
            url = current ?? ""
        } catch {
            self.error = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await client.setWebhookURL(url.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            self.error = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func remove() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await client.deleteWebhook()
            dismiss()
        } catch {
            self.error = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("Webhook sheet") {
    // Resolve the client in its own statement so the preview expression stays
    // under the 250ms type-check budget (warnings-as-errors makes it fatal).
    let client = ScreenClient.live(apiKey: "preview")
    ScreenWebhookSheet(client: client)
}
