//
//  AccountEditor+Logic.swift
//  coderpad
//

import BuddyDesignSystem
import Foundation
import SwiftUI

extension AccountEditor {
    /// Width of the right-aligned label column, sized to hold the longest label
    /// ("Description") so every field starts at the same x — the Mail look.
    var labelColumnWidth: CGFloat {
        #if os(macOS)
            84
        #else
            // iPadOS draws the label at the larger system body size (17pt vs macOS's
            // 13pt), where "Description" overflows the 84pt column and wraps to two
            // lines (#553). Widen the column so the longest label fits on one line.
            112
        #endif
    }

    var usesCompactAccountEditorLayout: Bool {
        #if os(macOS)
            false
        #else
            horizontalSizeClass == .compact
        #endif
    }

    /// One account-editor row. Regular widths use the Mail-style right-aligned label
    /// column; compact iPhone widths stack labels over controls so fields stay inside
    /// the sheet instead of forcing the whole editor wider than the screen.
    @ViewBuilder
    func fieldRow(_ label: String,
                  alignment: VerticalAlignment = .firstTextBaseline,
                  @ViewBuilder content: () -> some View) -> some View {
        if usesCompactAccountEditorLayout {
            VStack(alignment: .leading, spacing: 4) {
                if !label.isEmpty {
                    Text(LocalizedStringKey(label))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: alignment, spacing: 10) {
                Text(LocalizedStringKey(label))
                    .lineLimit(1)
                    .frame(width: labelColumnWidth, alignment: .trailing)
                    .foregroundStyle(.secondary)
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Bridges the optional `baseURL` to the text field: an empty field means
    /// "use the default", which we store as `nil` rather than an empty string.
    var baseURLBinding: Binding<String> {
        Binding(
            get: { draft.baseURL ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.baseURL = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    var isValidated: Bool {
        if case .valid = validation { return true }
        return false
    }

    /// Whether the editor is modifying a saved account (vs. adding a new one); the
    /// Delete callback is supplied only in that case.
    var isEditing: Bool {
        onDelete != nil
    }

    /// Org member emails for the picker, including any already-saved email that the
    /// org list might not return, sorted for a stable order.
    var emailOptions: [String] {
        var emails = Set(orgUsers.map(\.email).filter { !$0.isEmpty })
        if !draft.userEmail.isEmpty { emails.insert(draft.userEmail) }
        return emails.sorted()
    }

    func emailLabel(_ email: String) -> String {
        if let name = orgUsers.first(where: { $0.email == email })?.name, !name.isEmpty {
            return "\(name) · \(email)"
        }
        return email
    }

    var validateDisabled: Bool {
        draft.apiKey.trimmingCharacters(in: .whitespaces).isEmpty || validation == .validating
    }

    @ViewBuilder
    var validateButton: some View {
        // When Save is available it owns the default action (Return); otherwise Validate
        // is the primary call to action, so only one button claims the shortcut.
        if canSave {
            Button("Validate") { Task { await validate() } }
                .buttonStyle(.glass)
                .disabled(validateDisabled)
        } else {
            Button("Validate") { Task { await validate() } }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(validateDisabled)
        }
    }

    /// Whether the draft has a non-empty user email. Required to save: the email
    /// identifies "you" for the My Pads/My Questions filters and the menu bar.
    var hasEmail: Bool {
        EmailValidation.isPlausibleAddress(draft.userEmail.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A saved account whose key and server URL are untouched can be re-saved without
    /// re-validating, so edits to the Description or email persist freely; a new account
    /// or a changed credential still requires a successful validation first. In every
    /// case a user email is required — a legacy account saved without one must be
    /// re-validated (which reveals the picker and auto-detects the email) before it
    /// can be saved again.
    var canSave: Bool {
        guard hasEmail else { return false }

        return isValidated || (isEditing && draft.apiKey == initialAPIKey && draft.baseURL == initialBaseURL)
    }

    /// Saved accounts are managed like settings: changes autosave in the embedded
    /// editor instead of waiting for an explicit Save button. Adding a new account stays
    /// modal and explicit, because it is a multi-step validation flow.
    var commitsLive: Bool {
        embedded && isEditing
    }

    /// Schedules a debounced autosave for saved-account edits. Credential changes still
    /// respect `canSave`, so a changed API key or server URL waits for validation before
    /// the stored account is updated.
    func commitLiveEdit() {
        guard commitsLive else { return }

        liveCommitTask?.cancel()
        liveCommitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }

            persistLiveEditIfPossible()
        }
    }

    /// Persists the current draft when autosave is allowed and the draft is in a valid
    /// saveable state. Called after the debounce and when the editor disappears, so a
    /// quick navigation away does not drop the latest valid edit.
    func persistLiveEditIfPossible() {
        guard commitsLive, canSave else { return }

        finalizeNameIfNeeded()
        guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        onSave(draft.normalizedForStorage)
    }

    @ViewBuilder
    var saveButton: some View {
        let save = {
            finalizeNameIfNeeded()
            onSave(draft.normalizedForStorage)
        }
        if canSave {
            Button("Save", action: save)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        } else {
            Button("Save", action: save)
                .buttonStyle(.glass)
                .disabled(true)
        }
    }

    func finalizeNameIfNeeded() {
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            if isValidated, let org = validatedOrgName {
                draft.name = org
            } else {
                draft.name = "Account"
            }
        }
    }

    var validationBanner: some View {
        // Interview-key success is signalled by enabling Save, not a banner, so the
        // success text is omitted (the shared banner renders nothing on `.valid` then).
        ValidationStatusBanner(validation, validating: "Validating API key…")
    }

    /// A non-blocking, amber note shown when the key validated against the org but
    /// lacks the scope for one or more feature endpoints.
    @ViewBuilder
    var scopeWarningBanner: some View {
        if let scopeWarning {
            Label(scopeWarning, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.callout)
        }
    }

    /// For a saved account, fetch the org's member list on demand — when the user opens
    /// the "Your Email" picker to choose a different member — so the picker offers every
    /// member without the user having to press Validate. Loading lazily (rather than
    /// eagerly on appear) keeps the row from flashing between the saved email and the
    /// resolved name each time the editor opens (#497). Uses the already-saved
    /// (known-good) credentials and touches only `orgUsers` — not the validation state —
    /// so it never flips the editor into a validated/error state behind the user's back.
    /// Silent on failure: the saved email stays selectable and Validate remains the path
    /// that surfaces a real problem.
    func loadOrgMembersForEditing() async {
        guard isEditing, !isValidated, orgUsers.isEmpty, !draft.hasMalformedBaseURLOverride else { return }

        isLoadingMembers = true
        defer { isLoadingMembers = false }
        let client = CoderPadClient(apiKey: draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                    baseURL: draft.resolvedBaseURL)
        if let org = try? await client.organization() {
            orgUsers = org.users
        }
    }

    /// Whether another saved account already uses this key and server, to stop the
    /// same organization being added twice. Compares the trimmed key and the canonical
    /// server identity (so a trailing slash, host case, or explicit default port can't
    /// smuggle in a duplicate, #850), excluding the draft itself so re-validating a
    /// saved account (or changing only its description) never flags it as a clash.
    func duplicateAccountMessage() -> String? {
        let key = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = draft.serverIdentity
        let clashes = AccountsStore.shared.accounts.contains { existing in
            existing.id != draft.id
                && existing.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) == key
                && existing.serverIdentity == server
        }
        guard clashes else { return nil }

        return String(localized: """
        This API key is already added as another account. Each account must use a unique key.
        """)
    }

    func validate() async {
        // Magic demo keys: typing `demo` or `baddemo` into the key field creates a
        // sandbox demo account (mock data, or one whose mock server 401s) instead of
        // validating against CoderPad. This is the discoverable replacement for the old
        // wand menu (#549): the store helpers dedupe an existing demo and make it the active
        // account, so there's nothing to save here; just dismiss the editor.
        if let demo = Account.DemoMagicKey(typedKey: draft.apiKey) {
            switch demo {
            case .mockData: AccountsStore.shared.addDemoIfMissing()
            case .badKey: AccountsStore.shared.addDemoBadKeyIfMissing()
            }
            onCancel()
            return
        }
        // A non-empty but malformed Server URL must not silently fall back to the
        // hosted endpoint: validating there would send this (possibly self-hosted)
        // API key to the wrong host (#849). Reject locally, before any network call.
        if draft.hasMalformedBaseURLOverride {
            validation = .invalid(String(localized: """
            The Server URL isn't a valid web address. Enter a full URL starting with https://, \
            or leave the field blank to use the standard CoderPad server.
            """))
            return
        }
        // Reject a key that's already saved before hitting the network, so the user
        // gets immediate feedback rather than adding a duplicate organization.
        if let message = duplicateAccountMessage() {
            validation = .invalid(message)
            return
        }
        let fingerprint = currentValidationFingerprint
        validation = .validating
        scopeWarning = nil
        do {
            let client = CoderPadClient(apiKey: fingerprint.apiKey, baseURL: fingerprint.baseURL)
            let org = try await client.organization()
            guard await applyValidatedOrganization(org, client: client, fingerprint: fingerprint) else { return }
        } catch {
            guard validationStillMatches(fingerprint) else { return }

            validation = .invalid(friendlyValidationMessage(for: error))
        }
    }

    /// After the key proves it can reach the org, probe the main read endpoints
    /// with one lightweight request each and report any that return a 403, so the
    /// user learns up front that, e.g., Questions will be empty rather than hitting
    /// a silent empty section later. Non-blocking: the account still validates and
    /// saves. Network/other errors are not treated as missing scopes.
    func missingScopesWarning(client: CoderPadClient) async -> String? {
        func authorized(_ probe: () async throws -> Void) async -> Bool {
            do {
                try await probe()
                return true
            } catch let error as CoderPadError where error.isUnauthorized {
                return false
            } catch {
                return true
            }
        }
        /// One page proves read access without pulling the whole list.
        func firstPage(_ stream: AsyncThrowingStream<[some Any], any Error>) async throws {
            for try await _ in stream {
                return
            }
        }
        async let padsOK = authorized { try await firstPage(client.listPadsIncrementally()) }
        async let questionsOK = authorized { try await firstPage(client.listQuestionsIncrementally()) }
        async let quotaOK = authorized { _ = try await client.quota() }

        var missing: [String] = []
        if await padsOK == false { missing.append(String(localized: "Pads")) }
        if await questionsOK == false { missing.append(String(localized: "Questions")) }
        if await quotaOK == false { missing.append(String(localized: "Quota")) }
        guard !missing.isEmpty else { return nil }

        let list = missing.joined(separator: ", ")
        return String(localized: "This key works, but isn't authorized for: \(list). Those sections may be empty.")
    }

    /// Derives the signed-in user's email from their own pads. `/api/pads/` is scoped
    /// to the API key owner, so the most common owner email on the first page is "you".
    /// Returns nil if the user has no pads yet (e.g. a brand-new account), letting the
    /// caller fall back to the manual picker. Non-fatal: validation already succeeded.
    func detectUserEmail(client: CoderPadClient) async -> String? {
        do {
            for try await page in client.listPadsIncrementally() {
                let emails = page.map(\.ownerEmail).filter { !$0.isEmpty }
                guard !emails.isEmpty else { return nil }

                let counts = Dictionary(emails.map { ($0, 1) }, uniquingKeysWith: +)
                return counts.max { $0.value < $1.value }?.key
            }
        } catch {
            // Ignore: the picker remains available as a fallback.
        }
        return nil
    }
}
