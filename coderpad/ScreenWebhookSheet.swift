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
    @State private var isValidHTTPS = false
    /// The in-flight save/remove, cancelled if the sheet is torn down
    /// programmatically so the mutation can't finish invisibly (#1850).
    @State private var mutationTask: Task<Void, Never>?

    var body: some View {
        sheetContent
            // A save/remove in flight must not be dismissible: the mutation would
            // complete invisibly and invite a conflicting retry (#899).
            .interactiveDismissDisabled(isSaving)
            .task { await load() }
            .onDisappear { mutationTask?.cancel() }
            .alert("Remove the webhook?", isPresented: $confirmRemove) {
                Button("Cancel", role: .cancel) {}
                Button("Remove Webhook", role: .destructive) { mutationTask = Task { await remove() } }
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
                // Return in the field commits the webhook, like the Save button (#469).
                // A focused TextField swallows Return, so the default-action shortcut on
                // Save alone doesn't fire while the field has focus.
                .onSubmit { if isValidHTTPS, !isSaving { mutationTask = Task { await save() } } }

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
            mutationTask = Task { await save() }
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

    /// Whether the trimmed URL is a plausible webhook destination: https with a
    /// public hostname, no embedded credentials (#1846), no fragment (#1847), and
    /// a bounded overall length. Loopback, mDNS-local, and IP-literal hosts are
    /// refused - a webhook saved against internal infrastructure would turn the
    /// remote Screen service into an SSRF client against it (#1848). A query is
    /// allowed (real webhook endpoints carry auth tokens there) but counts
    /// against the length bound.
    private static func validateHTTPSURL(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 2048,
              let parsed = URL(string: trimmed),
              parsed.scheme?.lowercased() == "https",
              parsed.user == nil, parsed.password == nil, parsed.fragment == nil,
              let host = parsed.host?.lowercased(), !host.isEmpty,
              host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local")
        else { return false }

        let isIPv4Literal = host.contains(".") && host.allSatisfy { $0.isNumber || $0 == "." }
        let isIPv6Literal = host.contains(":")
        return !isIPv4Literal && !isIPv6Literal
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let current = try await client.webhookURL()
            existingURL = current
            // Never clobber a draft typed while the request was in flight (#1845).
            if url.isEmpty {
                url = current ?? ""
            }
        } catch {
            self.error = Self.presentableError(error)
        }
    }

    /// Bounded so long or sensitive server diagnostics can't flood the sheet (#1849).
    private static func presentableError(_ error: any Error) -> String {
        let text = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        return String(text.prefix(300))
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await client.setWebhookURL(url.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !Task.isCancelled else { return }

            dismiss()
        } catch {
            guard !Task.isCancelled else { return }

            self.error = Self.presentableError(error)
        }
    }

    private func remove() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await client.deleteWebhook()
            guard !Task.isCancelled else { return }

            dismiss()
        } catch {
            guard !Task.isCancelled else { return }

            self.error = Self.presentableError(error)
        }
    }
}

#Preview("Webhook sheet") {
    // Resolve the client in its own statement so the preview expression stays
    // under the 250ms type-check budget (warnings-as-errors makes it fatal).
    let client = ScreenClient.live(apiKey: "preview")
    ScreenWebhookSheet(client: client)
}
