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
        // Case-insensitive, like every other path that matches these addresses: the
        // picker de-duplicates on a folded key, so an address differing only in case
        // resolved to a row here but lost its display name (#2197).
        let match = orgUsers.first { $0.email.caseInsensitiveCompare(email) == .orderedSame }
        if let name = match?.name, !name.isEmpty {
            return "\(name) · \(email)"
        }
        return email
    }

    var validateDisabled: Bool {
        draft.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
            || validation == .validating
            || validationThrottle.isCoolingDown
    }

    /// Runs a validation, replacing any still in flight.
    func startValidation() {
        guard !validateDisabled else { return }

        validationTask?.cancel()
        validationTask = Task { await validate() }
    }

    /// Abandons a running validation and clears its published results, so editing the
    /// key or Server URL stops the probes rather than only ignoring them (#2194).
    func cancelValidation() {
        validationTask?.cancel()
        validationTask = nil
        validation = .idle
        scopeWarning = nil
        resetValidationThrottle()
    }

    @ViewBuilder
    var validateButton: some View {
        // When Save is available it owns the default action (Return); otherwise Validate
        // is the primary call to action, so only one button claims the shortcut.
        if canSave {
            Button("Validate") { startValidation() }
                .buttonStyle(.glass)
                .disabled(validateDisabled)
        } else {
            Button("Validate") { startValidation() }
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

        // An explicit validation failure blocks saving even when the credentials are
        // back to their stored values. Otherwise a saved account whose check had just
        // failed kept autosaving its other fields while the editor showed the failure,
        // which reads as the app ignoring the error (#2199).
        if case .invalid = validation { return false }

        return isValidated || credentialsUnchanged
    }

    /// Whether the draft's credentials still match what is stored, comparing the way
    /// the duplicate-account check does.
    ///
    /// The key used to be compared raw while the duplicate check trimmed it, so adding
    /// a trailing space to an unchanged key demanded a fresh validation that the
    /// duplicate check simultaneously treated as no change at all (#2198).
    var credentialsUnchanged: Bool {
        guard isEditing else { return false }

        let key = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedKey = initialAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (draft.baseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let storedBase = (initialBaseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return key == storedKey && base == storedBase
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

    func descriptionChanged() {
        nameEditGeneration &+= 1
        commitLiveEdit()
    }

    /// Persists the current draft when autosave is allowed and the draft is in a valid
    /// saveable state. Called after the debounce and when the editor disappears, so a
    /// quick navigation away does not drop the latest valid edit.
    func persistLiveEditIfPossible() {
        guard commitsLive, canSave else { return }

        // The account must still exist. A debounced autosave can fire after the user
        // deleted the account (or dismissed the editor and then deleted it), and
        // `onSave` on a removed id re-creates it from the stale draft (#2191).
        guard AccountsStore.shared.accounts.contains(where: { $0.id == draft.id }) else { return }

        finalizeNameIfNeeded()
        guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        onSave(draft.normalizedForStorage)
    }

    /// Persists the draft now, cancelling any debounced autosave first.
    ///
    /// An explicit Save did not cancel the pending task, so an older scheduled draft
    /// could land afterwards and overwrite the newer fields the user had just saved
    /// (#2192).
    func saveNow() {
        liveCommitTask?.cancel()
        liveCommitTask = nil
        finalizeNameIfNeeded()
        onSave(draft.normalizedForStorage)
    }

    @ViewBuilder
    var saveButton: some View {
        let save = { saveNow() }
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
        guard isEditing, !isValidated, orgUsers.isEmpty, !isLoadingMembers,
              !draft.hasMalformedBaseURLOverride else { return }

        isLoadingMembers = true
        memberLoadError = nil
        defer { isLoadingMembers = false }
        let fingerprint = currentValidationFingerprint
        let client = CoderPadClient(apiKey: fingerprint.apiKey, baseURL: fingerprint.baseURL)
        do {
            let org = try await client.organization()
            guard validationStillMatches(fingerprint) else { return }

            orgUsers = org.users
        } catch {
            guard validationStillMatches(fingerprint) else { return }

            memberLoadError = String(localized: "Couldn’t load organization members. Reopen to try again.")
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
        let validatedNameGeneration = nameEditGeneration
        validation = .validating
        scopeWarning = nil
        do {
            let client = CoderPadClient(apiKey: fingerprint.apiKey, baseURL: fingerprint.baseURL)
            let org = try await client.organization()
            guard await applyValidatedOrganization(
                org,
                client: client,
                fingerprint: fingerprint,
                nameGeneration: validatedNameGeneration
            ) else { return }

            resetValidationThrottle()
        } catch {
            guard validationStillMatches(fingerprint) else { return }

            validation = .invalid(friendlyValidationMessage(for: error))
            beginValidationCooldown()
        }
    }
}
