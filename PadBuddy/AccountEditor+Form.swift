//
//  AccountEditor+Form.swift
//  coderpad
//
//  The Mail-style stack of credential/appearance/email/Screen field rows, split out
//  of `AccountEditor.body` so each type-checks under the Release build's 250ms
//  type-check-timing budget (warnings-as-errors). (#427)
//

import SwiftUI

extension AccountEditor {
    var formFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldRow("API Key") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Group {
                            if revealKey {
                                TextField("", text: $draft.apiKey, prompt: Text("Paste CoderPad API key"))
                            } else {
                                SecureField("", text: $draft.apiKey, prompt: Text("Paste CoderPad API key"))
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        // The visible "API Key" label lives in the separate `fieldRow`
                        // column and isn't programmatically tied to the field, so name
                        // it explicitly or VoiceOver announces an unlabeled text field.
                        .accessibilityLabel("API Key")
                        Button {
                            toggleReveal()
                        } label: {
                            Image(systemName: revealKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(revealKey ? "Hide the API key." : "Show the API key.")
                        .accessibilityLabel(revealKey ? "Hide API key" : "Show API key")
                    }
                    GetAPIKeyLink()
                        .font(.callout)
                    Text("API integration requires CoderPad Enterprise.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            fieldRow("Server URL") {
                VStack(alignment: .leading, spacing: 5) {
                    TextField("", text: baseURLBinding,
                              prompt: Text(CoderPadClient.defaultBaseURL.absoluteString))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Server URL")
                        .help("""
                        Override only for self-hosted or regional CoderPad deployments. \
                        Leave blank to use the default.
                        """)
                    if serverURLChanged {
                        Label(
                            "Changing the server may connect this key to a different organization. "
                                + "Validate the API key before leaving to replace the saved endpoint.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
            }
            // A saved account always offers its Description so it can be renamed
            // without re-validating the key; a new account auto-fills it from the
            // organization once the key validates.
            if isEditing || isValidated {
                fieldRow("Description") {
                    TextField("", text: $draft.name,
                              prompt: Text("Auto-filled from your organization"))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Description")
                }
                fieldRow("Icon", alignment: .center) {
                    HStack(alignment: .center, spacing: 8) {
                        // Live preview of how the avatar will look elsewhere.
                        AvatarCircle(account: draft, diameter: 30)
                        AccountSymbolPicker(selection: $draft.iconSymbol)
                    }
                }
                fieldRow("Color", alignment: .center) {
                    AccountTintPicker(selection: $draft.tintHex,
                                      defaultColor: draft.defaultTint)
                }
            }
            // Picking a *different* member needs the validated org's member list,
            // but a saved account already carries its email, so show the row when
            // editing too: it surfaces the existing email automatically (via
            // `emailOptions`) without forcing a re-validation just to see it.
            if isValidated || isEditing {
                fieldRow("Your Email") {
                    VStack(alignment: .leading, spacing: 4) {
                        OrgMemberPicker(
                            selection: $draft.userEmail,
                            users: orgUsers,
                            isLoading: isLoadingMembers,
                            loadError: memberLoadError,
                            // Fetch the org's member list only when the user opens the
                            // picker to choose a different member, rather than eagerly on
                            // appear — eager loading made the row flash between the saved
                            // email and the resolved name on every open (#497).
                            onOpen: { startLoadingOrgMembers() }
                        )
                        .help("""
                        Identifies you for the My Pads and My Questions filters and the menu bar. \
                        Required to save.
                        """)
                        if !hasEmail {
                            Text("Required: pick which member you are to finish.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            // The optional CoderPad Screen credentials (a separate product), shown
            // once the account exists. Additive — they never gate Save.
            if isEditing || isValidated {
                screenSection
            }
            #if os(iOS)
                if isEditing {
                    watchProvisioningSection
                }
            #endif
        }
    }

    private var serverURLChanged: Bool {
        guard isEditing else { return false }

        let draftURL = (draft.baseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let savedURL = (persistedDraft.baseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return draftURL != savedURL
    }

    #if os(iOS)
        private var watchProvisioningSection: some View {
            fieldRow("Apple Watch") {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        watchProvisioning.provision(account: persistedDraft)
                    } label: {
                        Label("Connect Apple Watch", systemImage: "applewatch")
                    }
                    .disabled(!canSendAccountToWatch)

                    if let message = watchProvisioningMessage {
                        Label(message, systemImage: watchProvisioningMessageSymbol)
                            .font(.caption)
                            .foregroundStyle(watchProvisioningMessageIsProblem ? Color.secondary : Color.green)
                    }
                    if watchProvisioning.activationError != nil {
                        Button("Retry Apple Watch Connection") {
                            watchProvisioning.retryActivation()
                        }
                        .font(.caption)
                    }
                }
            }
        }

        private var canSendAccountToWatch: Bool {
            !hasUnsavedLiveChanges
                && TVProvisioningRequest.payload(for: persistedDraft) != nil
                && watchProvisioning.canProvision
        }

        private var watchProvisioningMessage: String? {
            if hasUnsavedLiveChanges {
                return String(localized: "Save or validate the API key before connecting Apple Watch.")
            }
            if TVProvisioningRequest.payload(for: persistedDraft) == nil {
                return String(localized: "This account cannot be sent to Apple Watch.")
            }
            return accountWatchProvisioningStatus.message ?? watchProvisioning.availabilityMessage
        }

        private var watchProvisioningMessageSymbol: String {
            if hasUnsavedLiveChanges || TVProvisioningRequest.payload(for: persistedDraft) == nil {
                return "exclamationmark.triangle.fill"
            }
            return accountWatchProvisioningStatus.message == nil
                ? "info.circle"
                : accountWatchProvisioningStatus.systemImage
        }

        private var watchProvisioningMessageIsProblem: Bool {
            hasUnsavedLiveChanges
                || TVProvisioningRequest.payload(for: persistedDraft) == nil
                || watchProvisioning.availabilityMessage != nil
        }

        private var accountWatchProvisioningStatus: WatchProvisioningStatus {
            watchProvisioning.status(for: persistedDraft.id)
        }
    #endif
}
