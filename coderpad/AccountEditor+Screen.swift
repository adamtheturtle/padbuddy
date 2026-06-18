//
//  AccountEditor+Screen.swift
//  coderpad
//
//  The optional CoderPad Screen credentials section of the account editor. Screen is
//  a separate product from the Interview API; these credentials are additive and never
//  gate Save.
//

import SwiftUI

extension AccountEditor {
    /// Whether the draft carries a non-empty Screen API key.
    var hasScreenKey: Bool {
        !((draft.screenApiKey ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// Bridges the optional `screenApiKey` to the text field: an empty field means
    /// "no Screen", which we store as `nil` rather than an empty string so
    /// `makeScreenClient()` returns nil.
    var screenApiKeyBinding: Binding<String> {
        Binding(
            get: { draft.screenApiKey ?? "" },
            set: { newValue in
                draft.screenApiKey =
                    newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newValue
            }
        )
    }

    var screenValidateDisabled: Bool {
        !hasScreenKey || screenValidation == .validating
    }

    /// The optional CoderPad Screen credentials block: an API key (with the same reveal
    /// treatment as the Interview key), a region picker shown once a key is entered, and
    /// a non-blocking Validate affordance. Presented as a first-class, separated section
    /// (a divider + an icon/title/subtitle header) rather than a bare inline disclosure,
    /// so it reads as an intentional part of the account rather than bolted on (#441). It
    /// stays collapsible so it keeps out of the way for accounts that don't use Screen.
    var screenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.vertical, 4)
            DisclosureGroup(isExpanded: $screenExpanded) {
                screenFields
                    .padding(.top, 8)
            } label: {
                screenSectionHeader
            }
        }
    }

    /// The section header for the Screen block: the same `person.crop.rectangle.stack`
    /// glyph the Screen section uses throughout, a title, and a one-line subtitle that
    /// explains it's an optional, separate product — so the collapsed row reads as a
    /// real section header, not an afterthought.
    private var screenSectionHeader: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text("CoderPad Screen")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Optional — connect this account to Screen assessments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "person.crop.rectangle.stack")
                .foregroundStyle(.tint)
        }
        .help("Optional: connect this account to CoderPad Screen (assessments).")
    }

    /// The Screen credential fields shown when the section is expanded.
    private var screenFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldRow("Screen Key") {
                HStack(spacing: 6) {
                    Group {
                        if revealScreenKey {
                            TextField("", text: screenApiKeyBinding,
                                      prompt: Text("Paste your Screen API key"))
                        } else {
                            SecureField("", text: screenApiKeyBinding,
                                        prompt: Text("Paste your Screen API key"))
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .accessibilityLabel("Screen API Key")
                    Button {
                        toggleScreenReveal()
                    } label: {
                        Image(systemName: revealScreenKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(revealScreenKey ? "Hide the Screen API key." : "Show the Screen API key.")
                    .accessibilityLabel(revealScreenKey ? "Hide Screen API key" : "Show Screen API key")
                }
            }
            // The region only matters once there's a key to point at a server.
            if hasScreenKey {
                fieldRow("Region") {
                    Picker("", selection: $draft.screenRegion) {
                        Text("United States").tag(ScreenRegion.unitedStates)
                        Text("Europe").tag(ScreenRegion.europe)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("Which CoderPad Screen region your key belongs to.")
                }
                fieldRow("") { screenValidateButton }
                screenValidationBanner
            }
        }
    }

    var screenValidateButton: some View {
        Button("Validate Screen Key") { Task { await validateScreen() } }
            .buttonStyle(.bordered)
            .disabled(screenValidateDisabled)
    }

    @ViewBuilder
    var screenValidationBanner: some View {
        switch screenValidation {
        case .idle:
            EmptyView()

        case .validating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Validating Screen key…").foregroundStyle(.secondary)
            }
            .font(.callout)

        case .valid:
            Label("Screen key works.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)

        case let .invalid(message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red).font(.callout)
        }
    }

    /// Optional, non-blocking check that the Screen key reaches the Screen API. Mirrors
    /// `validate()` but never affects Save — Screen is additive to the Interview account.
    /// Uses the draft's current key + region, so it works before the account is saved.
    func validateScreen() async {
        let key = (draft.screenApiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        screenValidation = .validating
        do {
            let client = ScreenClient.live(apiKey: key, baseURL: draft.screenRegion.baseURL)
            _ = try await client.listCampaigns()
            screenValidation = .valid("")
        } catch {
            screenValidation = .invalid(friendlyValidationMessage(for: error))
        }
    }
}

#Preview("Account editor — Screen section") {
    AccountEditor(
        initial: Account(
            name: "Acme", apiKey: "live-key", userEmail: "me@acme.com",
            screenApiKey: "screen-key", screenRegion: .europe
        ),
        embedded: true,
        onSave: { _ in },
        onCancel: {},
        onDelete: {}
    )
    .frame(width: 460)
    .padding()
}
